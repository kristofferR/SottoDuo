import Foundation
import XCTest
@testable import SottoDuoCore

final class SottoDuoBuildTests: XCTestCase {
    func testReleaseUsesSottoDuoIdentityAndSeparatesDevelopmentState() {
        let release = SottoDuoBuild.release
        let development = SottoDuoBuild.development
        XCTAssertEqual(release.bundleIdentifier, "com.kristofferr.sottoduo")
        XCTAssertEqual(release.displayName, "SottoDuo")
        XCTAssertEqual(development.displayName, "SottoDuo Dev")
        XCTAssertNotEqual(release.bundleIdentifier, development.bundleIdentifier)
        XCTAssertNotEqual(release.dataDirectory, development.dataDirectory)
        XCTAssertNotEqual(release.credentialService, development.credentialService)
        XCTAssertNotEqual(release.windowAutosaveName, development.windowAutosaveName)
        XCTAssertEqual(release.credentialService, "com.kristofferr.sottoduo.server")
        XCTAssertEqual(development.credentialService, "com.kristofferr.sottoduo.dev.server")
        XCTAssertFalse(release.isDevelopment)
        XCTAssertTrue(development.isDevelopment)
    }

    func testExistingSottoDataIsUsedUntilNewPreferencesExist() throws {
        let support = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: support) }
        let old = support.appendingPathComponent("Sotto", isDirectory: true)
        let current = support.appendingPathComponent("SottoDuo", isDirectory: true)
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        XCTAssertEqual(SottoDuoBuild.release.dataDirectory(in: support), old)
        try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
        XCTAssertEqual(SottoDuoBuild.release.dataDirectory(in: support), old)
        try Data("{}".utf8).write(to: current.appendingPathComponent("client.json"))
        XCTAssertEqual(SottoDuoBuild.release.dataDirectory(in: support), current)
    }
}
