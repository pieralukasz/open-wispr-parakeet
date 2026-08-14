import FluidAudio
import Foundation

public final class ParakeetTranscriber: @unchecked Sendable {
    private static let engine = ParakeetEngine()
    private let languageCode: String
    public var spokenPunctuation = false

    public init(language: String) {
        self.languageCode = language
    }

    public func prepare() throws {
        try Self.engine.prepare()
    }

    public func transcribe(audioURL: URL) throws -> String {
        try Self.engine.transcribe(audioURL: audioURL, languageCode: languageCode)
    }
}

private final class BlockingResult<Value>: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var result: Result<Value, Error>?

    func resolve(_ result: Result<Value, Error>) {
        lock.lock()
        self.result = result
        lock.unlock()
        semaphore.signal()
    }

    func wait() throws -> Value {
        semaphore.wait()
        lock.lock()
        defer { lock.unlock() }
        return try result!.get()
    }
}

private func blockingAwait<Value: Sendable>(
    _ operation: @escaping @Sendable () async throws -> Value
) throws -> Value {
    let box = BlockingResult<Value>()
    Task.detached(priority: .userInitiated) {
        do {
            box.resolve(.success(try await operation()))
        } catch {
            box.resolve(.failure(error))
        }
    }
    return try box.wait()
}

private final class ParakeetEngine: @unchecked Sendable {
    private let preparationLock = NSLock()
    private var manager: AsrManager?

    func prepare() throws {
        _ = try preparedManager()
    }

    func transcribe(audioURL: URL, languageCode: String) throws -> String {
        let manager = try preparedManager()
        let language = languageCode == "auto" ? nil : Language(rawValue: languageCode)

        return try blockingAwait {
            let layers = await manager.decoderLayerCount
            var decoderState = TdtDecoderState.make(decoderLayers: layers)
            let result = try await manager.transcribe(
                audioURL,
                decoderState: &decoderState,
                language: language
            )
            return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func preparedManager() throws -> AsrManager {
        preparationLock.lock()
        defer { preparationLock.unlock() }

        if let manager { return manager }

        let loaded: AsrManager = try blockingAwait {
            let version = AsrModelVersion.v3
            let models = try await AsrModels.downloadAndLoad(
                version: version,
                encoderPrecision: .int8
            )
            let config = ASRConfig(
                tdtConfig: TdtConfig(blankId: version.blankId),
                encoderHiddenSize: version.encoderHiddenSize,
                melChunkContext: false
            )
            let manager = AsrManager(config: config)
            try await manager.loadModels(models)
            return manager
        }
        manager = loaded
        return loaded
    }
}
