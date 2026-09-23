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

    func testDataDirectoryUsesCurrentAppName() {
        let support = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertEqual(SottoDuoBuild.release.dataDirectory(in: support), support.appendingPathComponent("SottoDuo", isDirectory: true))
        XCTAssertEqual(SottoDuoBuild.development.dataDirectory(in: support), support.appendingPathComponent("SottoDuo Dev", isDirectory: true))
    }
}
