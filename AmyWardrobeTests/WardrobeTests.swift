import XCTest
import SwiftData
@testable import AmyWardrobe

@MainActor
final class WardrobeTests: XCTestCase {
    var store: ImageStore!
    var container: ModelContainer!
    var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        store = try TestSupport.makeStore()
        container = try TestSupport.makeContainer()
    }

    func testCreateEditDeleteItem() throws {
        let item = try TestSupport.addItem("Белая блузка", store: store, context: context) {
            $0.subcategory = "Блузка"; $0.tags = ["офис"]; $0.seasons = [.spring, .summer]; $0.material = "Хлопок"
        }
        XCTAssertEqual(try context.fetch(FetchDescriptor<WardrobeItem>()).count, 1)
        item.name = "Блузка"; item.updatedAt = Date(); try context.save()
        let fetched = try XCTUnwrap(try context.fetch(FetchDescriptor<WardrobeItem>()).first)
        XCTAssertEqual(fetched.name, "Блузка")
        XCTAssertEqual(fetched.seasons, [.spring, .summer])
        XCTAssertEqual(fetched.tags, ["офис"])
        try WardrobeService.delete([item], context: context, store: store)
        XCTAssertTrue(try context.fetch(FetchDescriptor<WardrobeItem>()).isEmpty)
    }

    func testDeleteItemKeepsImageUsedByCollageAndOutfit() throws {
        let item = try TestSupport.addItem("Платье", category: "dresses", store: store, context: context)
        let file = item.imageFile
        let outfit = try OutfitService.create(from: [item], name: "Образ", context: context, store: store)
        try WardrobeService.delete([item], context: context, store: store)
        GarbageCollector.run(context: context, store: store, grace: 0)
        XCTAssertTrue(store.exists(file), "образ ссылается на изображение — файл должен остаться")
        XCTAssertEqual(outfit.entries.first?.imageFile, file)
        context.delete(outfit); try context.save()
        GarbageCollector.run(context: context, store: store, grace: 0)
        XCTAssertFalse(store.exists(file))
    }

    func testFiltersAndSearch() throws {
        try TestSupport.addItem("Красная юбка", category: "bottoms", color: .red, store: store, context: context) {
            $0.primaryColorHex = "#D64550"; $0.seasons = [.summer]; $0.isFavorite = true; $0.tags = ["вечер"]
        }
        try TestSupport.addItem("Синие джинсы", category: "bottoms", color: .blue, store: store, context: context) {
            $0.primaryColorHex = "#3F5FB5"; $0.seasons = [.autumn, .winter]
        }
        try TestSupport.addItem("Чёрные ботинки", category: "shoes", color: .black, store: store, context: context) {
            $0.primaryColorHex = "#1E1B22"; $0.seasons = [.autumn]
        }
        let all = try context.fetch(FetchDescriptor<WardrobeItem>())
        func names(_ c: WardrobeCriteria, _ s: WardrobeSort = .name) -> [String] { WardrobeFilter.apply(all, criteria: c, sort: s).map(\.name) }
        XCTAssertEqual(names(WardrobeCriteria()).count, 3)
        XCTAssertEqual(names(WardrobeCriteria(search: "юбк")), ["Красная юбка"])
        XCTAssertEqual(names(WardrobeCriteria(search: "ЮБК")), ["Красная юбка"], "поиск без учёта регистра")
        XCTAssertEqual(Set(names(WardrobeCriteria(categoryID: "bottoms"))), ["Красная юбка", "Синие джинсы"])
        XCTAssertEqual(Set(names(WardrobeCriteria(seasons: [.autumn]))), ["Синие джинсы", "Чёрные ботинки"])
        XCTAssertEqual(names(WardrobeCriteria(favoritesOnly: true)), ["Красная юбка"])
        XCTAssertEqual(names(WardrobeCriteria(colorFamilyID: "red")), ["Красная юбка"])
        XCTAssertEqual(names(WardrobeCriteria(tag: "вечер")), ["Красная юбка"])
        XCTAssertTrue(names(WardrobeCriteria(search: "несуществующее")).isEmpty)
    }

    func testEmptyWardrobe() throws {
        XCTAssertTrue(WardrobeFilter.apply([], criteria: WardrobeCriteria(search: "x"), sort: .newest).isEmpty)
        XCTAssertTrue(StylistEngine.suggest(items: [], occasion: .everyday, season: .summer).isEmpty)
        XCTAssertThrowsError(try OutfitService.create(from: [], name: "", context: context, store: store))
    }

    func testFavoritePersistsAcrossReopen() throws {
        let url = TestSupport.tempDir().appendingPathComponent("db.store")
        let schema = Schema(versionedSchema: AmySchemaV1.self)
        do {
            let c1 = try ModelContainer(for: schema, migrationPlan: AmyMigrationPlan.self, configurations: ModelConfiguration(schema: schema, url: url))
            let ctx = c1.mainContext
            let item = try TestSupport.addItem("Сумка", category: "bags", store: store, context: ctx)
            item.isFavorite = true
            let collage = try CollageService.create(name: "Мой коллаж", aspect: .square, backgroundHex: "#FFFFFF", context: ctx)
            collage.isFavorite = true
            try ctx.save()
        }
        let c2 = try ModelContainer(for: schema, migrationPlan: AmyMigrationPlan.self, configurations: ModelConfiguration(schema: schema, url: url))
        let item = try XCTUnwrap(try c2.mainContext.fetch(FetchDescriptor<WardrobeItem>()).first)
        XCTAssertTrue(item.isFavorite)
        XCTAssertTrue(try XCTUnwrap(try c2.mainContext.fetch(FetchDescriptor<CollageProject>()).first).isFavorite)
    }

    func testMigrationPlanOpensEmptyContainer() throws {
        let c = try PersistenceController.makeContainer(inMemory: true)
        XCTAssertTrue(try c.mainContext.fetch(FetchDescriptor<WardrobeItem>()).isEmpty)
        XCTAssertEqual(AmyMigrationPlan.schemas.count, 1)
    }

    func testFolderDeletionKeepsContents() throws {
        let folder = Folder(name: "Лето", kind: .collage); context.insert(folder)
        let c = try CollageService.create(name: "К", aspect: .square, backgroundHex: "#FFFFFF", context: context)
        c.folderID = folder.id; try context.save()
        try FolderService.delete(folder, context: context)
        XCTAssertNil(c.folderID)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CollageProject>()).count, 1)
    }
}

@MainActor
final class SettingsTests: XCTestCase {
    func testTaxonomyIsExtensibleAndPersists() {
        let defaults = UserDefaults(suiteName: "aw-test-\(UUID().uuidString)")!
        let s = AppSettings(defaults: defaults)
        XCTAssertGreaterThanOrEqual(s.allCategories.count, 11)
        s.addSubcategory("Бомбер", to: "outerwear")
        let id = s.addCategory(title: "Спортивная форма")
        XCTAssertNotNil(id)
        XCTAssertNil(s.addCategory(title: "спортивная форма"), "дубликаты запрещены")
        XCTAssertTrue(s.subcategories(for: "outerwear").contains("Бомбер"))
        let reloaded = AppSettings(defaults: defaults)
        XCTAssertTrue(reloaded.subcategories(for: "outerwear").contains("Бомбер"))
        XCTAssertEqual(reloaded.categoryTitle(id!), "Спортивная форма")
    }

    func testSizeSystemsDifferByCategory() {
        XCTAssertTrue(SizeCatalog.systems(for: "shoes").contains(.shoesEU))
        XCTAssertFalse(SizeCatalog.systems(for: "tops").contains(.shoesEU))
        XCTAssertTrue(SizeSystem.letter.values.contains("M"))
    }

    func testAvatarSuggestionIgnoresWeight() {
        var m = BodyMeasurements(); m.weightKg = 40
        let a = AvatarVisual.suggested(from: m)
        m.weightKg = 120
        XCTAssertEqual(a, AvatarVisual.suggested(from: m))
    }

    func testColorNearest() {
        XCTAssertEqual(ColorPalette.nearest(to: "#FEFEFE").id, "white")
        XCTAssertEqual(ColorPalette.nearest(to: "#D04040").id, "red")
    }
}
