import Foundation

public struct RendererAssets: Sendable {
    public let script: String
    public let style: String

    public init(script: String, style: String) {
        self.script = script
        self.style = style
    }

    public static func load(from resourcesURL: URL) throws -> RendererAssets {
        let rendererURL = resourcesURL.appendingPathComponent("Renderer", isDirectory: true)
        let manifestURL = rendererURL.appendingPathComponent("manifest.json")
        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode([String: String].self, from: manifestData)
        let script = try verifiedResource(named: "ide.js", in: rendererURL, manifest: manifest)
        let style = try verifiedResource(named: "ide.css", in: rendererURL, manifest: manifest)
        guard let scriptText = String(data: script, encoding: .utf8),
              let styleText = String(data: style, encoding: .utf8)
        else {
            throw InnerIDEError.rendererAssetsMissing
        }
        return RendererAssets(script: scriptText, style: styleText)
    }

    private static func verifiedResource(
        named name: String,
        in directory: URL,
        manifest: [String: String]
    ) throws -> Data {
        guard let expected = manifest[name] else { throw InnerIDEError.rendererAssetsMissing }
        let data = try Data(contentsOf: directory.appendingPathComponent(name))
        guard WorkspaceService.sha256(data) == expected else {
            throw InnerIDEError.rendererAssetsMissing
        }
        return data
    }

    public func document(bridgeScript: String, browserMode: Bool) -> String {
        let nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let script = Self.escapeClosingTag(self.script, tag: "script")
        let bridge = Self.escapeClosingTag(bridgeScript, tag: "script")
        let style = Self.escapeClosingTag(self.style, tag: "style")
        let connectSource = browserMode ? "'self'" : "'none'"
        return """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width,initial-scale=1">
          <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'nonce-\(nonce)' blob:; style-src 'unsafe-inline'; img-src data: blob:; font-src data:; worker-src blob:; child-src blob:; frame-src http://127.0.0.1:* blob: data:; connect-src \(connectSource); base-uri 'none'; form-action 'none'; object-src 'none'">
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
