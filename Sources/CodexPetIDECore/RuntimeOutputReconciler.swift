import Foundation

enum RuntimeOutputReconciler {
    static func unstreamedSuffix(returned: String, streamed: String) -> String {
        guard !returned.isEmpty else { return "" }
        guard !streamed.isEmpty else { return returned }
        if returned == streamed || streamed.contains(returned) {
            return ""
        }
        if returned.hasPrefix(streamed) {
            return String(returned.dropFirst(streamed.count))
        }
        return returned
    }
}
