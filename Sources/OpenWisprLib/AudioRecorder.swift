import AVFoundation
import CoreAudio
import CoreMedia
import Foundation
import ScreenCaptureKit

private let transcriptionFormat = AVAudioFormat(
    commonFormat: .pcmFormatFloat32,
    sampleRate: 16_000,
    channels: 1,
    interleaved: false
)!

private let transcriptionFileSettings: [String: Any] = [
    AVFormatIDKey: kAudioFormatLinearPCM,
    AVSampleRateKey: 16_000,
    AVNumberOfChannelsKey: 1,
    AVLinearPCMBitDepthKey: 16,
    AVLinearPCMIsFloatKey: false,
    AVLinearPCMIsBigEndianKey: false,
]

private final class MonoAudioFileSink {
    private let lock = NSLock()
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private var converterInputFormat: AVAudioFormat?

    init(url: URL) throws {
        file = try AVAudioFile(
            forWriting: url,
            settings: transcriptionFileSettings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard let file else { return }

        if buffer.format == transcriptionFormat {
            try? file.write(from: buffer)
            return
        }

        if converter == nil || converterInputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: transcriptionFormat)
            converterInputFormat = buffer.format
        }
        guard let converter else { return }

        let ratio = transcriptionFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * ratio)) + 32
        guard let converted = AVAudioPCMBuffer(
            pcmFormat: transcriptionFormat,
            frameCapacity: capacity
        ) else { return }

        var suppliedInput = false
        var conversionError: NSError?
        converter.convert(to: converted, error: &conversionError) { _, status in
            if suppliedInput {
                status.pointee = .noDataNow
                return nil
            }
            suppliedInput = true
            status.pointee = .haveData
            return buffer
        }

        if conversionError == nil && converted.frameLength > 0 {
            try? file.write(from: converted)
        }
    }

    func close() {
        lock.lock()
        file = nil
        converter = nil
        converterInputFormat = nil
        lock.unlock()
    }
}

private final class SystemAudioStreamOutput: NSObject, SCStreamOutput {
    let sink: MonoAudioFileSink

    init(sink: MonoAudioFileSink) {
        self.sink = sink
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .audio, sampleBuffer.isValid else { return }

        try? sampleBuffer.withAudioBufferList { audioBufferList, _ in
            guard let description = sampleBuffer.formatDescription?.audioStreamBasicDescription,
                  let format = AVAudioFormat(
                    standardFormatWithSampleRate: description.mSampleRate,
                    channels: description.mChannelsPerFrame
                  ),
                  let pcmBuffer = AVAudioPCMBuffer(
                    pcmFormat: format,
                    bufferListNoCopy: audioBufferList.unsafePointer
                  ) else { return }
            sink.append(pcmBuffer)
        }
    }
}

class AudioRecorder {
    private let systemAudioQueue = DispatchQueue(
        label: "com.human37.open-wispr.system-audio",
        qos: .userInitiated
    )
    private var audioEngine: AVAudioEngine?
    private var microphoneSink: MonoAudioFileSink?
    private var systemAudioSink: MonoAudioFileSink?
    private var systemAudioOutput: SystemAudioStreamOutput?
    private var systemAudioStream: SCStream?
    private var isRecording = false
    private var currentOutputURL: URL?
    private var microphoneOutputURL: URL?
    private var systemAudioOutputURL: URL?

    var preferredDeviceID: AudioDeviceID?
    var captureSource: AudioCaptureSource = .microphone

    /// Stop and release all capture resources. Call before changing source/device or on shutdown.
    func teardown() {
        if isRecording {
            audioEngine?.inputNode.removeTap(onBus: 0)
        }
        audioEngine?.stop()
        audioEngine = nil

        systemAudioStream?.stopCapture { _ in }
        systemAudioStream = nil
        systemAudioOutput = nil
        microphoneSink?.close()
        systemAudioSink?.close()
        microphoneSink = nil
        systemAudioSink = nil
        cleanupTemporarySources()

        isRecording = false
        currentOutputURL = nil
    }

    /// Release capture resources after changing source/device or waking from sleep.
    func reload() {
        teardown()
    }

    func startRecording(to outputURL: URL) async throws {
        guard !isRecording else { return }

        currentOutputURL = outputURL
        let urls = sourceURLs(for: outputURL, source: captureSource)
        microphoneOutputURL = urls.microphone
        systemAudioOutputURL = urls.systemAudio

        do {
            try Task.checkCancellation()
            if captureSource.includesSystemAudio, let systemURL = systemAudioOutputURL {
                try await startSystemAudioRecording(to: systemURL)
            }
            try Task.checkCancellation()
            if captureSource.includesMicrophone, let microphoneURL = microphoneOutputURL {
                try startMicrophoneRecording(to: microphoneURL)
            }
            isRecording = true
        } catch {
            teardown()
            throw error
        }
    }

    func stopRecording() async -> URL? {
        guard isRecording, let outputURL = currentOutputURL else { return nil }
        isRecording = false

        if captureSource.includesMicrophone {
            audioEngine?.inputNode.removeTap(onBus: 0)
            audioEngine?.stop()
            audioEngine = nil
            microphoneSink?.close()
            microphoneSink = nil
        }

        if let stream = systemAudioStream {
            try? await stream.stopCapture()
            await withCheckedContinuation { continuation in
                systemAudioQueue.async {
                    continuation.resume()
                }
            }
            systemAudioSink?.close()
            systemAudioSink = nil
            systemAudioOutput = nil
            systemAudioStream = nil
        }

        currentOutputURL = nil

        if captureSource == .microphoneAndSystemAudio,
           let microphoneURL = microphoneOutputURL,
           let systemAudioURL = systemAudioOutputURL {
            do {
                try mixAudioFiles(
                    microphoneURL: microphoneURL,
                    systemAudioURL: systemAudioURL,
                    outputURL: outputURL
                )
            } catch {
                print("Warning: failed to mix microphone and system audio: \(error.localizedDescription)")
                try? FileManager.default.removeItem(at: outputURL)
                try? FileManager.default.copyItem(at: microphoneURL, to: outputURL)
            }
            cleanupTemporarySources()
        }

        microphoneOutputURL = nil
        systemAudioOutputURL = nil
        return outputURL
    }

    private func startMicrophoneRecording(to outputURL: URL) throws {
        if audioEngine == nil {
            let engine = AVAudioEngine()
            if let deviceID = preferredDeviceID,
               deviceID != AudioDeviceManager.getDefaultInputDeviceID() {
                setInputDevice(deviceID, on: engine)
            }
            _ = engine.inputNode
            engine.prepare()
            audioEngine = engine
        }

        guard let engine = audioEngine else {
            throw AudioCaptureError.microphoneEngineUnavailable
        }

        let sink = try MonoAudioFileSink(url: outputURL)
        let inputFormat = engine.inputNode.outputFormat(forBus: 0)
        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            sink.append(buffer)
        }

        do {
            try engine.start()
            microphoneSink = sink
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            sink.close()
            throw error
        }
    }

    /// ScreenCaptureKit reports a missing Screen Recording grant as an
    /// SCStreamErrorDomain error whose message is the unreadable "The user declined
    /// TCCs for application, window, display capture". The grant is re-checked
    /// instead of matching on the error code alone, because the same condition also
    /// arrives under other codes when the grant is revoked mid-session.
    private static func mapSystemAudioError(_ error: Error) -> Error {
        let nsError = error as NSError
        guard nsError.domain == SCStreamErrorDomain else { return error }
        guard nsError.code == SCStreamError.Code.userDeclined.rawValue
            || !Permissions.hasScreenRecording else {
            return error
        }
        return AudioCaptureError.screenRecordingPermissionRequired
    }

    private func startSystemAudioRecording(to outputURL: URL) async throws {
        guard Permissions.ensureScreenRecording() else {
            throw AudioCaptureError.screenRecordingPermissionRequired
        }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
        } catch {
            throw Self.mapSystemAudioError(error)
        }

        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() })
            ?? content.displays.first else {
            throw AudioCaptureError.noDisplayAvailable
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 16_000
        configuration.channelCount = 1
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.queueDepth = 1

        let sink = try MonoAudioFileSink(url: outputURL)
        let output = SystemAudioStreamOutput(sink: sink)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: systemAudioQueue)

        do {
            try await stream.startCapture()
            systemAudioSink = sink
            systemAudioOutput = output
            systemAudioStream = stream
        } catch {
            sink.close()
            throw Self.mapSystemAudioError(error)
        }
    }

    private func sourceURLs(
        for outputURL: URL,
        source: AudioCaptureSource
    ) -> (microphone: URL?, systemAudio: URL?) {
        switch source {
        case .microphone:
            return (outputURL, nil)
        case .systemAudio:
            return (nil, outputURL)
        case .microphoneAndSystemAudio:
            let directory = outputURL.deletingLastPathComponent()
            let token = UUID().uuidString
            return (
                directory.appendingPathComponent(".open-wispr-\(token)-microphone.wav"),
                directory.appendingPathComponent(".open-wispr-\(token)-system.wav")
            )
        }
    }

    private func mixAudioFiles(
        microphoneURL: URL,
        systemAudioURL: URL,
        outputURL: URL
    ) throws {
        let microphoneFile = try AVAudioFile(
            forReading: microphoneURL,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        let systemFile = try AVAudioFile(
            forReading: systemAudioURL,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        let outputFile = try AVAudioFile(
            forWriting: outputURL,
            settings: transcriptionFileSettings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        let chunkSize: AVAudioFrameCount = 4096
        let microphoneBuffer = AVAudioPCMBuffer(
            pcmFormat: transcriptionFormat,
            frameCapacity: chunkSize
        )!
        let systemBuffer = AVAudioPCMBuffer(
            pcmFormat: transcriptionFormat,
            frameCapacity: chunkSize
        )!
        let mixedBuffer = AVAudioPCMBuffer(
            pcmFormat: transcriptionFormat,
            frameCapacity: chunkSize
        )!

        while microphoneFile.framePosition < microphoneFile.length
            || systemFile.framePosition < systemFile.length {
            microphoneBuffer.frameLength = 0
            systemBuffer.frameLength = 0
            if microphoneFile.framePosition < microphoneFile.length {
                try microphoneFile.read(into: microphoneBuffer, frameCount: chunkSize)
            }
            if systemFile.framePosition < systemFile.length {
                try systemFile.read(into: systemBuffer, frameCount: chunkSize)
            }

            let frameCount = max(microphoneBuffer.frameLength, systemBuffer.frameLength)
            guard frameCount > 0,
                  let microphoneSamples = microphoneBuffer.floatChannelData?[0],
                  let systemSamples = systemBuffer.floatChannelData?[0],
                  let mixedSamples = mixedBuffer.floatChannelData?[0] else { break }

            mixedBuffer.frameLength = frameCount
            for index in 0..<Int(frameCount) {
                let microphone = index < Int(microphoneBuffer.frameLength)
                    ? microphoneSamples[index] : 0
                let system = index < Int(systemBuffer.frameLength)
                    ? systemSamples[index] : 0
                mixedSamples[index] = max(-1, min(1, (microphone + system) * 0.5))
            }
            try outputFile.write(from: mixedBuffer)
        }
    }

    private func cleanupTemporarySources() {
        guard captureSource == .microphoneAndSystemAudio else { return }
        for url in [microphoneOutputURL, systemAudioOutputURL].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: url)
        }
        microphoneOutputURL = nil
        systemAudioOutputURL = nil
    }

    private func setInputDevice(_ deviceID: AudioDeviceID, on engine: AVAudioEngine) {
        guard let audioUnit = engine.inputNode.audioUnit else {
            print("Warning: could not access audio unit to set input device")
            return
        }

        var devID = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &devID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if status != noErr {
            print("Warning: failed to set audio input device (status: \(status))")
        }
    }
}
