import Foundation
import XCTest
@testable import CodexPetIDECore

final class IDEWebServerTests: XCTestCase {
    func testWaitUntilReadyAllowsDelayedBrowserStartup() async {
        let server = IDEWebServer(
            rendererAssets: RendererAssets(script: "", style: ""),
            sessionToken: "test-token"
        ) { request in
            .success(request.requestId)
        }
        let clientId = UUID().uuidString.lowercased()

        async let ready = server.waitUntilReady(
            clientId: clientId,
            timeout: .milliseconds(250)
        )
        try? await Task.sleep(for: .milliseconds(50))
        server.markReady(clientId: clientId)

        let didBecomeReady = await ready
        XCTAssertTrue(didBecomeReady)
    }

    func testWaitUntilReadyStillFailsClosedAfterTimeout() async {
        let server = IDEWebServer(
            rendererAssets: RendererAssets(script: "", style: ""),
            sessionToken: "test-token"
        ) { request in
            .success(request.requestId)
        }

        let didBecomeReady = await server.waitUntilReady(
            clientId: UUID().uuidString.lowercased(),
            timeout: .milliseconds(20)
        )
        XCTAssertFalse(didBecomeReady)
    }

    func testLoopbackDocumentDoesNotEmbedSessionTokenAndRPCRequiresAuthentication() async throws {
        let token = UUID().uuidString.lowercased()
        let server = IDEWebServer(
            rendererAssets: RendererAssets(
                script: "document.getElementById('root').textContent = 'ready'",
                style: "body { margin: 0 }"
            ),
            sessionToken: token
        ) { request in
            .success(request.requestId, data: .object(["method": .string(request.method)]))
        }
        let pageURL = try await server.start()
        defer { server.stop() }
        var rootComponents = try XCTUnwrap(URLComponents(url: pageURL, resolvingAgainstBaseURL: false))
        rootComponents.fragment = nil
        let rootURL = try XCTUnwrap(rootComponents.url)

        let (document, documentResponse) = try await URLSession.shared.data(from: rootURL)
        XCTAssertEqual((documentResponse as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertFalse(String(decoding: document, as: UTF8.self).contains(token))
        XCTAssertTrue(String(decoding: document, as: UTF8.self).contains("hostMode: 'browser'"))

        let clientId = UUID().uuidString.lowercased()
        let bridgeRequest = BridgeRequest(
            version: 1,
            requestId: "authorized",
            sessionToken: token,
            clientId: clientId,
            method: "workspace.current",
            params: .object([:])
        )
        let origin = "\(pageURL.scheme!)://\(pageURL.host!):\(pageURL.port!)"
        let rpcURL = try XCTUnwrap(URL(string: "\(origin)/api/v1/rpc"))
        var authorized = URLRequest(url: rpcURL)
        authorized.httpMethod = "POST"
        authorized.httpBody = try JSONEncoder().encode(bridgeRequest)
        authorized.setValue("application/json", forHTTPHeaderField: "Content-Type")
        authorized.setValue(token, forHTTPHeaderField: "X-Codex-IDE-Token")
        authorized.setValue(clientId, forHTTPHeaderField: "X-Codex-IDE-Client")
        authorized.setValue(origin, forHTTPHeaderField: "Origin")
        let (responseData, response) = try await URLSession.shared.data(for: authorized)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(
            try JSONDecoder().decode(BridgeResponse.self, from: responseData).data?["method"]?.stringValue,
            "workspace.current"
        )

        var rejected = authorized
        rejected.setValue("https://example.com", forHTTPHeaderField: "Origin")
        let (_, rejectedResponse) = try await URLSession.shared.data(for: rejected)
        XCTAssertEqual((rejectedResponse as? HTTPURLResponse)?.statusCode, 403)
    }

    func testParserEnforcesSixteenMiBBoundaryAndRejectsTraversal() throws {
        let tooLarge = Data([
            "POST /api/v1/rpc HTTP/1.1",
            "Host: 127.0.0.1",
            "Content-Length: \(IDEWebServer.maximumRequestBytes + 1)",
            "",
            ""
        ].joined(separator: "\r\n").utf8)
        XCTAssertThrowsError(try IDEHTTPRequest.parseIfComplete(
            tooLarge,
            maximumHeaderBytes: IDEWebServer.maximumHeaderBytes,
            maximumBodyBytes: IDEWebServer.maximumRequestBytes
        )) { error in
            XCTAssertEqual((error as? IDEHTTPError)?.status, 413)
        }

        let traversal = Data([
            "GET /%2e%2e/secret HTTP/1.1",
            "Host: 127.0.0.1",
            "",
            ""
        ].joined(separator: "\r\n").utf8)
        XCTAssertThrowsError(try IDEHTTPRequest.parseIfComplete(
            traversal,
            maximumHeaderBytes: IDEWebServer.maximumHeaderBytes,
            maximumBodyBytes: IDEWebServer.maximumRequestBytes
        ))
    }
}
