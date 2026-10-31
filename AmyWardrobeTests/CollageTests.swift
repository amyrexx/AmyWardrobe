import XCTest
import SwiftData
@testable import AmyWardrobe

final class CollageDocumentTests: XCTestCase {
    private func obj(_ x: Double = 100, _ y: Double = 100) -> CollageObject {
        CollageObject.image(file: String(repeating: "a", count: 64) + ".png", itemID: nil, pixelSize: CGSize(width: 200, height: 100), at: CGPoint(x: x, y: y), maxSide: 400)
    }

    func testLayerOrdering() {
        var doc = CollageDocument.blank(aspect: .square)
        let a = obj(), b = obj(), c = obj()
        doc.objects = [a, b, c]
        doc.bringToFront(a.id); XCTAssertEqual(doc.objects.map(\.id), [b.id, c.id, a.id])
        doc.sendToBack(a.id); XCTAssertEqual(doc.objects.map(\.id), [a.id, b.id, c.id])
        doc.moveForward(a.id); XCTAssertEqual(doc.objects.map(\.id), [b.id, a.id, c.id])
        doc.moveBackward(a.id); XCTAssertEqual(doc.objects.map(\.id), [a.id, b.id, c.id])
        doc.moveBackward(a.id); XCTAssertEqual(doc.objects.first?.id, a.id, "нижний слой остаётся нижним")
    }

    func testDuplicateDeleteCenter() {
        var doc = CollageDocument.blank(aspect: .square)
        let a = obj(10, 20); doc.objects = [a]
        let copyID = try! XCTUnwrap(doc.duplicate(a.id))
        XCTAssertEqual(doc.objects.count, 2)
        XCTAssertNotEqual(copyID, a.id)
        doc.centerOnCanvas(copyID)
        XCTAssertEqual(doc.object(copyID)?.centerX, 540)
        doc.remove(a.id); XCTAssertEqual(doc.objects.count, 1)
    }

    func testAspectKeepsImageProportions() {
        let o = obj()
        XCTAssertEqual(o.width / o.height, 2, accuracy: 0.001)
        XCTAssertEqual(max(o.width, o.height), 400, accuracy: 0.001)
    }

    func testCodableRoundTripKeepsTransforms() throws {
        var doc = CollageDocument.blank(aspect: .portrait45)
        var o = obj(321.5, 654.25); o.scale = 1.75; o.rotation = 0.6; o.flippedX = true
        doc.objects = [o, CollageObject.text(TextStyle(content: "Привет"), at: CGPoint(x: 5, y: 5)), CollageObject.frame(at: CGPoint(x: 9, y: 9))]
        doc.background = .gradient(topHex: "#FFFFFF", bottomHex: "#F4E5F0")
        let data = try JSONEncoder().encode(doc)
        let back = try JSONDecoder().decode(CollageDocument.self, from: data)
        XCTAssertEqual(back, doc)
        XCTAssertEqual(back.objects[0].scale, 1.75); XCTAssertEqual(back.objects[0].rotation, 0.6)
    }

    func testResizeCanvasScalesObjects() {
        var doc = CollageDocument.blank(aspect: .square)
        var o = obj(540, 540); o.scale = 1; doc.objects = [o]
        doc.resizeCanvas(to: CGSize(width: 2160, height: 2160))
        XCTAssertEqual(doc.objects[0].centerX, 1080, accuracy: 0.001)
        XCTAssertEqual(doc.objects[0].scale, 2, accuracy: 0.001)
    }
}

@MainActor
final class CollageEditorTests: XCTestCase {
    var store: ImageStore!
    var container: ModelContainer!
    var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        store = try TestSupport.makeStore()
        container = try TestSupport.makeContainer()
    }

    func makeModel() throws -> (CollageEditorModel, CollageProject) {
        let p = try CollageService.create(name: "Тест", aspect: .portrait45, backgroundHex: "#F5F0FC", context: context)
        return (CollageEditorModel(project: p, context: context, store: store), p)
    }

    func testAddMoveScaleRotateAndRestore() throws {
        let item = try TestSupport.addItem("Топ", store: store, context: context)
        let (model, project) = try makeModel()
        model.addItems([item])
        let id = try XCTUnwrap(model.selectedID)
        model.dragChanged(id, translation: CGSize(width: 50, height: -30)); model.dragEnded()
        model.magnifyChanged(id, factor: 2); model.magnifyEnded()
        model.rotateChanged(id, delta: 0.5); model.rotateEnded()
        let o = try XCTUnwrap(model.document.object(id))
        XCTAssertEqual(o.centerX, 540 + 50, accuracy: 0.001)
        XCTAssertEqual(o.centerY, 675 - 30, accuracy: 0.001)
        XCTAssertEqual(o.scale, 2, accuracy: 0.001)
        XCTAssertEqual(o.rotation, 0.5, accuracy: 0.001)
        XCTAssertEqual(o.itemID, item.id)
        model.saveNow()
        // «перезапуск»: новая модель читает сохранённый проект
        let restored = CollageEditorModel(project: project, context: context, store: store)
        XCTAssertEqual(restored.document, model.document)
    }

    func testUndoRedo() throws {
        let (model, _) = try makeModel()
        model.addText()
        XCTAssertEqual(model.document.objects.count, 1); XCTAssertTrue(model.canUndo)
        model.undo(); XCTAssertEqual(model.document.objects.count, 0); XCTAssertTrue(model.canRedo)
        model.redo(); XCTAssertEqual(model.document.objects.count, 1)
    }

    func testGestureIsSingleUndoStep() throws {
        let (model, _) = try makeModel()
        model.addFrame()
        let id = try XCTUnwrap(model.selectedID)
        let start = try XCTUnwrap(model.document.object(id)).centerX
        for i in 1...10 { model.dragChanged(id, translation: CGSize(width: Double(i) * 5, height: 0)) }
        model.dragEnded()
        model.undo()
        XCTAssertEqual(try XCTUnwrap(model.document.object(id)).centerX, start, accuracy: 0.001)
    }

    func testRevertSessionAndChangeDetection() throws {
        let (model, _) = try makeModel()
        XCTAssertFalse(model.hasSessionChanges)
        model.addText(); XCTAssertTrue(model.hasSessionChanges)
        model.revertSession(); XCTAssertFalse(model.hasSessionChanges); XCTAssertTrue(model.document.objects.isEmpty)
    }

    func testTextEditingRefitsHeight() throws {
        let (model, _) = try makeModel()
        model.addText()
        let h1 = try XCTUnwrap(model.selected).height
        model.updateText { $0.content = "Длинный текст\nв три\nстроки"; $0.fontSize = 120 }
        XCTAssertGreaterThan(try XCTUnwrap(model.selected).height, h1)
    }

    func testExportRenderIsRealCompositionWithoutUI() throws {
        let item = try TestSupport.addItem("Топ", color: .red, store: store, context: context)
        let (model, _) = try makeModel()
        model.addItems([item]); model.addText(); model.addFrame()
        model.setBackground(.solid(hex: "#FFFFFF"))
        let img = CollageRenderer.render(model.document, store: store)
        XCTAssertEqual(img.size, CGSize(width: 1080, height: 1350))
        XCTAssertNotNil(img.pngData()); XCTAssertNotNil(img.jpegData(compressionQuality: 0.9))
        // центр холста содержит красную вещь, угол — белый фон
        let corner = pixel(img, 5, 5), center = pixel(img, 540, 800)
        XCTAssertGreaterThan(corner.r, 240); XCTAssertGreaterThan(corner.g, 240)
        XCTAssertGreaterThan(center.r, center.g + 40, "в центре должна быть красная вещь")
    }

    func testMissingImageDoesNotBreakRender() throws {
        var doc = CollageDocument.blank(aspect: .square)
        doc.objects = [CollageObject.image(file: String(repeating: "b", count: 64) + ".png", itemID: UUID(), pixelSize: CGSize(width: 10, height: 10), at: CGPoint(x: 500, y: 500), maxSide: 300)]
        XCTAssertEqual(CollageRenderer.render(doc, store: store).size.width, 1080)
    }

    func testRenameOrDeleteOfItemDoesNotBreakCollage() throws {
        let item = try TestSupport.addItem("Топ", color: .green, store: store, context: context)
        let (model, project) = try makeModel()
        model.addItems([item]); model.saveNow()
        item.name = "Новое имя"; try WardrobeService.delete([item], context: context, store: store)
        GarbageCollector.run(context: context, store: store, grace: 0)
        let file = try XCTUnwrap(project.document.objects.first?.imageFile)
        XCTAssertTrue(store.exists(file), "коллаж хранит собственную ссылку на изображение")
    }

    private func pixel(_ img: UIImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
        let cg = img.cgImage!
        var px = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: -x, y: -(cg.height - 1 - y), width: cg.width, height: cg.height))
        return (Int(px[0]), Int(px[1]), Int(px[2]))
    }
}
