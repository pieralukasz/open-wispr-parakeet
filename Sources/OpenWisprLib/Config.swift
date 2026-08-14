import Foundation

public struct LanguageOption: Equatable, Sendable {
    public let code: String
    public let name: String
}

public enum AudioCaptureSource: String, Codable, CaseIterable, Sendable {
    case microphone
    case systemAudio
    case microphoneAndSystemAudio

    public var displayName: String {
        switch self {
        case .microphone: return "Microphone"
        case .systemAudio: return "System Audio"
        case .microphoneAndSystemAudio: return "Microphone + System Audio"
        }
    }

    public var includesMicrophone: Bool {
        self != .systemAudio
    }

    public var includesSystemAudio: Bool {
        self != .microphone
    }
}

public struct Config: Codable {
    public var hotkeys: [HotkeyConfig]
    public var language: String
    public var spokenPunctuation: FlexBool?
    public var maxRecordings: Int?
    public var toggleMode: FlexBool?
    public var audioCaptureSource: AudioCaptureSource
    public var audioInputDeviceID: UInt32?
    public var audioInputDeviceUID: String?
    /// Set once the daemon has offered to start OpenWispr at login, so the
    /// question is asked a single time regardless of the answer.
    public var launchAtLoginPrompted: FlexBool?

    public var hotkey: HotkeyConfig {
        get { hotkeys[0] }
        set { hotkeys = Config.deduplicateHotkeys([newValue]) }
    }

    public func hotkeySummary() -> String {
        hotkeys
            .map { KeyCodes.describe(keyCode: $0.keyCode, modifiers: $0.modifiers) }
            .joined(separator: " · ")
    }

    private static func deduplicateHotkeys(_ list: [HotkeyConfig]) -> [HotkeyConfig] {
        var out: [HotkeyConfig] = []
        for hotkey in list where !out.contains(hotkey) {
            out.append(hotkey)
        }
        return out
    }

    private enum CodingKeys: String, CodingKey {
        case hotkey
        case hotkeys
        case language
        case spokenPunctuation
        case maxRecordings
        case toggleMode
        case audioCaptureSource
        case audioInputDeviceID
        case audioInputDeviceUID
        case launchAtLoginPrompted
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let hotkeysList = try container.decodeIfPresent([HotkeyConfig].self, forKey: .hotkeys)
        let legacyHotkey = try container.decodeIfPresent(HotkeyConfig.self, forKey: .hotkey)
        if let list = hotkeysList, !list.isEmpty {
            hotkeys = Config.deduplicateHotkeys(list)
        } else if let legacyHotkey {
            hotkeys = [legacyHotkey]
        } else {
            hotkeys = [HotkeyConfig(keyCode: 63, modifiers: [])]
        }

        let requestedLanguage = try container.decodeIfPresent(String.self, forKey: .language) ?? "en"
        language = Config.supportedLanguages.contains(where: { $0.code == requestedLanguage })
            ? requestedLanguage
            : "auto"
        spokenPunctuation = try container.decodeIfPresent(FlexBool.self, forKey: .spokenPunctuation)
        maxRecordings = try container.decodeIfPresent(Int.self, forKey: .maxRecordings)
        toggleMode = try container.decodeIfPresent(FlexBool.self, forKey: .toggleMode)
        audioCaptureSource = try container.decodeIfPresent(
            AudioCaptureSource.self,
            forKey: .audioCaptureSource
        ) ?? .microphone
        audioInputDeviceID = try container.decodeIfPresent(UInt32.self, forKey: .audioInputDeviceID)
        audioInputDeviceUID = try container.decodeIfPresent(String.self, forKey: .audioInputDeviceUID)
        launchAtLoginPrompted = try container.decodeIfPresent(
            FlexBool.self,
            forKey: .launchAtLoginPrompted
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hotkeys, forKey: .hotkeys)
        try container.encode(hotkeys[0], forKey: .hotkey)
        try container.encode(language, forKey: .language)
        try container.encodeIfPresent(spokenPunctuation, forKey: .spokenPunctuation)
        try container.encodeIfPresent(maxRecordings, forKey: .maxRecordings)
        try container.encodeIfPresent(toggleMode, forKey: .toggleMode)
        try container.encode(audioCaptureSource, forKey: .audioCaptureSource)
        try container.encodeIfPresent(audioInputDeviceID, forKey: .audioInputDeviceID)
        try container.encodeIfPresent(audioInputDeviceUID, forKey: .audioInputDeviceUID)
        try container.encodeIfPresent(launchAtLoginPrompted, forKey: .launchAtLoginPrompted)
    }

    public init(
        hotkeys: [HotkeyConfig],
        language: String,
        spokenPunctuation: FlexBool?,
        maxRecordings: Int?,
        toggleMode: FlexBool?,
        audioCaptureSource: AudioCaptureSource = .microphone,
        audioInputDeviceID: UInt32? = nil,
        audioInputDeviceUID: String? = nil,
        launchAtLoginPrompted: FlexBool? = nil
    ) {
        self.hotkeys = hotkeys.isEmpty
            ? [HotkeyConfig(keyCode: 63, modifiers: [])]
            : Config.deduplicateHotkeys(hotkeys)
        self.language = language
        self.spokenPunctuation = spokenPunctuation
        self.maxRecordings = maxRecordings
        self.toggleMode = toggleMode
        self.audioCaptureSource = audioCaptureSource
        self.audioInputDeviceID = audioInputDeviceID
        self.audioInputDeviceUID = audioInputDeviceUID
        self.launchAtLoginPrompted = launchAtLoginPrompted
    }

    /// Languages supported by Parakeet TDT v3 in the pinned FluidAudio revision.
    public static let supportedLanguages: [LanguageOption] = [
        LanguageOption(code: "auto", name: "Auto-Detect"),
        LanguageOption(code: "en", name: "English"),
        LanguageOption(code: "pl", name: "Polish"),
        LanguageOption(code: "es", name: "Spanish"),
        LanguageOption(code: "fr", name: "French"),
        LanguageOption(code: "de", name: "German"),
        LanguageOption(code: "it", name: "Italian"),
        LanguageOption(code: "pt", name: "Portuguese"),
        LanguageOption(code: "ro", name: "Romanian"),
        LanguageOption(code: "nl", name: "Dutch"),
        LanguageOption(code: "da", name: "Danish"),
        LanguageOption(code: "sv", name: "Swedish"),
        LanguageOption(code: "fi", name: "Finnish"),
        LanguageOption(code: "hu", name: "Hungarian"),
        LanguageOption(code: "et", name: "Estonian"),
        LanguageOption(code: "lv", name: "Latvian"),
        LanguageOption(code: "lt", name: "Lithuanian"),
        LanguageOption(code: "mt", name: "Maltese"),
        LanguageOption(code: "cs", name: "Czech"),
        LanguageOption(code: "sk", name: "Slovak"),
        LanguageOption(code: "sl", name: "Slovenian"),
        LanguageOption(code: "hr", name: "Croatian"),
        LanguageOption(code: "bs", name: "Bosnian"),
        LanguageOption(code: "ru", name: "Russian"),
        LanguageOption(code: "uk", name: "Ukrainian"),
        LanguageOption(code: "be", name: "Belarusian"),
        LanguageOption(code: "bg", name: "Bulgarian"),
        LanguageOption(code: "sr", name: "Serbian"),
        LanguageOption(code: "el", name: "Greek"),
    ]

    public static let defaultMaxRecordings = 0

    public static func effectiveMaxRecordings(_ value: Int?) -> Int {
        let raw = value ?? Config.defaultMaxRecordings
        if raw == 0 { return 0 }
        return min(max(1, raw), 100)
    }

    public static let defaultConfig = Config(
        hotkeys: [HotkeyConfig(keyCode: 63, modifiers: [])],
        language: "en",
        spokenPunctuation: FlexBool(false),
        maxRecordings: nil,
        toggleMode: FlexBool(false)
    )

    public static var configDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/open-wispr")
    }

    public static var configFile: URL {
        configDir.appendingPathComponent("config.json")
    }

    public static func load() -> Config {
        guard let data = try? Data(contentsOf: configFile) else {
            let config = Config.defaultConfig
            try? config.save()
            return config
        }

        do {
            let config = try JSONDecoder().decode(Config.self, from: data)
            if containsDeprecatedEngineSettings(data) {
                try? config.save()
            }
            return config
        } catch {
            fputs("Warning: unable to parse \(configFile.path): \(error.localizedDescription)\n", stderr)
            return Config.defaultConfig
        }
    }

    public static func decode(from data: Data) throws -> Config {
        try JSONDecoder().decode(Config.self, from: data)
    }

    public func save() throws {
        try FileManager.default.createDirectory(
            at: Config.configDir,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        try encoder.encode(self).write(to: Config.configFile)
    }

    private static func containsDeprecatedEngineSettings(_ data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        let deprecatedKeys = [
            "modelPath",
            "modelSize",
            "transcriptionBackend",
            "whisperPrompt",
        ]
        return deprecatedKeys.contains(where: { json[$0] != nil })
    }
}

public struct FlexBool: Codable {
    public let value: Bool

    public init(_ value: Bool) { self.value = value }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let string = try? container.decode(String.self) {
            value = ["true", "yes", "1"].contains(string.lowercased())
        } else if let integer = try? container.decode(Int.self) {
            value = integer != 0
        } else {
            value = false
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

public struct HotkeyConfig: Codable, Equatable {
    public var keyCode: UInt16
    public var modifiers: [String]

    public init(keyCode: UInt16, modifiers: [String]) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public var modifierFlags: UInt64 {
        var flags: UInt64 = 0
        for modifier in modifiers {
            switch modifier.lowercased() {
            case "cmd", "command": flags |= UInt64(1 << 20)
            case "shift": flags |= UInt64(1 << 17)
            case "ctrl", "control": flags |= UInt64(1 << 18)
            case "opt", "option", "alt": flags |= UInt64(1 << 19)
            default: break
            }
        }
        return flags
    }
}
