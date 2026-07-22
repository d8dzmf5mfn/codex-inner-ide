import AppKit
import CodexPetIDECore
import Foundation

@MainActor
final class QuickChatHandoffController {
    private let launcher: CodexLauncher

    init(launcher: CodexLauncher) {
        self.launcher = launcher
    }

    func handoff(
        prompt: String,
        mainSession: CDPSession,
        port: Int?,
        mainTargetID: String?
    ) async -> HandoffResult {
        activateCodex()
        _ = try? await mainSession.send(method: "Page.bringToFront")
        if await dispatchQuickChatShortcut(mainSession),
           await fillQuickChatComposer(
               prompt,
               mainSession: mainSession,
               port: port,
               mainTargetID: mainTargetID,
               timeout: 5
           ) {
            return HandoffResult(destination: .chatgpt, mechanism: .quickChatShortcut)
        }

        let signal = try? await mainSession.evaluate(InjectionScripts.activateQuickChatSignal())
        if signal?["ok"]?.boolValue == true,
           await fillQuickChatComposer(
               prompt,
               mainSession: mainSession,
               port: port,
               mainTargetID: mainTargetID,
               timeout: 5
           ) {
            return HandoffResult(destination: .chatgpt, mechanism: .compatibilitySignal)
        }
        return copyToClipboard(prompt, destination: .chatgpt)
    }

    func copyToClipboard(
        _ prompt: String,
        destination: HandoffDestination
    ) -> HandoffResult {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        return HandoffResult(destination: destination, mechanism: .clipboard)
    }

    private func dispatchQuickChatShortcut(_ session: CDPSession) async -> Bool {
        do {
            let common: [String: JSONValue] = [
                "modifiers": .number(5),
                "key": .string("n"),
                "code": .string("KeyN"),
                "windowsVirtualKeyCode": .number(78),
                "nativeVirtualKeyCode": .number(45)
            ]
            _ = try await session.send(
                method: "Input.dispatchKeyEvent",
                params: common.merging(["type": .string("rawKeyDown")]) { _, new in new }
            )
            _ = try await session.send(
                method: "Input.dispatchKeyEvent",
                params: common.merging(["type": .string("keyUp")]) { _, new in new }
            )
            return true
        } catch {
            return false
        }
    }

    private func fillQuickChatComposer(
        _ prompt: String,
        mainSession: CDPSession,
        port: Int?,
        mainTargetID: String?,
        timeout: TimeInterval
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var candidateSessions: [String: CDPSession] = [:]

        while Date() < deadline {
            if let result = try? await mainSession.evaluate(
                InjectionScripts.quickChatComposerHandoff(prompt: prompt)
            ), result["ok"]?.boolValue == true {
                await closeCandidateSessions(candidateSessions)
                return true
            }

            if let port,
               let targets = try? await CDPTargetDiscovery.listTargets(port: port) {
                for target in targets where target.id != mainTargetID && candidateSessions[target.id] == nil {
                    guard let session = try? CDPSession(target: target, port: port) else { continue }
                    do {
                        try await session.connect()
                        candidateSessions[target.id] = session
                    } catch {
                        await session.close()
                    }
                }
                for session in candidateSessions.values {
                    if let result = try? await session.evaluate(
                        InjectionScripts.quickChatComposerHandoff(prompt: prompt)
                    ), result["ok"]?.boolValue == true {
                        await closeCandidateSessions(candidateSessions)
                        return true
                    }
                }
            }
            try? await Task.sleep(for: .milliseconds(200))
        }

        await closeCandidateSessions(candidateSessions)
        return false
    }

    private func closeCandidateSessions(_ sessions: [String: CDPSession]) async {
        for session in sessions.values { await session.close() }
    }

    private func activateCodex() {
        let application = launcher.launchedApplication ?? launcher.runningApplications.first
        application?.activate(options: [])
    }
}
