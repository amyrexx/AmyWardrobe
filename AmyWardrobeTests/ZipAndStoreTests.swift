import XCTest
@testable import AmyWardrobe

final class ZipAndStoreTests: XCTestCase {
    func testCRC32KnownValue() {
        XCTAssertEqual(CRC32.checksum(Data("123456789".utf8)), 0xCBF43926)
    }

    func testZipRoundTrip() throws {
        let url = TestSupport.tempDir().appendingPathComponent("a.zip")
        let w = try ZipWriter(url: url)
        let payload = Data((0..<5000).map { UInt8($0 % 251) })
        try w.add(name: "images/x.bin", data: payload)
        try w.add(name: "текст.json", data: Data("{}".utf8))
        try w.finish()
        let r = try ZipReader(url: url)
        XCTAssertEqual(Set(r.orderedNames), ["images/x.bin", "текст.json"])
        XCTAssertEqual(try r.read("images/x.bin"), payload)
    }

    func testZipDetectsCorruption() throws {
        let url = TestSupport.tempDir().appendingPathComponent("b.zip")
        let w = try ZipWriter(url: url)
        try w.add(name: "f", data: Data(repeating: 7, count: 1000))
        try w.finish()
        var bytes = try Data(contentsOf: url)
        bytes[100] ^= 0xFF
        let r = try ZipReader(data: bytes)
        XCTAssertThrowsError(try r.read("f"))
        XCTAssertThrowsError(try ZipReader(data: Data("not a zip at all, definitely not".utf8)))
    }

    func testImageStoreDedupesAndKeepsAlpha() throws {
        let store = try TestSupport.makeStore()
        let data = TestSupport.pngData()
        let a = try store.save(data: data), b = try store.save(data: data)
        XCTAssertEqual(a, b)
        XCTAssertEqual(store.allFileNames().count, 1)
        XCTAssertTrue(ImageStore.isValidFileName(a))
        XCTAssertEqual(try store.loadData(a), data, "оригинал сохраняется без изменений")
        let thumb = try XCTUnwrap(store.thumbnail(fileName: a))
        XCTAssertTrue(ImageStore.hasAlpha(thumb), "прозрачность миниатюры сохраняется")
        XCTAssertEqual(store.pixelSize(fileName: a), CGSize(width: 64, height: 96))
    }

    func testImageStoreRejectsGarbageAndMissing() throws {
        let store = try TestSupport.makeStore()
        XCTAssertThrowsError(try store.save(data: Data("garbage".utf8))) { XCTAssertEqual($0 as? AppError, .imageDecodeFailed) }
        XCTAssertThrowsError(try store.loadData("nope.png"))
        XCTAssertNil(store.thumbnail(fileName: "nope.png"))
        XCTAssertFalse(ImageStore.isValidFileName("../../etc/passwd"))
    }

    func testGarbageCollectionRespectsReferencesAndGrace() throws {
        let store = try TestSupport.makeStore()
        let keep = try store.save(data: TestSupport.pngData(color: .red))
        let drop = try store.save(data: TestSupport.pngData(color: .blue))
        XCTAssertEqual(store.collectGarbage(referenced: [keep], grace: 600), 0, "свежие файлы не удаляются")
        XCTAssertEqual(store.collectGarbage(referenced: [keep], grace: 0), 1)
        XCTAssertTrue(store.exists(keep)); XCTAssertFalse(store.exists(drop))
    }
}
