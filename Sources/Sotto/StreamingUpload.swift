import Foundation
import SottoAPI

extension ServerClient {
    /// Inference frames and archival original audio have independent send queues.
    func uploadStreaming(_ stream: AsyncThrowingStream<CapturedAudioChunk, Error>, to id: UUID,
                         preserveOriginal: Bool,
                         onRecognition: @escaping @Sendable (RecognitionState) async -> Void) async throws -> FinishGenerationRequest {
        var request = try request(path: "v1/generations/\(id)/stream")
        guard let url = request.url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw ServerClientError.invalidEndpoint
        }
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        request.url = components.url
        let socket = session.webSocketTask(with: request)
        socket.maximumMessageSize = 262_144
        let transport = InferenceUpload(socket: socket)
        let originals = AudioChunkPipe()
        socket.resume()
        let reader = Task { try await transport.readUpdates(onRecognition) }
        let originalUpload = Task {
            do {
                var buffer = UploadBuffer(kind: .original)
                for try await chunk in originals.stream {
                    try Task.checkCancellation()
                    try buffer.append(chunk)
                    if buffer.data.count >= 768_000 { try await flush(&buffer, to: id) }
                }
                try await flush(&buffer, to: id)
                return buffer.frames
            } catch {
                await transport.fail(error)
                throw error
            }
        }
        defer {
            originals.cancel()
            originalUpload.cancel()
            reader.cancel()
            socket.cancel(with: .normalClosure, reason: nil)
        }
        return try await withTaskCancellationHandler {
            var audio = Data()
            for try await chunk in stream {
                try Task.checkCancellation()
                try await transport.check()
                switch chunk.kind {
                case .original:
                    guard preserveOriginal else { throw ServerClientError.invalidResponse }
                    originals.append(chunk)
                case .normalized:
                    guard chunk.sampleRate == 16_000, chunk.channels == 1, chunk.data.count % 4 == 0 else {
                        throw ServerClientError.invalidResponse
                    }
                    audio.append(chunk.data)
                    // 50 ms at 16 kHz float32; never wait for a round trip per frame.
                    while audio.count >= 3_200 {
                        try await transport.send(Data(audio.prefix(3_200)))
                        audio.removeFirst(3_200)
                    }
                }
            }
            if !audio.isEmpty { try await transport.send(audio) }
            originals.finish()
            // Start provider finalization while the original-audio archive drains.
            let frames = try await transport.finish()
            try await reader.value
            let originalFrames = try await originalUpload.value
            return FinishGenerationRequest(inferenceFrames: frames, originalFrames: preserveOriginal ? originalFrames : nil)
        } onCancel: {
            socket.cancel(with: .goingAway, reason: nil)
            originals.cancel()
            originalUpload.cancel()
            reader.cancel()
        }
    }
}

private struct AudioStreamMessage: Decodable {
    var type: String
    var nextSequence: Int?
    var frameCount: Int64?
    var recognition: RecognitionState?
    var message: String?
}

/// Cumulative durable acknowledgements bound outstanding audio to one second.
private actor InferenceUpload {
    let socket: URLSessionWebSocketTask
    private var sequence = 0
    private var frames: Int64 = 0
    private var acknowledgedFrames: Int64 = 0
    private var acknowledgedSequence = 0
    private var pending: [Int: Int64] = [:]
    private var ended = false
    private var failure: Error?

    init(socket: URLSessionWebSocketTask) { self.socket = socket }
    func check() throws {
        try Task.checkCancellation()
        if let failure { throw failure }
    }
    func fail(_ error: Error) {
        if failure == nil { failure = error }
        socket.cancel(with: .goingAway, reason: nil)
    }
    func readUpdates(_ update: @escaping @Sendable (RecognitionState) async -> Void) async throws {
        do {
            while !ended {
                let message = try await socket.receive()
                guard case .string(let json) = message, let data = json.data(using: .utf8) else {
                    throw ServerClientError.invalidResponse
                }
                let value = try JSONDecoder().decode(AudioStreamMessage.self, from: data)
                switch value.type {
                case "ack":
                    guard let next = value.nextSequence, let count = value.frameCount,
                          next == acknowledgedSequence + 1, pending.removeValue(forKey: next) == count else {
                        throw ServerClientError.invalidResponse
                    }
                    acknowledgedSequence = next
                    acknowledgedFrames = count
                case "ended":
                    guard value.frameCount == frames, pending.isEmpty else { throw ServerClientError.invalidResponse }
                    ended = true
                case "recognition":
                    guard let recognition = value.recognition else { throw ServerClientError.invalidResponse }
                    await update(recognition)
                case "error": throw ServerClientError.rejected(422, value.message ?? "Audio streaming failed.")
                default: throw ServerClientError.invalidResponse
                }
            }
        } catch {
            fail(error)
            throw error
        }
    }
    func send(_ audio: Data) async throws {
        let deadline = ContinuousClock.now + .seconds(12)
        while frames - acknowledgedFrames >= 16_000 {
            try check()
            guard ContinuousClock.now < deadline else { throw ServerClientError.uploadBacklog }
            try await Task.sleep(for: .milliseconds(10))
        }
        try check()
        var header = UInt32(sequence).littleEndian
        var packet = withUnsafeBytes(of: &header) { Data($0) }
        packet.append(audio)
        sequence += 1
        frames += Int64(audio.count / 4)
        pending[sequence] = frames
        try await socket.send(.data(packet))
    }
    func finish() async throws -> Int64 {
        try check()
        try await socket.send(.string("{\"type\":\"end\",\"frameCount\":\(frames)}"))
        let deadline = ContinuousClock.now + .seconds(12)
        while !ended {
            try check()
            guard ContinuousClock.now < deadline else { throw ServerClientError.disconnected }
            try await Task.sleep(for: .milliseconds(10))
        }
        return frames
    }
}
