import Foundation

/// Single-instance guard for the dictation daemon. Without it, opening
/// OpenWispr.app while the LaunchAgent copy is running registers a second global
/// listener for the same hotkey.
public enum DaemonLock {
    public static var defaultLockURL: URL {
        Config.configDir.appendingPathComponent("daemon.lock")
    }

    /// The descriptor is left open for the lifetime of the process on purpose: the
    /// kernel drops the flock when the process exits, so a crashed daemon cannot
    /// leave a stale lock that blocks the next start.
    public static func acquire(at url: URL = defaultLockURL) -> Bool {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let descriptor = open(url.path, O_CREAT | O_RDWR, 0o644)
        // An unusable lock file must not stop dictation from starting.
        guard descriptor >= 0 else { return true }

        if flock(descriptor, LOCK_EX | LOCK_NB) == 0 { return true }
        close(descriptor)
        return false
    }
}
