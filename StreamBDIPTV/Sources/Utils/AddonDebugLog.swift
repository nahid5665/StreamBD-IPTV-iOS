import Foundation

/// In-memory ring buffer of addon-pipeline diagnostics, viewable in-app
/// (Settings → Addon Diagnostics) so sideloaded builds can be debugged
/// without a Mac attached.
final class AddonDebugLog {
    static let shared = AddonDebugLog()
    private var lines: [String] = []
    private let lock = NSLock()
    private let maxLines = 500

    private init() {}

    func append(_ line: String) {
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        lock.lock()
        defer { lock.unlock() }
        lines.append("[\(stamp)] \(line)")
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return lines.joined(separator: "\n")
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        lines.removeAll()
    }
}

/// Central debug-logging helper: prints to console AND the in-app buffer.
/// Calls are gated on AppConfig.debugAddonLogging.
func addonLog(_ message: String) {
    guard AppConfig.debugAddonLogging else { return }
    print(message)
    AddonDebugLog.shared.append(message)
}
