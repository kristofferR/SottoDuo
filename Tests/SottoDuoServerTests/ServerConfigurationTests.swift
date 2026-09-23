import Foundation
@testable import SottoDuoServerKit
import XCTest

final class ServerConfigurationTests: XCTestCase {
    private func inference() -> InferenceConfiguration {
        let url = URL(fileURLWithPath: "/tmp/unused-sottoduo-test-model")
        return InferenceConfiguration(speechHelper: url, speechModel: url, vadModel: url, proofHelper: url, proofModel: url)
    }

    func testPublicBindingRequiresStrongToken() throws {
        let directory = URL(fileURLWithPath: "/tmp/unused-sottoduo-test-data")
        XCTAssertThrowsError(try ServerConfiguration(host: "0.0.0.0", dataDirectory: directory, inference: inference()))
        XCTAssertThrowsError(try ServerConfiguration(host: "100.90.80.70", dataDirectory: directory, token: "short", inference: inference()))
        XCTAssertNoThrow(try ServerConfiguration(host: "0.0.0.0", dataDirectory: directory,
                                                token: String(repeating: "x", count: 32), inference: inference()))
        XCTAssertNoThrow(try ServerConfiguration(dataDirectory: directory, inference: inference()))
    }

    func testParserAcceptsLegacyEnvironmentWithNewNamesTakingPrecedence() throws {
        let tokenFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try "legacy-token".write(to: tokenFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tokenFile) }
        let legacy = [
            "SOTTO_DEV": "1", "SOTTO_SERVER_HOST": "localhost", "SOTTO_SERVER_PORT": "8493",
            "SOTTO_SERVER_DATA_DIR": "/tmp/legacy-data", "SOTTO_SERVER_TOKEN_FILE": tokenFile.path,
            "SOTTO_ENGINE_PATH": "/tmp/legacy-engine", "SOTTO_SPEECH_MODEL": "/tmp/legacy-speech",
            "SOTTO_VAD_PATH": "/tmp/legacy-vad", "SOTTO_TEXT_ENGINE_PATH": "/tmp/legacy-text-engine",
            "SOTTO_TEXT_MODEL": "/tmp/legacy-text-model"
        ]
        let configuration = try ServerConfiguration.parse(arguments: [], environment: legacy)
        XCTAssertTrue(configuration.development)
        XCTAssertEqual(configuration.host, "localhost")
        XCTAssertEqual(configuration.port, 8493)
        XCTAssertEqual(configuration.dataDirectory.path, "/tmp/legacy-data")
        XCTAssertEqual(configuration.token, "legacy-token")
        XCTAssertEqual(configuration.inference.speechHelper.path, "/tmp/legacy-engine")
        XCTAssertEqual(configuration.inference.speechModel.path, "/tmp/legacy-speech")
        XCTAssertEqual(configuration.inference.vadModel.path, "/tmp/legacy-vad")
        XCTAssertEqual(configuration.inference.proofHelper.path, "/tmp/legacy-text-engine")
        XCTAssertEqual(configuration.inference.proofModel.path, "/tmp/legacy-text-model")

        let updated = try ServerConfiguration.parse(arguments: [], environment: legacy.merging([
            "SOTTODUO_DEV": "0", "SOTTODUO_SERVER_PORT": "8494",
            "SOTTODUO_SERVER_DATA_DIR": "/tmp/new-data"
        ]) { _, new in new })
        XCTAssertFalse(updated.development)
        XCTAssertEqual(updated.port, 8494)
        XCTAssertEqual(updated.dataDirectory.path, "/tmp/new-data")
    }

    func testWaveHeaderPreservesSampleBytes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let raw = directory.appendingPathComponent("test.pcm")
        let wave = directory.appendingPathComponent("test.wav")
        let samples = Data([0, 0, 255, 127, 0, 128])
        try samples.write(to: raw)
        try WaveFile.write(rawURL: raw, outputURL: wave, sampleRate: 16000, channels: 1, float: false)
        let result = try Data(contentsOf: wave)
        XCTAssertEqual(result.count, 44 + samples.count)
        XCTAssertEqual(String(data: result.prefix(4), encoding: .utf8), "RIFF")
        XCTAssertEqual(result.suffix(samples.count), samples)
        XCTAssertEqual(Array(result[20..<24]), [1, 0, 1, 0])
        XCTAssertEqual(Array(result[24..<28]), [128, 62, 0, 0])
    }
}
