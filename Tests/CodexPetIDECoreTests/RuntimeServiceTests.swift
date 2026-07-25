import Foundation
import XCTest
@testable import CodexPetIDECore

final class RuntimeServiceTests: XCTestCase {
    private var root: URL!
    private var workspace: WorkspaceService!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexInnerIDE-Runtime-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        workspace = try WorkspaceService(rootURL: root)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    func testParsesJavaPackageNames() {
        XCTAssertEqual(
            RuntimeService.javaPackageName("// header\npackage com.example.app;\npublic class Main {}"),
            "com.example.app"
        )
        XCTAssertNil(RuntimeService.javaPackageName("public class Main {}"))
    }

    func testParsesDiagnosticSeverityPerMatch() async throws {
        let service = RuntimeService(
            client: AppServerClient(executableURL: URL(fileURLWithPath: "/usr/bin/false"), workingDirectoryURL: root),
            workspace: workspace
        )
        let file = root.appendingPathComponent("Main.java")
        let output = """
        \(file.path):4: warning: unchecked conversion
        \(file.path):9: error: cannot find symbol
        """

        let diagnostics = await service.parseDiagnostics(
            output,
            languageID: "java",
            fallbackPath: "Main.java"
        )

        XCTAssertEqual(diagnostics.map(\.relativePath), ["Main.java", "Main.java"])
        XCTAssertEqual(diagnostics.map(\.line), [4, 9])
        XCTAssertEqual(diagnostics.map(\.severity), ["warning", "error"])
        XCTAssertEqual(diagnostics.map(\.message), ["unchecked conversion", "cannot find symbol"])
    }

    func testDiagnosticsCannotEscapeWorkspace() async throws {
        let service = RuntimeService(
            client: AppServerClient(executableURL: URL(fileURLWithPath: "/usr/bin/false"), workingDirectoryURL: root),
            workspace: workspace
        )
        let diagnostics = await service.parseDiagnostics(
            "/private/tmp/outside.ts(3,7): error TS2304: Cannot find name 'missing'.",
            languageID: "typescript",
            fallbackPath: "src/app.ts"
        )

        XCTAssertEqual(diagnostics.first?.relativePath, "src/app.ts")
        XCTAssertEqual(diagnostics.first?.line, 3)
        XCTAssertEqual(diagnostics.first?.column, 7)
    }

    func testRuntimeOutputReconcilerRestoresBufferedOutputWithoutDuplicatingStreamedText() {
        XCTAssertEqual(
            RuntimeOutputReconciler.unstreamedSuffix(
                returned: "hello world\n",
                streamed: ""
            ),
            "hello world\n"
        )
        XCTAssertEqual(
            RuntimeOutputReconciler.unstreamedSuffix(
                returned: "hello world\n",
                streamed: "hello world\n"
            ),
            ""
        )
        XCTAssertEqual(
            RuntimeOutputReconciler.unstreamedSuffix(
                returned: "hello world\nsecond line\n",
                streamed: "hello world\n"
            ),
            "second line\n"
        )
        XCTAssertEqual(
            RuntimeOutputReconciler.unstreamedSuffix(
                returned: "hello world\n",
                streamed: "prefix\nhello world\n"
            ),
            ""
        )
    }
}

final class PreviewServiceTests: XCTestCase {
    private var root: URL!
    private var workspace: WorkspaceService!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexInnerIDE-Preview-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        workspace = try WorkspaceService(rootURL: root)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    func testServesEncodedWorkspacePathWithRestrictedPolicy() async throws {
        let directory = root.appendingPathComponent("web page", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("<h1>Local preview</h1>".utf8)
            .write(to: directory.appendingPathComponent("index #1.html"))
        let service = PreviewService(workspace: workspace)
        defer { service.stop() }

        let descriptor = try await service.descriptor(
            relativePath: "web page/index #1.html",
            languageID: "html"
        )
        let url = try XCTUnwrap(descriptor.url.flatMap(URL.init(string:)))
        let (data, response) = try await URLSession.shared.data(from: url)
        let http = try XCTUnwrap(response as? HTTPURLResponse)

        XCTAssertEqual(http.statusCode, 200)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "<h1>Local preview</h1>")
        XCTAssertEqual(http.value(forHTTPHeaderField: "Cache-Control"), "no-store")
        XCTAssertEqual(http.value(forHTTPHeaderField: "X-Content-Type-Options"), "nosniff")
        XCTAssertTrue(http.value(forHTTPHeaderField: "Content-Security-Policy")?.contains("connect-src 'none'") == true)
    }

    func testCSSUsesNearestHTMLAndMarkdownDoesNotStartServer() async throws {
        let nested = root.appendingPathComponent("site", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("<link rel=\"stylesheet\" href=\"styles.css\">".utf8)
            .write(to: nested.appendingPathComponent("index.html"))
        try Data("body {}".utf8).write(to: nested.appendingPathComponent("styles.css"))
        try Data("# Preview".utf8).write(to: root.appendingPathComponent("README.md"))
        let service = PreviewService(workspace: workspace)
        defer { service.stop() }

        let css = try await service.descriptor(relativePath: "site/styles.css", languageID: "css")
        let markdown = try await service.descriptor(relativePath: "README.md", languageID: "markdown")

        XCTAssertEqual(css.entryRelativePath, "site/index.html")
        XCTAssertNotNil(css.url)
        XCTAssertEqual(markdown.content, "# Preview")
        XCTAssertNil(markdown.url)
    }

    func testPreviewRejectsTraversal() async throws {
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexInnerIDE-Outside-\(UUID().uuidString).html")
        try Data("secret".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        let service = PreviewService(workspace: workspace)
        defer { service.stop() }

        do {
            _ = try await service.descriptor(relativePath: "../\(outside.lastPathComponent)", languageID: "html")
            XCTFail("Expected traversal to be rejected")
        } catch {
            switch error as? InnerIDEError {
            case .invalidRelativePath, .pathEscapesWorkspace:
                break
            default:
                XCTFail("Expected an invalid or escaping path rejection, got \(error)")
            }
        }
    }
}
