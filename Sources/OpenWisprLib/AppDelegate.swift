import AppKit

public class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBar: StatusBarController!
    var hotkeyManagers: [HotkeyManager] = []
    var recorder: AudioRecorder!
    var transcriber: ParakeetTranscriber!
    var inserter: TextInserter!
    var config: Config!
    var recordingLifecycle = RecordingLifecycle()
    var currentRecordingURL: URL?
    private var recordingStartTask: Task<Bool, Never>?
    private var sleepWakeObservers: [NSObjectProtocol] = []
    private var hasShownScreenRecordingAlert = false
    var isReady = false
    public var lastTranscription: String?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        statusBar = StatusBarController()
        recorder = AudioRecorder()
        registerSleepWakeObservers()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.setup()
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        recordingStartTask?.cancel()
        recorder?.teardown()
        unregisterSleepWakeObservers()
    }

    private func setup() {
        do {
            try setupInner()
        } catch {
            print("Fatal setup error: \(error.localizedDescription)")
        }
    }

    private func setupInner() throws {
        config = Config.load()
        inserter = TextInserter()
        migrateAudioDeviceUIDIfNeeded()
        recorder.preferredDeviceID = AudioDeviceManager.resolveConfiguredDeviceID(
            uid: config.audioInputDeviceUID,
            legacyID: config.audioInputDeviceID
        )
        recorder.captureSource = config.audioCaptureSource
        if Config.effectiveMaxRecordings(config.maxRecordings) == 0 {
            RecordingStore.deleteAllRecordings()
        }
        transcriber = makeParakeetTranscriber(for: config)

        DispatchQueue.main.async {
            self.statusBar.reprocessHandler = { [weak self] url in
                self?.reprocess(audioURL: url)
            }
            self.statusBar.onConfigChange = { [weak self] newConfig in
                self?.applyConfigChange(newConfig)
            }
            self.statusBar.buildMenu()
        }

        if !AXIsProcessTrusted() {
            DispatchQueue.main.async {
                self.statusBar.state = .waitingForPermission
                self.statusBar.buildMenu()
            }
        }

        if config.audioCaptureSource.includesMicrophone {
            Permissions.ensureMicrophone()
        }

        if config.audioCaptureSource.includesSystemAudio {
            Permissions.ensureScreenRecording()
        }

        if !AXIsProcessTrusted() {
            print("Accessibility: not granted")
            Permissions.promptAccessibility()
            Permissions.openAccessibilitySettings()
            print("Waiting for Accessibility permission...")
            while !AXIsProcessTrusted() {
                Thread.sleep(forTimeInterval: 0.5)
            }
            print("Accessibility: granted")
        } else {
            print("Accessibility: granted")
        }

        DispatchQueue.main.async {
            self.statusBar.state = .downloading
            self.statusBar.updateDownloadProgress("Loading Parakeet v3...")
        }
        print("Loading Parakeet v3...")
        try transcriber.prepare()
        DispatchQueue.main.async {
            self.statusBar.updateDownloadProgress(nil)
        }
        print("Parakeet v3 ready.")

        DispatchQueue.main.async { [weak self] in
            self?.startListening()
        }
    }

    private func startListening() {
        for m in hotkeyManagers { m.stop() }
        hotkeyManagers = []
        for hk in config.hotkeys {
            let manager = HotkeyManager(
                keyCode: hk.keyCode,
                modifiers: hk.modifierFlags
            )
            manager.start(
                onKeyDown: { [weak self] in
                    self?.handleKeyDown()
                },
                onKeyUp: { [weak self] in
                    self?.handleKeyUp()
                }
            )
            hotkeyManagers.append(manager)
        }

        isReady = true
        statusBar.state = .idle
        statusBar.buildMenu()

        let hotkeyDesc = config.hotkeySummary()
        print("open-wispr v\(OpenWispr.version)")
        print("Hotkey: \(hotkeyDesc)")
        print("Engine: Parakeet v3")
        print("Ready.")

        promptForLaunchAtLoginIfNeeded()
    }

    /// Offers to install the login LaunchAgent the first time the daemon reaches
    /// a working state. Asking earlier would compete with the Accessibility and
    /// Microphone prompts, and asking after a failed start would be noise.
    private func promptForLaunchAtLoginIfNeeded() {
        guard !(config.launchAtLoginPrompted?.value ?? false),
              !LaunchAtLogin.isEnabled,
              LaunchAtLogin.defaultExecutablePath() != nil else { return }

        let alert = NSAlert()
        alert.messageText = "Start OpenWispr at login?"
        alert.informativeText = "OpenWispr can start automatically when you log in, so the "
            + "dictation hotkey is always ready. You can change this any time from the menu "
            + "bar icon."
        alert.addButton(withTitle: "Start at Login")
        alert.addButton(withTitle: "Not Now")

        NSApp.activate(ignoringOtherApps: true)
        let wantsLaunchAtLogin = alert.runModal() == .alertFirstButtonReturn

        if wantsLaunchAtLogin {
            do {
                try LaunchAtLogin.enable()
            } catch {
                print("Could not enable launch at login: \(error.localizedDescription)")
            }
        }

        var stored = Config.load()
        stored.launchAtLoginPrompted = FlexBool(true)
        do {
            try stored.save()
            config = stored
        } catch {
            print("Could not record the launch-at-login answer: \(error.localizedDescription)")
        }

        statusBar.buildMenu()
    }

    public func reloadConfig() {
        let newConfig = Config.load()
        applyConfigChange(newConfig)
    }

    /// Configs written by older versions store only the numeric AudioDeviceID,
    /// which is not stable across reboots or device replugs. If that ID still
    /// refers to a device, persist its UID so the selection survives.
    private func migrateAudioDeviceUIDIfNeeded() {
        guard config.audioInputDeviceUID == nil,
              let legacyID = config.audioInputDeviceID,
              let uid = AudioDeviceManager.getDeviceUID(deviceID: legacyID) else { return }
        config.audioInputDeviceUID = uid
        try? config.save()
    }

    func applyConfigChange(_ newConfig: Config) {
        guard isReady else { return }
        let newDeviceID = AudioDeviceManager.resolveConfiguredDeviceID(
            uid: newConfig.audioInputDeviceUID,
            legacyID: newConfig.audioInputDeviceID
        )
        let deviceChanged = recorder.preferredDeviceID != newDeviceID
        let sourceChanged = recorder.captureSource != newConfig.audioCaptureSource
        config = newConfig
        recorder.preferredDeviceID = newDeviceID
        recorder.captureSource = newConfig.audioCaptureSource
        if sourceChanged && newConfig.audioCaptureSource.includesMicrophone {
            Permissions.ensureMicrophone()
        }
        let screenRecordingMissing = sourceChanged
            && newConfig.audioCaptureSource.includesSystemAudio
            && !Permissions.ensureScreenRecording()
        if deviceChanged || sourceChanged {
            recorder.reload()
        }
        transcriber = makeParakeetTranscriber(for: config)
        inserter = TextInserter()

        for m in hotkeyManagers { m.stop() }
        hotkeyManagers = []
        for hk in config.hotkeys {
            let manager = HotkeyManager(
                keyCode: hk.keyCode,
                modifiers: hk.modifierFlags
            )
            manager.start(
                onKeyDown: { [weak self] in self?.handleKeyDown() },
                onKeyUp: { [weak self] in self?.handleKeyUp() }
            )
            hotkeyManagers.append(manager)
        }

        statusBar.buildMenu()

        let hotkeyDesc = config.hotkeySummary()
        print("Config updated: engine=parakeet lang=\(config.language) source=\(config.audioCaptureSource.rawValue) hotkey=\(hotkeyDesc)")

        if screenRecordingMissing {
            presentCaptureFailure(AudioCaptureError.screenRecordingPermissionRequired)
        }
    }

    private func makeParakeetTranscriber(for config: Config) -> ParakeetTranscriber {
        let transcriber = ParakeetTranscriber(language: config.language)
        transcriber.spokenPunctuation = config.spokenPunctuation?.value ?? false
        return transcriber
    }

    private func handleKeyDown() {
        guard isReady else { return }

        let isToggle = config.toggleMode?.value ?? false

        switch recordingLifecycle.keyDown(toggleMode: isToggle) {
        case .startRecording:
            handleRecordingStart()
        case .stopRecording:
            handleRecordingStop()
        case .none, .cancelRecording, .prepareRecorder:
            break
        }
    }

    private func handleKeyUp() {
        guard isReady else { return }

        let isToggle = config.toggleMode?.value ?? false

        if recordingLifecycle.keyUp(toggleMode: isToggle) == .stopRecording {
            handleRecordingStop()
        }
    }

    private func handleRecordingStart() {
        statusBar.state = .recording
        let outputURL: URL
        if Config.effectiveMaxRecordings(config.maxRecordings) == 0 {
            outputURL = RecordingStore.tempRecordingURL()
        } else {
            outputURL = RecordingStore.newRecordingURL()
        }
        currentRecordingURL = outputURL

        recordingStartTask = Task { [weak self] in
            guard let self else { return false }
            do {
                try await self.recorder.startRecording(to: outputURL)
                return true
            } catch {
                DispatchQueue.main.async {
                    print("Error: \(error.localizedDescription)")
                    self.recordingLifecycle.recordingStartFailed()
                    RecordingCancellation.discardTrackedPartialRecording(&self.currentRecordingURL)
                    self.presentCaptureFailure(error)
                }
                return false
            }
        }
    }

    /// The status bar renders a single short line, so the full remedy goes into an
    /// alert. It is shown once per launch because every hotkey press hits the same
    /// missing grant and would otherwise stack modals.
    private func presentCaptureFailure(_ error: Error) {
        let captureError = error as? AudioCaptureError
        statusBar.state = .error(captureError?.shortDescription ?? error.localizedDescription)
        statusBar.buildMenu()
        clearErrorStateAfterDelay()

        guard captureError == .screenRecordingPermissionRequired,
              !hasShownScreenRecordingAlert else { return }
        hasShownScreenRecordingAlert = true

        let alert = NSAlert()
        alert.messageText = "Screen Recording permission required"
        alert.informativeText = AudioCaptureError.screenRecordingPermissionRequired.localizedDescription
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            Permissions.openScreenRecordingSettings()
        }
    }

    private func clearErrorStateAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, case .error = self.statusBar.state else { return }
            self.statusBar.state = .idle
            self.statusBar.buildMenu()
        }
    }

    private func handleRecordingStop() {
        statusBar.state = .transcribing
        let startTask = recordingStartTask
        recordingStartTask = nil

        Task { [weak self] in
            guard let self else { return }
            guard await startTask?.value ?? true,
                  let audioURL = await self.recorder.stopRecording() else {
                DispatchQueue.main.async {
                    RecordingCancellation.discardTrackedPartialRecording(&self.currentRecordingURL)
                    if case .error = self.statusBar.state { return }
                    self.statusBar.state = .idle
                    self.statusBar.buildMenu()
                }
                return
            }

            self.currentRecordingURL = nil
            let maxRecordings = Config.effectiveMaxRecordings(self.config.maxRecordings)
            defer {
                if maxRecordings == 0 {
                    try? FileManager.default.removeItem(at: audioURL)
                }
            }
            do {
                let raw = try self.transcriber.transcribe(audioURL: audioURL)
                let text = (self.config.spokenPunctuation?.value ?? false) ? TextPostProcessor.process(raw) : raw
                if maxRecordings > 0 {
                    RecordingStore.prune(maxCount: maxRecordings)
                }
                DispatchQueue.main.async {
                    if !text.isEmpty {
                        self.lastTranscription = text
                        self.inserter.insert(text: text)
                    }
                    self.statusBar.state = .idle
                    self.statusBar.buildMenu()
                }
            } catch {
                if maxRecordings > 0 {
                    RecordingStore.prune(maxCount: maxRecordings)
                }
                DispatchQueue.main.async {
                    print("Error: \(error.localizedDescription)")
                    self.statusBar.state = .error(error.localizedDescription)
                    self.statusBar.buildMenu()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        if case .error = self.statusBar.state {
                            self.statusBar.state = .idle
                            self.statusBar.buildMenu()
                        }
                    }
                }
            }
        }
    }

    func handleSystemWillSleep() {
        guard recordingLifecycle.systemWillSleep() == .cancelRecording else { return }

        recordingStartTask?.cancel()
        recordingStartTask = nil
        recorder.teardown()
        RecordingCancellation.discardTrackedPartialRecording(&currentRecordingURL)
        resetRecordingStatusToIdleIfNeeded()
    }

    func handleSystemDidWake() {
        guard recordingLifecycle.systemDidWake(isReady: isReady) == .prepareRecorder else { return }

        recorder.preferredDeviceID = AudioDeviceManager.resolveConfiguredDeviceID(
            uid: config.audioInputDeviceUID,
            legacyID: config.audioInputDeviceID
        )
        recorder.captureSource = config.audioCaptureSource
        recorder.reload()
    }

    private func registerSleepWakeObservers() {
        guard sleepWakeObservers.isEmpty else { return }

        let center = NSWorkspace.shared.notificationCenter
        sleepWakeObservers = [
            center.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.handleSystemWillSleep()
            },
            center.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.handleSystemDidWake()
            },
        ]
    }

    private func unregisterSleepWakeObservers() {
        let center = NSWorkspace.shared.notificationCenter
        for observer in sleepWakeObservers {
            center.removeObserver(observer)
        }
        sleepWakeObservers = []
    }

    private func resetRecordingStatusToIdleIfNeeded() {
        guard case .recording = statusBar.state else { return }
        statusBar.state = .idle
        statusBar.buildMenu()
    }

    public func reprocess(audioURL: URL) {
        guard case .idle = statusBar.state else { return }

        statusBar.state = .transcribing

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                let raw = try self.transcriber.transcribe(audioURL: audioURL)
                let text = (self.config.spokenPunctuation?.value ?? false) ? TextPostProcessor.process(raw) : raw
                DispatchQueue.main.async {
                    if !text.isEmpty {
                        self.lastTranscription = text
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        self.statusBar.state = .copiedToClipboard
                        self.statusBar.buildMenu()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            self.statusBar.state = .idle
                            self.statusBar.buildMenu()
                        }
                    } else {
                        self.statusBar.state = .idle
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    print("Reprocess error: \(error.localizedDescription)")
                    self.statusBar.state = .idle
                }
            }
        }
    }
}
