import AppKit
import CodexPetIDECore
import Foundation
import WebKit

@MainActor
protocol IDEWindowControllerDelegate: AnyObject {
    func ideWindowController(
        _ controller: IDEWindowController,
        handle request: BridgeRequest
    ) async -> BridgeResponse

    func ideWindowControllerShouldClose(_ controller: IDEWindowController) async -> Bool
}

@MainActor
final class IDEWindowController: NSWindowController, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate,
    WKScriptMessageHandler
{
    static let defaultSize = NSSize(width: 1180, height: 760)
    static let minimumSize = NSSize(width: 900, height: 600)
    static let bridgeName = "codexInnerIdeBridge"

    weak var delegate: IDEWindowControllerDelegate?

    private let webView: WKWebView
    private let frameAutosaveName: String
    private var allowCloseOnce = false
    private var closeRequestInFlight = false
    private var loaded = false

    init(
        rendererAssets: RendererAssets,
        sessionToken: String,
        workspaceID: String
    ) {
        let userContentController = WKUserContentController()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController = userContentController
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isInspectable = false
        webView.allowsMagnification = true
        webView.allowsBackForwardNavigationGestures = false

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Codex Inner IDE"
        panel.minSize = Self.minimumSize
        panel.level = .normal
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.fullScreenPrimary]
        panel.contentView = webView

        frameAutosaveName = "CodexInnerIDE.Window.\(workspaceID)"
        super.init(window: panel)

        panel.delegate = self
        webView.navigationDelegate = self
        webView.uiDelegate = self
        userContentController.add(self, name: Self.bridgeName)

        if !panel.setFrameUsingName(frameAutosaveName) {
            panel.setContentSize(Self.defaultSize)
            panel.center()
        }
        panel.setFrameAutosaveName(frameAutosaveName)

        let html = Self.document(
            rendererAssets: rendererAssets,
            bridgeScript: InjectionScripts.webViewBridgeBootstrap(sessionToken: sessionToken)
        )
        webView.loadHTMLString(html, baseURL: nil)
        loaded = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        guard loaded else { return }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func setPinned(_ pinned: Bool) {
        guard let panel = window as? NSPanel else { return }
        panel.level = pinned ? .floating : .normal
        panel.isFloatingPanel = pinned
        panel.collectionBehavior = pinned
            ? [.canJoinAllSpaces, .fullScreenAuxiliary]
            : [.fullScreenPrimary]
    }

    func closeImmediately() {
        guard window != nil else { return }
        allowCloseOnce = true
        window?.close()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Self.bridgeName)
    }

    func requestUserClose() {
        window?.performClose(nil)
    }

    func requestSaveAll() async -> Bool {
        await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(
                "Promise.resolve(window.__codexInnerIdeRequestSaveAll?.() ?? false)"
            ) { value, _ in
                continuation.resume(returning: (value as? NSNumber)?.boolValue == true)
            }
        }
    }

    func requestActiveEditContext(
        instruction: String,
        scope: PythonEditScope
    ) async -> ActivePythonEditContext? {
        do {
            let value = try await webView.callAsyncJavaScript(
                """
                const getter = window.__codexInnerIdeGetActiveEditContext;
                if (typeof getter !== "function") return null;
                const value = await getter(instruction, scope);
                return value == null ? null : JSON.stringify(value);
                """,
                arguments: [
                    "instruction": instruction,
                    "scope": scope.rawValue
                ],
                in: nil,
                contentWorld: .page
            )
            guard let text = value as? String,
                  let data = text.data(using: .utf8)
            else { return nil }
            return try JSONDecoder().decode(ActivePythonEditContext.self, from: data)
        } catch {
            return nil
        }
    }

    func emit(type: String, payload: JSONValue) {
        let event = JSONValue.object(["type": .string(type), "payload": payload])
        guard let data = try? JSONEncoder().encode(event),
              let text = String(data: data, encoding: .utf8)
        else { return }
        webView.evaluateJavaScript(
            "window.__codexInnerIdeEmit?.(\(InjectionScripts.javaScriptLiteral(text)))"
        )
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if allowCloseOnce { return true }
        guard !closeRequestInFlight else { return false }
        closeRequestInFlight = true
        Task { [weak self] in
            guard let self else { return }
            let shouldClose = await delegate?.ideWindowControllerShouldClose(self) ?? true
            closeRequestInFlight = false
            if shouldClose {
                allowCloseOnce = true
                sender.performClose(nil)
            }
        }
        return false
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.targetFrame?.isMainFrame == false {
            let url = navigationAction.request.url
            let isLoopbackPreview = url?.scheme == "http" && url?.host == "127.0.0.1"
            let isEmbeddedPreview = ["about", "blob", "data"].contains(url?.scheme ?? "")
            decisionHandler(isLoopbackPreview || isEmbeddedPreview ? .allow : .cancel)
            return
        }
        let isInitialDocument = navigationAction.navigationType == .other
            && (navigationAction.request.url == nil || navigationAction.request.url?.scheme == "about")
        decisionHandler(isInitialDocument ? .allow : .cancel)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        nil
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        guard let window else {
            completionHandler()
            return
        }
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window) { _ in completionHandler() }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        guard let window else {
            completionHandler(false)
            return
        }
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "Confirm")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            completionHandler(response == .alertFirstButtonReturn)
        }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        guard let window else {
            completionHandler(nil)
            return
        }
        let alert = NSAlert()
        alert.messageText = prompt
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(string: defaultText ?? "")
        field.placeholderString = prompt
        field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = field

        alert.beginSheetModal(for: window) { response in
            completionHandler(response == .alertFirstButtonReturn ? field.stringValue : nil)
        }
        window.makeFirstResponder(field)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.bridgeName,
              JSONSerialization.isValidJSONObject(message.body),
              let data = try? JSONSerialization.data(withJSONObject: message.body),
              let request = try? JSONDecoder().decode(BridgeRequest.self, from: data)
        else { return }

        Task { [weak self] in
            guard let self else { return }
            let response = await delegate?.ideWindowController(self, handle: request)
                ?? BridgeResponse.failure(
                    request.requestId,
                    error: InnerIDEError.bridgeRejected("window controller is disconnected")
                )
            deliver(response)
        }
    }

    private func deliver(_ response: BridgeResponse) {
        guard let data = try? JSONEncoder().encode(response),
              let text = String(data: data, encoding: .utf8)
        else { return }
        webView.evaluateJavaScript(
            "window.__codexInnerIdeResolve?.(\(InjectionScripts.javaScriptLiteral(text)))"
        )
    }

    private static func document(rendererAssets: RendererAssets, bridgeScript: String) -> String {
        let nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let script = escapeClosingTag(rendererAssets.script, tag: "script")
        let bridge = escapeClosingTag(bridgeScript, tag: "script")
        let style = escapeClosingTag(rendererAssets.style, tag: "style")
        return """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width,initial-scale=1">
          <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'nonce-\(nonce)' blob:; style-src 'unsafe-inline'; img-src data: blob:; font-src data:; worker-src blob:; child-src blob:; frame-src http://127.0.0.1:* blob: data:; connect-src 'none'; base-uri 'none'; form-action 'none'">
          <title>Codex Inner IDE</title>
          <style>\(style)</style>
        </head>
        <body>
          <div id="root"></div>
          <script nonce="\(nonce)">
            (() => {
              const root = document.getElementById('root');
              const showFailure = (reason) => {
                if (!root || root.childElementCount > 0) return;
                const message = reason instanceof Error ? reason.message : String(reason || 'Unknown renderer error');
                root.innerHTML = `
                  <main style="box-sizing:border-box;display:grid;place-items:center;min-height:100vh;padding:32px;background:#f7f7f5;color:#252525;font:14px -apple-system,BlinkMacSystemFont,sans-serif">
                    <section style="max-width:560px;border:1px solid #dddcd7;border-radius:14px;background:white;padding:24px;box-shadow:0 10px 36px rgba(0,0,0,.08)">
                      <h1 style="font-size:18px;margin:0 0 10px">Codex Inner IDE could not start</h1>
                      <p style="line-height:1.5;margin:0;color:#61615d">${message}</p>
                    </section>
                  </main>`;
              };
              window.addEventListener('error', (event) => showFailure(event.error || event.message));
              window.addEventListener('unhandledrejection', (event) => showFailure(event.reason));
              window.setTimeout(() => showFailure('The renderer did not mount within 5 seconds.'), 5000);
            })();
          </script>
          <script nonce="\(nonce)">\(bridge)</script>
          <script nonce="\(nonce)">\(script)</script>
        </body>
        </html>
        """
    }

    private static func escapeClosingTag(_ value: String, tag: String) -> String {
        value.replacingOccurrences(
            of: "</\(tag)",
            with: "<\\/\(tag)",
            options: [.caseInsensitive]
        )
    }
}
