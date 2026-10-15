import AVFoundation
import Speech
import Darwin

enum SpeechEvent {
    case level(Double)
    case ready, partial(String), final(String), failure(String)
}

@MainActor
protocol SpeechListening: AnyObject {
    func authorize() async -> Bool
    func start(configuration: PracticeConfiguration, receive: @escaping (SpeechEvent) -> Void) async throws
    func stop()
}

@MainActor
final class SpeechRecognitionService: SpeechListening {
    private var engine = AVAudioEngine()
    private let recognizer: SFSpeechRecognizer?
    private let settings: TrainingSettings?
    private let cue = CuePlayer()
    private var inputGate: AudioInputGate?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var watchdog: Task<Void, Never>?
    private var generation = UUID()
    private var tapInstalled = false
    private var latest = ""
    private var lastChange = Date()
    private var endingAt: Date?

    init(settings: TrainingSettings? = nil) {
        self.settings = settings
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: settings?.options.englishLocale ?? "en-US"))
    }

    func authorize() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard speech, !Task.isCancelled else { return false }
        return await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
    }

    func start(configuration: PracticeConfiguration, receive: @escaping (SpeechEvent) -> Void) async throws {
        stop()
        let token = generation
        guard let recognizer, recognizer.isAvailable else {
            throw RecognitionError.unavailable
        }
        guard recognizer.supportsOnDeviceRecognition else { throw RecognitionError.offlineUnavailable }
        let session = AVAudioSession.sharedInstance()
        do {
            let options = settings?.options
            let useCue = options?.cuePack != nil && options?.cuePack != .spoken && options?.cuePack != .selected
            if useCue {
                try session.setCategory(.playAndRecord, mode: .measurement,
                    options: [.allowBluetooth, .defaultToSpeaker])
            } else {
                try session.setCategory(.record, mode: .measurement, options: [.allowBluetooth])
            }
            // Rebuild the input graph after switching from sentence playback to recording.
            try session.setActive(true)
            engine = AVAudioEngine()
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = true
            request.taskHint = configuration.isSentence ? .dictation : .confirmation
            // Do not bias recognition using the hidden answer.
            self.request = request
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw RecognitionError.unavailable }
            let gate = AudioInputGate()
            inputGate = gate
            // Construct the render callback outside MainActor; audio callbacks run on a render thread.
            input.installTap(onBus: 0, bufferSize: 1024, format: format,
                block: Self.captureBlock(gate: gate, request: request))
            tapInstalled = true
            latest = ""
            lastChange = Date()
            endingAt = nil
            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let final = result?.isFinal == true
                let failed = error != nil
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token else { return }
                    if let text {
                        if text != self.latest { self.lastChange = Date() }
                        self.latest = text
                        if final {
                            self.stop()
                            receive(.final(text))
                            return
                        }
                        receive(.partial(text))
                    }
                    if failed {
                        // endAudio may terminate with an error instead of a final result.
                        // Only accept this fallback after our own silence/timeout boundary.
                        let endedNormally = self.endingAt != nil
                        let text = self.latest
                        self.stop()
                        if endedNormally { receive(.final(text)) }
                        else { receive(.failure("本地语音识别中断，请检查系统英语离线资源和音频设备后重新开始。")) }
                    }
                }
            }
            engine.prepare()
            try engine.start()
            if useCue, let options {
                // The engine is already running, but cue audio is excluded from Speech input.
                try await cue.play(.ready, pack: options.cuePack, volume: options.cueVolume, activateSession: false)
            }
            guard generation == token, !Task.isCancelled else { throw CancellationError() }
            gate.open(after: useCue ? mach_absolute_time() : 0)
            lastChange = Date()
            let began = Date()
            receive(.ready)
            watchdog = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    guard !Task.isCancelled, let self, self.generation == token else { return }
                    let now = Date()
                    receive(.level(self.endingAt == nil ? gate.level : 0))
                    if let ending = self.endingAt {
                        if now.timeIntervalSince(ending) >= configuration.finalResultSeconds {
                            let text = self.latest
                            self.stop()
                            receive(.final(text))
                            return
                        }
                    } else if now.timeIntervalSince(began) >= configuration.listeningSeconds ||
                                (!self.latest.isEmpty && now.timeIntervalSince(self.lastChange) >= configuration.silenceSeconds) {
                        self.inputGate?.close()
                        self.engine.stop()
                        if self.tapInstalled { self.engine.inputNode.removeTap(onBus: 0); self.tapInstalled = false }
                        request.endAudio()
                        self.endingAt = now
                    }
                }
            }
        } catch {
            if generation == token { stop() }
            throw error
        }
    }

    nonisolated static func captureBlock(gate: AudioInputGate,
        request: SFSpeechAudioBufferRecognitionRequest) -> AVAudioNodeTapBlock {
        { buffer, when in gate.append(buffer, when: when, to: request) }
    }

    func stop() {
        generation = UUID()
        inputGate?.close(); inputGate = nil
        cue.stop()
        watchdog?.cancel()
        watchdog = nil
        engine.stop()
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        request?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        request = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    enum RecognitionError: LocalizedError {
        case unavailable, offlineUnavailable
        var errorDescription: String? {
            switch self {
            case .unavailable: return "英语语音识别或麦克风暂不可用，请检查权限和音频设备。"
            case .offlineUnavailable: return "此设备尚不能进行本地英语识别，请先在 iPhone 系统中准备英语离线语音资源。SpeakFlow 不会改用联网识别。"
            }
        }
    }
}

// Called from the audio render thread and MainActor; gate by capture timestamp, not delivery time.
final class AudioInputGate {
    private let lock = NSLock()
    private var threshold: UInt64?
    private var measuredLevel = 0.0
    var level: Double { lock.lock(); defer { lock.unlock() }; return measuredLevel }
    func open(after time: UInt64) { lock.lock(); threshold = time; lock.unlock() }
    func close() { lock.lock(); threshold = nil; measuredLevel = 0; lock.unlock() }
    func accepts(hostTime: UInt64?) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let threshold else { return false }
        return threshold == 0 || (hostTime.map { $0 >= threshold } ?? false)
    }
    // Hold the same lock through append. close() waits for an in-flight append,
    // so callers can safely endAudio after closing without a late render callback.
    func append(_ buffer: AVAudioPCMBuffer, when: AVAudioTime,
                to request: SFSpeechAudioBufferRecognitionRequest) {
        lock.lock(); defer { lock.unlock() }
        guard let offset = Self.offset(boundary: threshold,
            hostTime: when.isHostTimeValid ? when.hostTime : nil,
            sampleRate: buffer.format.sampleRate, frameCount: Int(buffer.frameLength)) else { return }
        if let samples = buffer.floatChannelData?[0] {
            var sum = 0.0
            for frame in offset..<Int(buffer.frameLength) {
                let value = Double(samples[frame])
                sum += value * value
            }
            let rms = sqrt(sum / Double(Int(buffer.frameLength) - offset))
            let db = 20 * log10(max(rms, 0.000001))
            measuredLevel = db.isFinite && db > -48 ? min(1, max(0, (db + 48) / 36)) : 0
        } else { measuredLevel = 0 }
        if offset == 0 { request.append(buffer); return }
        let remaining = buffer.frameLength - AVAudioFrameCount(offset)
        guard let trimmed = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: remaining) else { return }
        trimmed.frameLength = remaining
        let sources = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let destinations = UnsafeMutableAudioBufferListPointer(trimmed.mutableAudioBufferList)
        let stride = Int(buffer.format.streamDescription.pointee.mBytesPerFrame)
        guard stride > 0, sources.count == destinations.count else { return }
        for channel in sources.indices {
            guard let source = sources[channel].mData, let destination = destinations[channel].mData,
                offset * stride + Int(remaining) * stride <= Int(sources[channel].mDataByteSize),
                Int(remaining) * stride <= Int(destinations[channel].mDataByteSize) else { return }
            memcpy(destination, source.advanced(by: offset * stride), Int(remaining) * stride)
        }
        request.append(trimmed)
    }
    func firstFrame(hostTime: UInt64?, sampleRate: Double, frameCount: Int) -> Int? {
        lock.lock(); let boundary = threshold; lock.unlock()
        return Self.offset(boundary: boundary, hostTime: hostTime, sampleRate: sampleRate, frameCount: frameCount)
    }
    private static func offset(boundary: UInt64?, hostTime: UInt64?, sampleRate: Double, frameCount: Int) -> Int? {
        guard let boundary, frameCount > 0, sampleRate.isFinite, sampleRate > 0 else { return nil }
        if boundary == 0 { return 0 }
        guard let hostTime else { return nil }
        if hostTime >= boundary { return 0 }
        let frames = AVAudioTime.seconds(forHostTime: boundary - hostTime) * sampleRate
        guard frames.isFinite, frames < Double(frameCount) else { return nil }
        return Int(ceil(frames)) < frameCount ? Int(ceil(frames)) : nil
    }
}
