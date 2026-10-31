import XCTest
import SwiftData
@testable import AmyWardrobe

@MainActor
final class OutfitTests: XCTestCase {
    var store: ImageStore!
    var container: ModelContainer!
    var context: ModelContext { container.mainContext }
    override func setUpWithError() throws { store = try TestSupport.makeStore(); container = try TestSupport.makeContainer() }

    func testOutfitFromItems() throws {
        let top = try TestSupport.addItem("Топ", store: store, context: context)
        let skirt = try TestSupport.addItem("Юбка", category: "bottoms", color: .purple, store: store, context: context)
        let o = try OutfitService.create(from: [top, skirt], name: "Офис", context: context, store: store)
        XCTAssertEqual(o.entries.map(\.name), ["Топ", "Юбка"])
        XCTAssertNotNil(o.previewFile); XCTAssertTrue(store.exists(try XCTUnwrap(o.previewFile)))
        o.isFavorite = true; try context.save()
        XCTAssertTrue(try context.fetch(FetchDescriptor<Outfit>()).first!.isFavorite)
    }

    func testOutfitFromCollageDoesNotChangeCollage() throws {
        let top = try TestSupport.addItem("Топ", store: store, context: context)
        let p = try CollageService.create(name: "К", aspect: .square, backgroundHex: "#FFFFFF", context: context)
        let model = CollageEditorModel(project: p, context: context, store: store)
        model.addItems([top]); model.addText(); model.saveNow()
        let before = p.documentData
        let o = try OutfitService.create(from: p, items: [top], context: context, store: store)
        XCTAssertEqual(o.origin, .collage); XCTAssertEqual(o.sourceCollageID, p.id)
        XCTAssertEqual(o.entries.count, 1, "текстовые объекты не становятся вещами")
        XCTAssertEqual(p.documentData, before)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CollageProject>()).count, 1)
    }

    func testEmptyCollageCannotBecomeOutfit() throws {
        let p = try CollageService.create(name: "Пусто", aspect: .square, backgroundHex: "#FFFFFF", context: context)
        XCTAssertThrowsError(try OutfitService.create(from: p, items: [], context: context, store: store))
    }

    func testReplaceEntryAndDuplicate() throws {
        let a = try TestSupport.addItem("A", store: store, context: context)
        let b = try TestSupport.addItem("B", color: .orange, store: store, context: context)
        let o = try OutfitService.create(from: [a], name: "О", context: context, store: store)
        var list = o.entries
        list[0] = OutfitEntry(id: list[0].id, itemID: b.id, name: b.name, categoryID: b.categoryID, subcategory: "", imageFile: b.imageFile)
        o.entries = list
        XCTAssertEqual(o.entries.first?.name, "B")
        let copy = try OutfitService.duplicate(o, context: context)
        XCTAssertNotEqual(copy.id, o.id); XCTAssertEqual(copy.entries, o.entries)
    }
}

@MainActor
final class BackupTests: XCTestCase {
    var store: ImageStore!
    var container: ModelContainer!
    var context: ModelContext { container.mainContext }
    override func setUpWithError() throws { store = try TestSupport.makeStore(); container = try TestSupport.makeContainer() }

    private func populate() throws -> (items: [WardrobeItem], collage: CollageProject, outfit: Outfit) {
        let a = try TestSupport.addItem("Платье", category: "dresses", color: .red, store: store, context: context) { $0.tags = ["вечер"]; $0.isFavorite = true }
        let b = try TestSupport.addItem("Туфли", category: "shoes", color: .black, store: store, context: context)
        let c = try CollageService.create(name: "Вечер", aspect: .portrait45, backgroundHex: "#F4E5F0", context: context)
        let m = CollageEditorModel(project: c, context: context, store: store)
        m.addItems([a, b]); m.addText(); m.saveNow()
        let o = try OutfitService.create(from: [a, b], name: "Образ", context: context, store: store)
        return ([a, b], c, o)
    }

    private func export() throws -> URL {
        let payload = try BackupService.makePayload(context: context, settings: SettingsData())
        return try BackupService.writeArchive(payload: payload, store: store, to: TestSupport.tempDir())
    }

    func testExportInspectRestoreIntoCleanState() throws {
        let src = try populate()
        let archive = try export()
        let inspection = try BackupService.inspect(archive: archive)
        XCTAssertEqual(inspection.manifest.formatVersion, 1)
        XCTAssertEqual(inspection.manifest.counts.items, 2); XCTAssertEqual(inspection.manifest.counts.collages, 1); XCTAssertEqual(inspection.manifest.counts.outfits, 1)
        XCTAssertTrue(inspection.manifest.warnings.isEmpty)

        // чистое состояние: новая БД и новое хранилище
        let store2 = try TestSupport.makeStore()
        let container2 = try TestSupport.makeContainer()
        let report = try BackupService.restore(inspection, into: container2.mainContext, store: store2, settings: nil)
        XCTAssertEqual(report.added, 4)
        let items = try container2.mainContext.fetch(FetchDescriptor<WardrobeItem>())
        XCTAssertEqual(Set(items.map(\.name)), ["Платье", "Туфли"])
        XCTAssertTrue(items.first { $0.name == "Платье" }!.isFavorite)
        for i in items { XCTAssertTrue(store2.exists(i.imageFile)) }
        let restoredCollage = try XCTUnwrap(try container2.mainContext.fetch(FetchDescriptor<CollageProject>()).first)
        XCTAssertEqual(restoredCollage.document, src.collage.document)
        let o = try XCTUnwrap(try container2.mainContext.fetch(FetchDescriptor<Outfit>()).first)
        XCTAssertEqual(o.entries, src.outfit.entries)
        let img = CollageRenderer.render(restoredCollage.document, store: store2)
        XCTAssertEqual(img.size.width, 1080)
    }

    func testRepeatedImportDoesNotDuplicate() throws {
        _ = try populate()
        let inspection = try BackupService.inspect(archive: try export())
        let r1 = try BackupService.restore(inspection, into: context, store: store, settings: nil)
        XCTAssertEqual(r1.added, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WardrobeItem>()).count, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Outfit>()).count, 1)
        let c2 = try TestSupport.makeContainer(); let s2 = try TestSupport.makeStore()
        _ = try BackupService.restore(inspection, into: c2.mainContext, store: s2, settings: nil)
        let again = try BackupService.restore(inspection, into: c2.mainContext, store: s2, settings: nil)
        XCTAssertEqual(again.added, 0); XCTAssertGreaterThan(again.skipped, 0)
        XCTAssertEqual(try c2.mainContext.fetch(FetchDescriptor<WardrobeItem>()).count, 2)
    }

    func testCorruptedArchiveIsRejectedAndDataUntouched() throws {
        _ = try populate()
        let archive = try export()
        var bytes = try Data(contentsOf: archive)
        bytes[bytes.count / 3] ^= 0xFF                       // порча содержимого
        let bad = TestSupport.tempDir().appendingPathComponent("bad.zip")
        try bytes.write(to: bad)
        XCTAssertThrowsError(try BackupService.inspect(archive: bad)) { XCTAssertTrue($0 is AppError) }
        let junk = TestSupport.tempDir().appendingPathComponent("junk.zip")
        try Data("это не архив".utf8).write(to: junk)
        XCTAssertThrowsError(try BackupService.inspect(archive: junk))
        let truncated = TestSupport.tempDir().appendingPathComponent("trunc.zip")
        try Data(bytes.prefix(bytes.count / 2)).write(to: truncated)
        XCTAssertThrowsError(try BackupService.inspect(archive: truncated))
        XCTAssertEqual(try context.fetch(FetchDescriptor<WardrobeItem>()).count, 2, "текущие данные не затронуты")
    }

    func testFutureFormatVersionRejected() throws {
        let url = TestSupport.tempDir().appendingPathComponent("future.zip")
        let w = try ZipWriter(url: url)
        let payload = try BackupService.encoder.encode(BackupPayload())
        try w.add(name: "data.json", data: payload)
        let m = BackupManifest(formatVersion: 99, appVersion: "9", createdAt: Date(), counts: .init(),
                               files: [.init(path: "data.json", size: payload.count, sha256: ImageStore.sha256Hex(payload))])
        try w.add(name: "manifest.json", data: try BackupService.encoder.encode(m))
        try w.finish()
        XCTAssertThrowsError(try BackupService.inspect(archive: url)) { XCTAssertEqual($0 as? AppError, .backupUnsupportedVersion(99)) }
    }

    func testMissingRequiredFieldsRejected() throws {
        let url = TestSupport.tempDir().appendingPathComponent("nofields.zip")
        let w = try ZipWriter(url: url)
        let payload = Data(#"{"items": "oops"}"#.utf8)
        try w.add(name: "data.json", data: payload)
        let m = BackupManifest(formatVersion: 1, appVersion: "1", createdAt: Date(), counts: .init(),
                               files: [.init(path: "data.json", size: payload.count, sha256: ImageStore.sha256Hex(payload))])
        try w.add(name: "manifest.json", data: try BackupService.encoder.encode(m))
        try w.finish()
        XCTAssertThrowsError(try BackupService.inspect(archive: url))
    }

    func testPathTraversalInManifestRejected() throws {
        let url = TestSupport.tempDir().appendingPathComponent("evil.zip")
        let w = try ZipWriter(url: url)
        let d = Data("x".utf8)
        try w.add(name: "images/../../evil.png", data: d)
        let m = BackupManifest(formatVersion: 1, appVersion: "1", createdAt: Date(), counts: .init(),
                               files: [.init(path: "images/../../evil.png", size: 1, sha256: ImageStore.sha256Hex(d))])
        try w.add(name: "manifest.json", data: try BackupService.encoder.encode(m))
        try w.finish()
        XCTAssertThrowsError(try BackupService.inspect(archive: url))
    }

    func testMissingImageProducesWarningNotCrash() throws {
        let items = try populate().items
        store.remove(items[0].imageFile)
        let payload = try BackupService.makePayload(context: context, settings: SettingsData())
        let archive = try BackupService.writeArchive(payload: payload, store: store, to: TestSupport.tempDir())
        let inspection = try BackupService.inspect(archive: archive)
        XCTAssertFalse(inspection.manifest.warnings.isEmpty)
    }
}
