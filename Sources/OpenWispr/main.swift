import AppKit
import Foundation
import OpenWisprLib

setvbuf(stdout, nil, _IOLBF, 0)
setvbuf(stderr, nil, _IOLBF, 0)

let version = OpenWispr.version

func printUsage() {
    print("""
    open-wispr v\(version) — Local Parakeet v3 voice dictation for macOS

    USAGE:
        open-wispr start                Start the dictation daemon
        open-wispr set-hotkey <key>     Set the push-to-talk hotkey
        open-wispr get-hotkey           Show current hotkey
        open-wispr set-language <code>  Set the language (e.g. pl, en, auto)
        open-wispr transcribe-file <path>  Transcribe a local audio file with Parakeet v3
        open-wispr enable-autostart     Start the daemon automatically at login
        open-wispr disable-autostart    Stop starting the daemon at login
        open-wispr status               Show configuration and status
        open-wispr --help               Show this help message

    HOTKEY EXAMPLES:
        open-wispr set-hotkey globe             Globe/fn key (default)
        open-wispr set-hotkey rightoption        Right Option key
        open-wispr set-hotkey rightcmd           Right Command key
        open-wispr set-hotkey f5                 F5 key
        open-wispr set-hotkey ctrl+space         Ctrl + Space
    """)
}

func cmdStart() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let delegate = AppDelegate()
    app.delegate = delegate

    signal(SIGINT) { _ in
        print("\nStopping open-wispr...")
        exit(0)
    }

    app.run()
}

func cmdSetHotkey(_ keyString: String) {
    guard let parsed = KeyCodes.parse(keyString) else {
        print("Error: Unknown key '\(keyString)'")
        print("Run 'open-wispr --help' for examples")
        exit(1)
    }

    var config = Config.load()
    config.hotkey = HotkeyConfig(keyCode: parsed.keyCode, modifiers: parsed.modifiers)

    do {
        try config.save()
        let description = KeyCodes.describe(
            keyCode: parsed.keyCode,
            modifiers: parsed.modifiers
        )
        print("Hotkey set to: \(description)")
    } catch {
        print("Error saving config: \(error.localizedDescription)")
        exit(1)
    }
}

func cmdSetLanguage(_ language: String) {
    let validCodes = Config.supportedLanguages.map(\.code)
    guard validCodes.contains(language) else {
        print("Error: Unknown language '\(language)'")
        print("Available: \(validCodes.joined(separator: ", "))")
        exit(1)
    }

    var config = Config.load()
    config.language = language

    do {
        try config.save()
        let name = Config.supportedLanguages.first(where: { $0.code == language })?.name
            ?? language
        print("Language set to: \(name) (\(language))")
    } catch {
        print("Error saving config: \(error.localizedDescription)")
        exit(1)
    }
}

/// Resolves the bundled binary the LaunchAgent should run. Falls back to the
/// installed OpenWispr.app when the CLI was invoked through a symlink on PATH,
/// since a LaunchAgent pointing outside the bundle loses its TCC grants.
func autostartExecutablePath() -> String? {
    if let path = LaunchAtLogin.defaultExecutablePath() { return path }
    return AppBundleLaunch.findOpenWisprAppBundle()?
        .appendingPathComponent("Contents/MacOS/open-wispr").path
}

func cmdEnableAutostart() {
    guard let executablePath = autostartExecutablePath() else {
        print("Error: OpenWispr.app not found — install it before enabling autostart.")
        exit(1)
    }

    do {
        try LaunchAtLogin.enable(executablePath: executablePath)
        print("Autostart enabled: \(LaunchAtLogin.plistURL.path)")
        print("Takes effect at the next login; the running daemon is left alone.")
    } catch {
        print("Error: \(error.localizedDescription)")
        exit(1)
    }
}

func cmdDisableAutostart() {
    do {
        try LaunchAtLogin.disable()
        print("Autostart disabled")
    } catch {
        print("Error: \(error.localizedDescription)")
        exit(1)
    }
}

func cmdGetHotkey() {
    print("Current hotkey: \(Config.load().hotkeySummary())")
}

func cmdStatus() {
    let config = Config.load()
    let languageName = Config.supportedLanguages
        .first(where: { $0.code == config.language })?.name ?? config.language
    let toggleMode = config.toggleMode?.value ?? false

    print("open-wispr v\(version)")
    print("Config:      \(Config.configFile.path)")
    print("Hotkey:      \(config.hotkeySummary())")
    print("Engine:      Parakeet v3")
    print("Audio input: \(config.audioCaptureSource.displayName)")
    print("Language:    \(languageName) (\(config.language))")
    print("Toggle:      \(toggleMode ? "on (press to start/stop)" : "off (hold to talk)")")
    print("Autostart:   \(LaunchAtLogin.isEnabled ? "on (starts at login)" : "off")")
}

func cmdTranscribeFile(_ path: String) {
    let audioURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    guard FileManager.default.fileExists(atPath: audioURL.path) else {
        print("Error: Audio file not found: \(audioURL.path)")
        exit(1)
    }

    let config = Config.load()
    let transcriber = ParakeetTranscriber(language: config.language)
    transcriber.spokenPunctuation = config.spokenPunctuation?.value ?? false

    do {
        try transcriber.prepare()
        print(try transcriber.transcribe(audioURL: audioURL))
    } catch {
        print("Error: \(error.localizedDescription)")
        exit(1)
    }
}

let args = CommandLine.arguments
let rawCommand = args.count > 1 ? args[1] : nil
let command: String? = {
    if let rawCommand, rawCommand.hasPrefix("-psn_") { return "start" }
    return rawCommand
}()

switch command {
case "start":
    if AppBundleLaunch.relaunchThroughAppBundleIfNeeded() {
        exit(0)
    }
    cmdStart()
case "set-hotkey":
    guard args.count > 2 else {
        print("Usage: open-wispr set-hotkey <key>")
        exit(1)
    }
    cmdSetHotkey(args[2])
case "set-language":
    guard args.count > 2 else {
        print("Usage: open-wispr set-language <code>")
        print("Examples: pl, en, auto")
        exit(1)
    }
    cmdSetLanguage(args[2])
case "get-hotkey":
    cmdGetHotkey()
case "enable-autostart":
    cmdEnableAutostart()
case "disable-autostart":
    cmdDisableAutostart()
case "status":
    cmdStatus()
case "transcribe-file":
    guard args.count > 2 else {
        print("Usage: open-wispr transcribe-file <audio-path>")
        exit(1)
    }
    cmdTranscribeFile(args[2])
case "--help", "-h", "help":
    printUsage()
case nil:
    printUsage()
default:
    print("Unknown command: \(command!)")
    printUsage()
    exit(1)
}
