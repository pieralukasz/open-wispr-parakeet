import Foundation

/// Manages the user LaunchAgent that starts the dictation daemon at login.
///
/// Only the plist is written — no `launchctl` call. launchd picks up
/// `~/Library/LaunchAgents` at the next login, which is exactly when the job
/// should run, and skipping the bootstrap avoids starting a second daemon
/// alongside the one the user is already running.
public enum LaunchAtLogin {
    public static let label = "com.human37.open-wispr"

    public enum Failure: LocalizedError {
        case executableNotInAppBundle

        public var errorDescription: String? {
            switch self {
            case .executableNotInAppBundle:
                return "Autostart needs the binary inside OpenWispr.app, because macOS "
                    + "binds Microphone and Accessibility grants to the app bundle. "
                    + "Run OpenWispr.app/Contents/MacOS/open-wispr instead."
            }
        }
    }

    public static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    public static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    /// Executable to record in the LaunchAgent, or nil when the running binary
    /// sits outside an app bundle (a bare CLI build, or a symlink on PATH).
    public static func defaultExecutablePath() -> String? {
        guard let path = Bundle.main.executableURL?.resolvingSymlinksInPath().path,
              path.contains(".app/Contents/MacOS/") else { return nil }
        return path
    }

    public static func makePlistData(executablePath: String) throws -> Data {
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executablePath, "start"],
            "RunAtLoad": true,
            // Marks the job as user-facing so launchd does not throttle its CPU.
            "ProcessType": "Interactive",
        ]
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }

    public static func enable(executablePath: String? = defaultExecutablePath()) throws {
        guard let executablePath else { throw Failure.executableNotInAppBundle }

        let directory = plistURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try makePlistData(executablePath: executablePath).write(to: plistURL)
    }

    public static func disable() throws {
        guard isEnabled else { return }
        try FileManager.default.removeItem(at: plistURL)
    }
}
