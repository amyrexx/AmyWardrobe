import XCTest
import SwiftData
import UIKit
@testable import AmyWardrobe

enum TestSupport {
    static func tempDir(_ name: String = UUID().uuidString) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("AWTests-\(name)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func makeStore() throws -> ImageStore { try ImageStore(root: tempDir()) }

    /// Синтетическое PNG с прозрачными углами (личных фото в тестах нет).
    static func pngData(color: UIColor = .systemPink, size: CGSize = CGSize(width: 64, height: 96)) -> Data {
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1; fmt.opaque = false
        return UIGraphicsImageRenderer(size: size, format: fmt).image { _ in
            color.setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 8, dy: 8), cornerRadius: 12).fill()
        }.pngData()!
    }

    @MainActor
    static func makeContainer() throws -> ModelContainer { try PersistenceController.makeContainer(inMemory: true) }

    @MainActor
    @discardableResult
    static func addItem(_ name: String, category: String = "tops", color: UIColor = .systemPink, store: ImageStore,
                        context: ModelContext, configure: (WardrobeItem) -> Void = { _ in }) throws -> WardrobeItem {
        try WardrobeService.addItem(name: name, categoryID: category, imageData: pngData(color: color), context: context, store: store, configure: configure)
    }
}
