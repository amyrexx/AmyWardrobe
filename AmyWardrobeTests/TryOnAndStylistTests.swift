import XCTest
import SwiftData
@testable import AmyWardrobe

private struct FailingProvider: VirtualTryOnProvider {
    let id = "fail"; let displayName = "Падающий"
    func availability() -> TryOnAvailability { .available }
    func generate(_ request: TryOnRequest, progress: @escaping @Sendable (Double) -> Void) async throws -> TryOnResult {
        throw AppError.tryOnFailed("тестовая ошибка")
    }
}

private struct SlowProvider: VirtualTryOnProvider {
    let id = "slow"; let displayName = "Медленный"
    func availability() -> TryOnAvailability { .available }
    func generate(_ request: TryOnRequest, progress: @escaping @Sendable (Double) -> Void) async throws -> TryOnResult {
        try await Task.sleep(nanoseconds: 5_000_000_000)
        return TryOnResult(imageData: Data(), providerID: id, createdAt: Date(), durationSeconds: 5)
    }
}

@MainActor
final class TryOnTests: XCTestCase {
    func testGeometryIsInsideCanvasForAllExtremes() {
        for v in [AvatarVisual(), AvatarVisual(shoulder: 1.15, bust: 1.15, waist: 1.15, hip: 1.15, torso: 1.1, leg: 1.1),
                  AvatarVisual(shoulder: 0.85, bust: 0.85, waist: 0.85, hip: 0.85, torso: 0.9, leg: 0.9)] {
            let g = AvatarGeometry(visual: v)
            XCTAssertLessThan(g.footY + 40, AvatarGeometry.canvas.height)
            XCTAssertGreaterThan(g.cx - g.hipHalf, 50)
        }
    }

    func testPlacementZonesAndLayerOrder() {
        let g = AvatarGeometry(visual: AvatarVisual())
        let size = CGSize(width: 400, height: 500)
        func z(_ c: String) -> Int { GarmentPlacementEngine.place(imageSize: size, categoryID: c, subcategory: "", geometry: g, adjustment: .init()).z }
        XCTAssertLessThan(z("shoes"), z("bottoms")); XCTAssertLessThan(z("bottoms"), z("tops"))
        XCTAssertLessThan(z("tops"), z("outerwear")); XCTAssertLessThan(z("outerwear"), z("hats"))
        let top = GarmentPlacementEngine.place(imageSize: size, categoryID: "tops", subcategory: "", geometry: g, adjustment: .init()).rect
        let shoes = GarmentPlacementEngine.place(imageSize: size, categoryID: "shoes", subcategory: "", geometry: g, adjustment: .init()).rect
        XCTAssertLessThan(top.midY, shoes.midY)
        XCTAssertEqual(top.width / top.height, size.width / size.height, accuracy: 0.001, "пропорции сохраняются")
        let moved = GarmentPlacementEngine.place(imageSize: size, categoryID: "tops", subcategory: "", geometry: g,
                                                 adjustment: PlacementAdjustment(dx: 30, dy: -10, scale: 1.2, rotation: 0.1)).rect
        XCTAssertEqual(moved.midX, top.midX + 30, accuracy: 0.01)
        XCTAssertGreaterThan(moved.width, top.width)
    }

    func testCompositionRendersAndSaves() throws {
        let store = try TestSupport.makeStore(); let container = try TestSupport.makeContainer()
        let g = AvatarGeometry(visual: AvatarVisual())
        let img = UIImage(data: TestSupport.pngData(color: .red))!
        let p = GarmentPlacementEngine.place(imageSize: img.size, categoryID: "tops", subcategory: "", geometry: g, adjustment: .init())
        let out = TryOnCompositor.render(visual: AvatarVisual(), garments: [PlacedGarment(image: img, rect: p.rect, rotation: 0, z: p.z)], width: 600)
        XCTAssertEqual(out.size.width, 600); XCTAssertEqual(out.size.height, (1240.0 * 600 / 600).rounded())
        let rec = try TryOnRepository.save(imageData: out.pngData()!, mode: "compose", outfit: nil, context: container.mainContext, store: store)
        XCTAssertTrue(store.exists(rec.imageFile))
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<TryOnRecord>()).count, 1)
    }

    func testUnavailableProviderIsHonest() async throws {
        let p = UnavailableTryOnProvider()
        XCTAssertEqual(p.availability(), .unavailable(reason: p.reason))
        do { _ = try await p.generate(TryOnRequest(avatarPNG: Data(), garments: []), progress: { _ in }); XCTFail() }
        catch { XCTAssertTrue(error is AppError) }
        XCTAssertTrue(TryOnProviderFactory.make(settings: SettingsData()) is UnavailableTryOnProvider)
        var s = SettingsData(); s.tryOnEnabled = true; s.tryOnEndpoint = "https://example.com/tryon"
        XCTAssertTrue(TryOnProviderFactory.make(settings: s) is HTTPTryOnProvider)
        s.tryOnEndpoint = "javascript:alert(1)"
        XCTAssertTrue(TryOnProviderFactory.make(settings: s) is UnavailableTryOnProvider)
    }

    func testGenerationFailureDoesNotSaveResultAndAllowsRetry() async throws {
        let c = TryOnGenerationController(provider: FailingProvider())
        c.start(TryOnRequest(avatarPNG: Data(), garments: []))
        try await waitUntil { if case .failed = c.state { return true } else { return false } }
        guard case .failed(let m) = c.state else { return XCTFail() }
        XCTAssertTrue(m.contains("тестовая ошибка"))
        c.start(TryOnRequest(avatarPNG: Data(), garments: []))     // повтор
        try await waitUntil { if case .failed = c.state { return true } else { return false } }
    }

    func testGenerationCancel() async throws {
        let c = TryOnGenerationController(provider: SlowProvider())
        c.start(TryOnRequest(avatarPNG: Data(), garments: []))
        if case .running = c.state {} else { XCTFail("должно идти выполнение") }
        c.cancel()
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(c.state, .idle)
    }

    func testMultipartBody() {
        let (d, boundary) = MultipartBody.build([.field(name: "a", value: "1"), .file(name: "f", filename: "f.png", mime: "image/png", data: Data([1, 2, 3]))], boundary: "B")
        let s = String(decoding: d, as: UTF8.self)
        XCTAssertEqual(boundary, "B")
        XCTAssertTrue(s.contains("name=\"a\"\r\n\r\n1")); XCTAssertTrue(s.contains("filename=\"f.png\"")); XCTAssertTrue(s.hasSuffix("--B--\r\n"))
    }

    private func waitUntil(timeout: TimeInterval = 3, _ cond: @MainActor () -> Bool) async throws {
        let end = Date().addingTimeInterval(timeout)
        while !cond() { if Date() > end { XCTFail("таймаут ожидания"); return }; try await Task.sleep(nanoseconds: 20_000_000) }
    }
}

@MainActor
final class StylistTests: XCTestCase {
    func testSuggestionsAreDeterministicAndRuleBased() throws {
        let store = try TestSupport.makeStore(); let container = try TestSupport.makeContainer(); let ctx = container.mainContext
        try TestSupport.addItem("Белая блузка", category: "tops", store: store, context: ctx) { $0.primaryColorHex = "#FFFFFF"; $0.seasons = [.summer]; $0.tags = ["офис"] }
        try TestSupport.addItem("Чёрные брюки", category: "bottoms", color: .black, store: store, context: ctx) { $0.primaryColorHex = "#1E1B22"; $0.seasons = [.summer] }
        try TestSupport.addItem("Лоферы", category: "shoes", color: .brown, store: store, context: ctx) { $0.primaryColorHex = "#7B5A44" }
        let items = try ctx.fetch(FetchDescriptor<WardrobeItem>())
        let a = StylistEngine.suggest(items: items, occasion: .office, season: .summer, seed: 5)
        let b = StylistEngine.suggest(items: items, occasion: .office, season: .summer, seed: 5)
        XCTAssertEqual(a.count, 1)
        XCTAssertEqual(a.first?.items.map(\.name), b.first?.items.map(\.name))
        XCTAssertEqual(Set(a[0].items.map(\.name)), ["Белая блузка", "Чёрные брюки", "Лоферы"])
        XCTAssertTrue(a[0].reasons.contains { $0.contains("повод") || $0.contains("сезон") })
    }

    func testColorHarmony() {
        XCTAssertGreaterThan(StylistEngine.colorHarmony(["#FFFFFF", "#1E1B22"]).score, 0)
        XCTAssertLessThan(StylistEngine.colorHarmony(["#D64550", "#6BAA75", "#3F5FB5"]).score, 1.5)
    }

    func testSeasonByMonth() {
        let c = Calendar(identifier: .gregorian)
        XCTAssertEqual(Season.current(c.date(from: DateComponents(year: 2026, month: 1, day: 5))!, calendar: c), .winter)
        XCTAssertEqual(Season.current(c.date(from: DateComponents(year: 2026, month: 7, day: 5))!, calendar: c), .summer)
    }

    func testErrorMessagesAreRussian() {
        XCTAssertTrue(AppError.diskFull.localizedDescription.contains("свободного места"))
        XCTAssertEqual(AppAlert(error: AppError.permissionDenied("Нет доступа к «Фото»")).message, "Нет доступа к «Фото»")
        XCTAssertNotNil(AppError.tryOnTimeout.errorDescription)
    }
}
