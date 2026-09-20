import Foundation
import SottoAPI
import XCTest
@testable import Sotto

final class StreamingUploadTests: XCTestCase {
    private func client(blockUpgrade: Bool = false) throws -> ServerClient {
        guard let endpoint = ProcessInfo.processInfo.environment["SOTTO_STREAM_TEST_URL"] else {
            throw XCTSkip("Run Server/tests/fixtures/streaming-client-server.ts for the native streaming contract test.")
        }
        let configuration = URLSessionConfiguration.ephemeral
        if blockUpgrade { configuration.httpAdditionalHeaders = ["X-Sotto-Test-Block-Upgrade": "1"] }
        return try ServerClient(endpoint: endpoint, token: "sotto-native-streaming-test-token-2026",
                                session: URLSession(configuration: configuration))
    }

    func testStreamingArchivesBothFormatsAndReturnsCloudText() async throws {
        try await take(sample: 0, expectedText: "Cloud transcript.", expectedProvider: .soniox)
    }

    func testCloudDisconnectFinishesRecordingThroughWhisper() async throws {
        try await take(sample: 0.25, expectedText: "Hello world.", expectedProvider: .whisper)
    }

    func testRejectedWebSocketUpgradeFallsBackWithoutLosingAudio() async throws {
        try await take(sample: 0, expectedText: "Cloud transcript.", expectedProvider: .soniox, blockUpgrade: true)
    }

    private func take(sample: Float, expectedText: String, expectedProvider: RecognitionState.Provider, blockUpgrade: Bool = false) async throws {
        let client = try client(blockUpgrade: blockUpgrade)
        defer { client.session.invalidateAndCancel() }
        let record = try await client.create(.init(requestID: UUID(), device: .init(id: "native-stream-test", name: "Native test"), mode: .test))
        let pipe = AudioChunkPipe()
        let previews = RecognitionUpdates()
        let upload = Task {
            try await client.uploadStreaming(pipe.stream, to: record.id, preserveOriginal: true) { recognition in
                await previews.append(recognition)
            }
        }
        let producer = Task {
            for _ in 0..<20 {
                let audio = [Float](repeating: sample, count: 800).withUnsafeBytes { Data($0) }
                pipe.append(.init(kind: .original, data: Data(repeating: 0, count: 19_200), sampleRate: 48_000, channels: 2))
                pipe.append(.init(kind: .normalized, data: audio, sampleRate: 16_000, channels: 1))
                try await Task.sleep(for: .milliseconds(50))
            }
            pipe.finish()
        }
        do {
            let counts = try await upload.value
            try await producer.value
            XCTAssertEqual(counts.inferenceFrames, 16_000)
            XCTAssertEqual(counts.originalFrames, 48_000)
            let updates = await previews.values
            if blockUpgrade {
                XCTAssertTrue(updates.isEmpty)
            } else {
                XCTAssertTrue(updates.contains { $0.provider == expectedProvider })
                if expectedProvider == .soniox { XCTAssertTrue(updates.contains { $0.partialText == "Live cloud preview." }) }
            }
            var completed = try await client.finish(record.id, value: counts)
            if !completed.status.isTerminal { completed = try await client.events(record.id) { _ in } }
            XCTAssertEqual(completed.status, .completed)
            XCTAssertEqual(completed.finalText, expectedText)
            XCTAssertEqual(completed.recognition?.provider, expectedProvider)
            XCTAssertEqual(completed.inferenceAudio?.frameCount, 16_000)
            XCTAssertEqual(completed.originalAudio?.frameCount, 48_000)
            XCTAssertNil(completed.recognition?.partialText)
            try await client.delete(record.id)
        } catch {
            producer.cancel(); pipe.cancel(); upload.cancel()
            try? await client.cancel(record.id)
            throw error
        }
    }
}

private actor RecognitionUpdates {
    var values: [RecognitionState] = []
    func append(_ value: RecognitionState) { values.append(value) }
}
