import XCTest
@testable import AppManagerCore

final class ShadowAppServiceTests: XCTestCase {
    var tempBaseDirectory: URL!
    var sampleAppURL: URL!
    var shadowService: ShadowAppService!

    override func setUp() {
        super.setUp()
        tempBaseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempBaseDirectory, withIntermediateDirectories: true)

        shadowService = ShadowAppService(baseShadowsDirectory: tempBaseDirectory)

        // Create a mock .app bundle for testing
        let appDir = tempBaseDirectory.appendingPathComponent("MockSource.app", isDirectory: true)
        let contentsDir = appDir.appendingPathComponent("Contents", isDirectory: true)
        let macosDir = contentsDir.appendingPathComponent("MacOS", isDirectory: true)
        try? FileManager.default.createDirectory(at: macosDir, withIntermediateDirectories: true)

        let executableURL = macosDir.appendingPathComponent("MockSource")
        try? "mock executable payload".data(using: .utf8)?.write(to: executableURL)

        // Mock Info.plist
        let infoPlist: [String: Any] = [
            "CFBundleIdentifier": "com.example.mockapp",
            "CFBundleName": "MockSource",
            "CFBundleShortVersionString": "1.0.0",
            "CFBundleVersion": "100"
        ]
        let plistData = try? PropertyListSerialization.data(fromPropertyList: infoPlist, format: .xml, options: 0)
        let plistURL = contentsDir.appendingPathComponent("Info.plist")
        try? plistData?.write(to: plistURL)

        sampleAppURL = appDir
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempBaseDirectory)
        super.tearDown()
    }

    func testShadowURLsResolution() {
        let appItem = AppItem(
            name: "MockSource",
            bundleIdentifier: "com.example.mockapp",
            bundleURL: sampleAppURL
        )

        let folder = shadowService.shadowFolderURL(for: "com.example.mockapp")
        XCTAssertEqual(folder.lastPathComponent, "com.example.mockapp")

        let shadowApp = shadowService.shadowAppURL(for: appItem)
        XCTAssertEqual(shadowApp.lastPathComponent, "MockSource.app")
        XCTAssertEqual(shadowApp.deletingLastPathComponent().lastPathComponent, "com.example.mockapp")
    }

    func testBundleCloning() throws {
        let destAppURL = tempBaseDirectory.appendingPathComponent("Cloned.app", isDirectory: true)
        try shadowService.cloneBundle(source: sampleAppURL, destination: destAppURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: destAppURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destAppURL.appendingPathComponent("Contents/MacOS/MockSource").path))
    }

    func testShadowMetadataEncodingAndValidation() throws {
        let appItem = AppItem(
            name: "MockSource",
            bundleIdentifier: "com.example.mockapp",
            bundleURL: sampleAppURL
        )

        XCTAssertFalse(shadowService.isShadowValid(for: appItem))

        let shadowURL = shadowService.shadowAppURL(for: appItem)
        let folder = shadowService.shadowFolderURL(for: appItem.bundleIdentifier)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try shadowService.cloneBundle(source: sampleAppURL, destination: shadowURL)

        let attrs = try FileManager.default.attributesOfItem(atPath: sampleAppURL.path)
        let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0

        let metadata = ShadowMetadata(
            bundleIdentifier: appItem.bundleIdentifier,
            sourceBundlePath: sampleAppURL.path,
            sourceModificationTimestamp: mtime,
            sourceVersion: "1.0.0"
        )
        let data = try JSONEncoder().encode(metadata)
        let metaURL = folder.appendingPathComponent("shadow_metadata.json")
        try data.write(to: metaURL)

        XCTAssertTrue(shadowService.isShadowValid(for: appItem))

        // Invalidate by changing source modification date
        let futureDate = Date(timeIntervalSince1970: mtime + 100)
        try FileManager.default.setAttributes([.modificationDate: futureDate], ofItemAtPath: sampleAppURL.path)

        XCTAssertFalse(shadowService.isShadowValid(for: appItem))
    }

    func testShadowCleanup() throws {
        let appItem = AppItem(
            name: "MockSource",
            bundleIdentifier: "com.example.mockapp",
            bundleURL: sampleAppURL
        )

        let folder = shadowService.shadowFolderURL(for: appItem.bundleIdentifier)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let shadowURL = shadowService.shadowAppURL(for: appItem)
        try shadowService.cloneBundle(source: sampleAppURL, destination: shadowURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: shadowURL.path))

        shadowService.clearShadow(for: appItem.bundleIdentifier)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }
}
