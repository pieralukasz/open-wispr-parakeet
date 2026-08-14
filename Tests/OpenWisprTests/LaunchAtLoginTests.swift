import XCTest
@testable import OpenWisprLib

final class LaunchAtLoginTests: XCTestCase {

    private func decodePlist(executablePath: String) throws -> [String: Any] {
        let data = try LaunchAtLogin.makePlistData(executablePath: executablePath)
        let plist = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        )
        return try XCTUnwrap(plist as? [String: Any])
    }

    // MARK: - Plist contents

    func testPlistRunsTheGivenExecutableWithStart() throws {
        let path = "/Users/tester/Applications/OpenWispr.app/Contents/MacOS/open-wispr"

        let plist = try decodePlist(executablePath: path)

        XCTAssertEqual(plist["ProgramArguments"] as? [String], [path, "start"])
    }

    func testPlistUsesTheBundleIdentifierAsLabel() throws {
        let plist = try decodePlist(executablePath: "/tmp/open-wispr")

        XCTAssertEqual(plist["Label"] as? String, "com.human37.open-wispr")
        XCTAssertEqual(LaunchAtLogin.label, "com.human37.open-wispr")
    }

    func testPlistRunsAtLoadAsAnInteractiveJob() throws {
        let plist = try decodePlist(executablePath: "/tmp/open-wispr")

        XCTAssertEqual(plist["RunAtLoad"] as? Bool, true)
        XCTAssertEqual(plist["ProcessType"] as? String, "Interactive")
    }

    func testPlistOmitsKeepAliveSoQuitIsRespected() throws {
        let plist = try decodePlist(executablePath: "/tmp/open-wispr")

        XCTAssertNil(plist["KeepAlive"])
    }

    // MARK: - Plist location

    func testPlistLivesInTheUserLaunchAgentsDirectory() {
        let expected = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.human37.open-wispr.plist")

        XCTAssertEqual(LaunchAtLogin.plistURL, expected)
    }

    // MARK: - Enable failure path

    func testEnableRejectsAnExecutableOutsideAnAppBundle() {
        XCTAssertThrowsError(try LaunchAtLogin.enable(executablePath: nil)) { error in
            XCTAssertEqual(error as? LaunchAtLogin.Failure, .executableNotInAppBundle)
        }
    }
}
