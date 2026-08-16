import XCTest
import AppKit
@testable import AppManagerCore

final class AppIconCacheTests: XCTestCase {
    var cache: AppIconCache!
    let sampleURL = URL(fileURLWithPath: "/Applications/Safari.app")

    override func setUp() {
        super.setUp()
        cache = AppIconCache(countLimit: 100)
    }

    override func tearDown() {
        cache.clear()
        super.tearDown()
    }

    func testCacheHitAndMiss() {
        XCTAssertNil(cache.cachedIcon(for: sampleURL))

        let dummyImage = NSImage(size: NSSize(width: 32, height: 32))
        cache.setCachedIcon(dummyImage, for: sampleURL)

        let cached = cache.cachedIcon(for: sampleURL)
        XCTAssertNotNil(cached)
        XCTAssertEqual(cached, dummyImage)
    }

    func testIconSynchronousFetchAndCache() {
        XCTAssertNil(cache.cachedIcon(for: sampleURL))

        let icon = cache.icon(for: sampleURL)
        XCTAssertNotNil(icon)
        XCTAssertNotNil(cache.cachedIcon(for: sampleURL))
    }

    func testAsyncLoadWithCompletion() {
        let expectation = self.expectation(description: "Async icon load completion")

        cache.loadIcon(for: sampleURL) { image in
            XCTAssertTrue(Thread.isMainThread, "Completion should be called on the main thread")
            XCTAssertNotNil(image)
            expectation.fulfill()
        }

        waitForExpectations(timeout: 3.0)
        XCTAssertNotNil(cache.cachedIcon(for: sampleURL))
    }

    func testAsyncLoadWithSwiftConcurrency() async {
        let image = await cache.loadIcon(for: sampleURL)
        XCTAssertNotNil(image)
        XCTAssertNotNil(cache.cachedIcon(for: sampleURL))
    }

    func testClearCache() {
        let dummyImage = NSImage(size: NSSize(width: 32, height: 32))
        cache.setCachedIcon(dummyImage, for: sampleURL)
        XCTAssertNotNil(cache.cachedIcon(for: sampleURL))

        cache.clear()
        XCTAssertNil(cache.cachedIcon(for: sampleURL))
    }

    func testConcurrentAccessThreadSafety() {
        let iterations = 100
        let group = DispatchGroup()

        for i in 0..<iterations {
            let dummyURL = URL(fileURLWithPath: "/Applications/App\(i).app")
            let dummyImage = NSImage(size: NSSize(width: 32, height: 32))

            group.enter()
            DispatchQueue.global().async {
                self.cache.setCachedIcon(dummyImage, for: dummyURL)
                _ = self.cache.cachedIcon(for: dummyURL)
                group.leave()
            }
        }

        let result = group.wait(timeout: .now() + 5.0)
        XCTAssertEqual(result, .success, "Concurrent read/write should complete without deadlocks or crashes")
    }
}
