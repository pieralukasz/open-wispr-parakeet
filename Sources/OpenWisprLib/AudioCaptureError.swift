import Foundation

public enum AudioCaptureError: LocalizedError, Equatable {
    case screenRecordingPermissionRequired
    case noDisplayAvailable
    case microphoneEngineUnavailable

    public var errorDescription: String? {
        switch self {
        case .screenRecordingPermissionRequired:
            return "System audio capture needs Screen Recording permission. Grant OpenWispr in "
                + "System Settings → Privacy & Security → Screen & System Audio Recording, "
                + "then restart OpenWispr."
        case .noDisplayAvailable:
            return "No display is available for system audio capture"
        case .microphoneEngineUnavailable:
            return "Microphone audio engine is not available"
        }
    }

    /// The status bar menu renders one line, so `errorDescription` is too long for it.
    public var shortDescription: String {
        switch self {
        case .screenRecordingPermissionRequired: return "Screen Recording permission needed"
        case .noDisplayAvailable: return "No display for system audio"
        case .microphoneEngineUnavailable: return "Microphone unavailable"
        }
    }
}
