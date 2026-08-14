import AppKit
import AVFoundation
import ApplicationServices
import Foundation

struct Permissions {
    static func ensureMicrophone() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            print("Microphone: granted")
        case .notDetermined:
            print("Microphone: requesting...")
            let semaphore = DispatchSemaphore(value: 0)
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                print("Microphone: \(granted ? "granted" : "denied")")
                semaphore.signal()
            }
            semaphore.wait()
        default:
            print("Microphone: denied — grant in System Settings → Privacy & Security → Microphone")
        }
    }

    static func promptAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static var hasScreenRecording: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// macOS shows the Screen Recording prompt at most once per app; later calls
    /// return false without asking, so a user who declined has to be sent to
    /// System Settings instead of being re-prompted.
    @discardableResult
    static func ensureScreenRecording() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            print("Screen Recording: granted")
            return true
        }
        print("Screen Recording: requesting...")
        let granted = CGRequestScreenCaptureAccess()
        print("Screen Recording: \(granted ? "granted" : "denied")")
        return granted
    }

    static func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
