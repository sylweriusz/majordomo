@preconcurrency import AVFoundation
import Foundation

struct RecordedAudioCapture: Sendable {
    let pcmData: Data
    let sampleRate: Double
    let channelCount: AVAudioChannelCount
    let startedAt: Date

    var fileName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return "dictation-\(formatter.string(from: startedAt)).wav"
    }

    func writeWAV(to url: URL) throws {
        let sampleRateValue = UInt32(sampleRate.rounded())
        let channelCountValue = UInt16(channelCount)
        let bitsPerSample = UInt16(32)
        let bytesPerSample = UInt16(MemoryLayout<Float>.size)
        let blockAlign = channelCountValue * bytesPerSample
        let byteRate = sampleRateValue * UInt32(blockAlign)
        let dataChunkSize = UInt32(pcmData.count)
        let riffChunkSize = UInt32(36) + dataChunkSize

        var data = Data()
        data.append(Data("RIFF".utf8))
        data.append(littleEndianBytes(riffChunkSize))
        data.append(Data("WAVE".utf8))
        data.append(Data("fmt ".utf8))
        data.append(littleEndianBytes(UInt32(16)))
        data.append(littleEndianBytes(UInt16(3)))
        data.append(littleEndianBytes(channelCountValue))
        data.append(littleEndianBytes(sampleRateValue))
        data.append(littleEndianBytes(byteRate))
        data.append(littleEndianBytes(blockAlign))
        data.append(littleEndianBytes(bitsPerSample))
        data.append(Data("data".utf8))
        data.append(littleEndianBytes(dataChunkSize))
        data.append(pcmData)
        try data.write(to: url, options: .atomic)
    }

    private func littleEndianBytes<T: FixedWidthInteger>(_ value: T) -> Data {
        var littleEndianValue = value.littleEndian
        return withUnsafeBytes(of: &littleEndianValue) { Data($0) }
    }
}

enum AudioRecorderError: LocalizedError {
    case microphoneDenied
    case noInputFormat
    case conversionUnavailable
    case engineStartFailed(String)

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            L10n.text("error.audio.mic_permission")
        case .noInputFormat:
            L10n.text("error.audio.no_input_format")
        case .conversionUnavailable:
            L10n.text("error.audio.conversion_unavailable")
        case .engineStartFailed(let message):
            L10n.text("error.audio.start_failed", message)
        }
    }
}

private final class AudioRecorderCaptureSink: @unchecked Sendable {
    let shouldCapture: Bool
    private let lock = NSLock()
    private var data = Data()

    init(shouldCapture: Bool) {
        self.shouldCapture = shouldCapture
    }

    func append(_ chunk: Data) {
        guard shouldCapture, !chunk.isEmpty else { return }
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func snapshot() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

private final class AudioConverterInputState: @unchecked Sendable {
    var consumedInput = false
}

@MainActor
final class AudioRecorder {
    private let engine = AVAudioEngine()
    private let silentMixer = AVAudioMixerNode()
    private var visualizer: MicVisualizer?
    private var captureSink: AudioRecorderCaptureSink?
    private var captureStartDate: Date?
    private var captureFormat: AVAudioFormat?
    private let tapCompletionGroup = DispatchGroup()

    var isRecording: Bool {
        engine.isRunning
    }

    var needsMicrophonePermissionPrompt: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined
    }

    init() {
        engine.attach(silentMixer)
    }

    func start(
        levelsHandler: @escaping @MainActor ([Float]) -> Void,
        sampleHandler: @escaping @Sendable (Data) -> Void,
        captureAudio: Bool = false
    ) async throws {
        try await requestMicrophoneAccess()
        _ = stop()

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw AudioRecorderError.noInputFormat
        }
        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioRecorderError.conversionUnavailable
        }

        let visualizer = MicVisualizer()
        let captureSink = AudioRecorderCaptureSink(shouldCapture: captureAudio)
        self.visualizer = visualizer
        self.captureSink = captureSink
        self.captureStartDate = Date()
        self.captureFormat = targetFormat

        engine.connect(inputNode, to: silentMixer, format: inputFormat)
        silentMixer.outputVolume = 0.001

        inputNode.installTap(
            onBus: 0,
            bufferSize: 1024,
            format: inputFormat,
            block: makeTapHandler(
                visualizer: visualizer,
                converter: converter,
                targetFormat: targetFormat,
                captureSink: captureSink,
                sampleHandler: sampleHandler,
                levelsHandler: levelsHandler
            )
        )

        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            engine.disconnectNodeOutput(inputNode)
            self.visualizer = nil
            self.captureSink = nil
            self.captureStartDate = nil
            self.captureFormat = nil
            throw AudioRecorderError.engineStartFailed(error.localizedDescription)
        }
    }

    func stop() -> RecordedAudioCapture? {
        if engine.isRunning {
            engine.stop()
        }
        engine.inputNode.removeTap(onBus: 0)
        engine.disconnectNodeOutput(engine.inputNode)

        // Wait for all in-flight tap callbacks to complete on a background
        // queue to avoid deadlocking with tap callbacks that dispatch to @MainActor.
        let group = tapCompletionGroup
        DispatchQueue.global().sync {
            group.wait()
        }

        defer {
            visualizer = nil
            captureSink = nil
            captureStartDate = nil
            captureFormat = nil
        }

        guard let captureSink,
              captureSink.shouldCapture,
              let captureStartDate,
              let captureFormat else {
            return nil
        }

        let capturedPCM = captureSink.snapshot()
        guard !capturedPCM.isEmpty else {
            return nil
        }

        return RecordedAudioCapture(
            pcmData: capturedPCM,
            sampleRate: captureFormat.sampleRate,
            channelCount: captureFormat.channelCount,
            startedAt: captureStartDate
        )
    }

    private func requestMicrophoneAccess() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if granted { return }
            throw AudioRecorderError.microphoneDenied
        case .denied, .restricted:
            throw AudioRecorderError.microphoneDenied
        @unknown default:
            throw AudioRecorderError.microphoneDenied
        }
    }

    private func makeTapHandler(
        visualizer: MicVisualizer,
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat,
        captureSink: AudioRecorderCaptureSink,
        sampleHandler: @escaping @Sendable (Data) -> Void,
        levelsHandler: @escaping @MainActor ([Float]) -> Void
    ) -> (AVAudioPCMBuffer, AVAudioTime) -> Void {
        let group = tapCompletionGroup
        return { buffer, _ in
            group.enter()
            defer { group.leave() }
            if let pcmChunk = Self.convert(buffer: buffer, using: converter, targetFormat: targetFormat) {
                captureSink.append(pcmChunk)
                sampleHandler(pcmChunk)
            }

            guard buffer.floatChannelData != nil,
                  buffer.frameLength > 0 else {
                return
            }

            visualizer.process(buffer)
            let snapshot = visualizer.levels
            Task { @MainActor in
                levelsHandler(snapshot)
            }
        }
    }

    private nonisolated static func convert(
        buffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter,
        targetFormat: AVAudioFormat
    ) -> Data? {
        let ratio = targetFormat.sampleRate / max(buffer.format.sampleRate, 1)
        let frameCapacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * ratio)) + 64
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else {
            return nil
        }

        let inputState = AudioConverterInputState()
        var conversionError: NSError?
        let status = converter.convert(to: convertedBuffer, error: &conversionError) { _, outStatus in
            if inputState.consumedInput {
                outStatus.pointee = .noDataNow
                return nil
            }

            inputState.consumedInput = true
            outStatus.pointee = .haveData
            return buffer
        }

        if let conversionError {
            AppLog.error("audio conversion failed: \(conversionError.localizedDescription)")
            return nil
        }

        guard status == .haveData || status == .inputRanDry || status == .endOfStream,
              convertedBuffer.frameLength > 0,
              let channelData = convertedBuffer.floatChannelData?[0] else {
            return nil
        }

        let byteCount = Int(convertedBuffer.frameLength) * MemoryLayout<Float>.size
        return Data(bytes: channelData, count: byteCount)
    }
}
