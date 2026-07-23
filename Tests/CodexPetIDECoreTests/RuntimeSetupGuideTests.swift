import Foundation
import XCTest
@testable import CodexPetIDECore

final class RuntimeSetupGuideTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexInnerIDE-Setup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    func testShowsHomebrewCommandsOnlyWhenHomebrewIsExecutable() throws {
        let brew = root.appendingPathComponent("brew")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: brew)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: brew.path)

        XCTAssertNotNil(RuntimeSetupGuide.homebrewExecutable(environment: ["PATH": root.path]))
        let brewJava = RuntimeSetupGuide.options(languageID: "java", homebrewAvailable: true)
        XCTAssertEqual(brewJava.first?.command, "brew install openjdk")
        XCTAssertNil(brewJava.first?.downloadURL)

        let downloadJava = RuntimeSetupGuide.options(languageID: "java", homebrewAvailable: false)
        XCTAssertNil(downloadJava.first?.command)
        XCTAssertEqual(downloadJava.first?.downloadURL, RuntimeSetupGuide.javaDownloadURL)
    }

    func testTypeScriptRequiresNodeBeforeOfferingWorkspaceInstall() {
        let nodeFirst = RuntimeSetupGuide.options(
            languageID: "typescript",
            homebrewAvailable: false,
            nodeAvailable: false
        )
        XCTAssertEqual(nodeFirst.first?.downloadURL, RuntimeSetupGuide.nodeDownloadURL)
        XCTAssertEqual(nodeFirst.first?.scope, .system)

        let workspace = RuntimeSetupGuide.options(
            languageID: "typescript",
            homebrewAvailable: true,
            nodeAvailable: true
        )
        XCTAssertEqual(workspace.first?.command, "npm install --save-dev typescript tsx")
        XCTAssertEqual(workspace.first?.scope, .workspace)
    }

    func testJavaCandidatesCoverWorkspaceJavaHomeSystemAndHomebrewPaths() {
        let candidates = RuntimeSetupGuide.javaCompilerCandidates(
            workspaceRoot: root,
            environment: [
                "JAVA_HOME": "/custom/jdk",
                "PATH": "/custom/bin:/usr/bin"
            ]
        ).map(\.path)

        XCTAssertTrue(candidates.contains("/custom/jdk/bin/javac"))
        XCTAssertTrue(candidates.contains(root.appendingPathComponent(".jdk/bin/javac").path))
        XCTAssertTrue(candidates.contains("/opt/homebrew/opt/openjdk/bin/javac"))
        XCTAssertTrue(candidates.contains("/usr/local/opt/openjdk/bin/javac"))
        XCTAssertTrue(candidates.contains("/custom/bin/javac"))
    }

    func testRuntimeDescriptorDecodesLegacyPayloadWithoutSetupOptions() throws {
        let data = Data("""
        {
          "id": "legacy",
          "languageId": "java",
          "label": "Java",
          "version": "17",
          "source": "path",
          "action": "run",
          "available": true
        }
        """.utf8)
        XCTAssertEqual(
            try JSONDecoder().decode(RuntimeDescriptor.self, from: data).setupOptions,
            []
        )
    }
}
