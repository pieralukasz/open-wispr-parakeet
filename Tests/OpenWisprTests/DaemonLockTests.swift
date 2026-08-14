import XCTest
@testable import OpenWisprLib

final class DaemonLockTests: XCTestCase {
    private func temporaryLockURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("open-wispr-lock-\(UUID().uuidString)")
    }

    func testAcquireSucceedsWhenNoDaemonHoldsTheLock() {
        let url = temporaryLockURL()
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertTrue(DaemonLock.acquire(at: url))
    }

    func testAcquireFailsWhileTheLockIsAlreadyHeld() {
        let url = temporaryLockURL()
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertTrue(DaemonLock.acquire(at: url))
        XCTAssertFalse(DaemonLock.acquire(at: url))
    }

    func testAcquireCreatesMissingParentDirectory() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-wispr-lock-dir-\(UUID().uuidString)")
        let url = directory.appendingPathComponent("daemon.lock")
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertTrue(DaemonLock.acquire(at: url))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}
