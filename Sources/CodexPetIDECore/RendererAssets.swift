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
}
