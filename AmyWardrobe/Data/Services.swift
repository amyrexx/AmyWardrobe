import Foundation
import SwiftData
import UIKit

/// Сборщик мусора: удаляет файлы изображений, на которые больше нет ссылок ни из вещей, ни из коллажей, ни из образов.
/// Если хоть один документ не удалось разобрать — ничего не удаляется (безопасность важнее места).
enum GarbageCollector {
    @MainActor
    static func referencedFiles(context: ModelContext) -> Set<String>? {
        var files = Set<String>()
        do {
            for i in try context.fetch(FetchDescriptor<WardrobeItem>()) {
                files.insert(i.imageFile); files.formUnion(i.extraImageFiles)
            }
            for c in try context.fetch(FetchDescriptor<CollageProject>()) {
                guard let doc = try? JSONDecoder().decode(CollageDocument.self, from: c.documentData) else { return nil }
                files.formUnion(doc.referencedFiles)
                if let p = c.previewFile { files.insert(p) }
            }
            for o in try context.fetch(FetchDescriptor<Outfit>()) {
                guard let entries = try? JSONDecoder().decode([OutfitEntry].self, from: o.entriesData) else { return nil }
                files.formUnion(entries.map(\.imageFile))
                if let p = o.previewFile { files.insert(p) }
                if let t = o.tryOnFile { files.insert(t) }
            }
            for r in try context.fetch(FetchDescriptor<TryOnRecord>()) { files.insert(r.imageFile) }
        } catch {
            return nil
        }
        return files
    }

    @MainActor @discardableResult
    static func run(context: ModelContext, store: ImageStore = .shared, grace: TimeInterval = 600) -> Int {
        guard let refs = referencedFiles(context: context) else { return 0 }
        return store.collectGarbage(referenced: refs, grace: grace)
    }
}

enum WardrobeService {
    /// Создаёт вещь из исходных байт изображения (оригинал сохраняется без изменений).
    @MainActor
    static func addItem(name: String, categoryID: String, imageData: Data, context: ModelContext,
                        store: ImageStore = .shared, configure: (WardrobeItem) -> Void = { _ in }) throws -> WardrobeItem {
        let file = try store.save(data: imageData)
        let item = WardrobeItem(name: name, categoryID: categoryID, imageFile: file)
        configure(item)
        context.insert(item)
        do { try context.save() } catch { context.rollback(); throw error }
        return item
    }

    /// Удаляет вещи. Образы и коллажи сохраняют собственные ссылки на изображения, поэтому не разрушаются.
    @MainActor
    static func delete(_ items: [WardrobeItem], context: ModelContext, store: ImageStore = .shared) throws {
        for i in items { context.delete(i) }
        do { try context.save() } catch { context.rollback(); throw error }
        GarbageCollector.run(context: context, store: store)
    }

    @MainActor
    static func markWorn(_ item: WardrobeItem, context: ModelContext) {
        item.wearCount += 1
        item.lastWornAt = Date()
        item.updatedAt = Date()
        try? context.save()
    }
}

enum OutfitService {
    static func entries(from items: [WardrobeItem]) -> [OutfitEntry] {
        items.map { OutfitEntry(itemID: $0.id, name: $0.name, categoryID: $0.categoryID,
                                subcategory: $0.subcategory, imageFile: $0.imageFile) }
    }

    /// Автоматическая раскладка вещей по сетке для превью образа.
    static func autoLayoutDocument(for entries: [OutfitEntry], store: ImageStore) -> CollageDocument {
        var doc = CollageDocument.blank(aspect: .portrait45)
        let n = max(1, entries.count)
        let cols = n <= 1 ? 1 : (n <= 4 ? 2 : 3)
        let rows = Int(ceil(Double(n) / Double(cols)))
        let margin = 60.0
        let cellW = (doc.canvasWidth - margin * 2) / Double(cols)
        let cellH = (doc.canvasHeight - margin * 2) / Double(rows)
        for (i, e) in entries.enumerated() {
            let r = i / cols, c = i % cols
            let rowCount = min(cols, entries.count - r * cols)
            let offsetX = Double(cols - rowCount) * cellW / 2   // центрируем неполный ряд
            let size = store.pixelSize(fileName: e.imageFile) ?? CGSize(width: 1, height: 1)
            let side = min(cellW, cellH) * 0.88
            let center = CGPoint(x: margin + offsetX + cellW * (Double(c) + 0.5), y: margin + cellH * (Double(r) + 0.5))
            doc.objects.append(CollageObject.image(file: e.imageFile, itemID: e.itemID, pixelSize: size, at: center, maxSide: side))
        }
        return doc
    }

    @MainActor
    static func renderPreview(for outfit: Outfit, store: ImageStore = .shared) {
        let doc = autoLayoutDocument(for: outfit.entries, store: store)
        if let data = CollageRenderer.render(doc, store: store, maxSide: 720).jpegData(compressionQuality: 0.85),
           let file = try? store.save(data: data) {
            outfit.previewFile = file
        }
    }

    @MainActor
    static func create(from items: [WardrobeItem], name: String, context: ModelContext, store: ImageStore = .shared) throws -> Outfit {
        guard !items.isEmpty else { throw AppError.validation("Выберите хотя бы одну вещь.") }
        let outfit = Outfit(name: name.isEmpty ? "Новый образ" : name, entries: entries(from: items), origin: .items)
        renderPreview(for: outfit, store: store)
        context.insert(outfit)
        do { try context.save() } catch { context.rollback(); throw error }
        return outfit
    }

    /// Создаёт ОТДЕЛЬНЫЙ образ из коллажа; исходный коллаж не изменяется.
    @MainActor
    static func create(from collage: CollageProject, items: [WardrobeItem], context: ModelContext, store: ImageStore = .shared) throws -> Outfit {
        let lookup = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var entries: [OutfitEntry] = []
        for obj in collage.document.objects where obj.kind == .image {
            guard let file = obj.imageFile else { continue }
            if let id = obj.itemID, let item = lookup[id] {
                entries.append(OutfitEntry(itemID: id, name: item.name, categoryID: item.categoryID, subcategory: item.subcategory, imageFile: file))
            } else {
                entries.append(OutfitEntry(itemID: obj.itemID, name: "Фото из коллажа", categoryID: "other", subcategory: "", imageFile: file))
            }
        }
        guard !entries.isEmpty else { throw AppError.validation("В коллаже нет изображений вещей.") }
        let outfit = Outfit(name: collage.name, entries: entries, origin: .collage)
        outfit.sourceCollageID = collage.id
        outfit.previewFile = collage.previewFile
        if outfit.previewFile == nil { renderPreview(for: outfit, store: store) }
        context.insert(outfit)
        do { try context.save() } catch { context.rollback(); throw error }
        return outfit
    }

    @MainActor
    static func duplicate(_ outfit: Outfit, context: ModelContext) throws -> Outfit {
        let copy = Outfit(name: outfit.name + " (копия)", entries: outfit.entries, origin: outfit.origin)
        copy.details = outfit.details; copy.tags = outfit.tags; copy.folderID = outfit.folderID
        copy.previewFile = outfit.previewFile; copy.tryOnFile = outfit.tryOnFile
        copy.sourceCollageID = outfit.sourceCollageID
        context.insert(copy)
        do { try context.save() } catch { context.rollback(); throw error }
        return copy
    }
}

enum CollageService {
    @MainActor
    static func create(name: String, aspect: CollageAspect, backgroundHex: String, context: ModelContext) throws -> CollageProject {
        let p = CollageProject(name: name.isEmpty ? "Новый коллаж" : name, document: .blank(aspect: aspect, backgroundHex: backgroundHex))
        context.insert(p)
        do { try context.save() } catch { context.rollback(); throw error }
        return p
    }

    @MainActor
    static func duplicate(_ p: CollageProject, context: ModelContext) throws -> CollageProject {
        let copy = CollageProject(name: p.name + " (копия)", document: p.document)
        copy.tags = p.tags; copy.folderID = p.folderID; copy.previewFile = p.previewFile
        context.insert(copy)
        do { try context.save() } catch { context.rollback(); throw error }
        return copy
    }

    @MainActor
    static func delete(_ p: CollageProject, context: ModelContext, store: ImageStore = .shared) throws {
        context.delete(p)
        do { try context.save() } catch { context.rollback(); throw error }
        GarbageCollector.run(context: context, store: store)
    }
}

enum FolderService {
    /// Удаление папки не удаляет содержимое — оно переносится «в корень».
    @MainActor
    static func delete(_ folder: Folder, context: ModelContext) throws {
        let id = folder.id
        for c in try context.fetch(FetchDescriptor<CollageProject>(predicate: #Predicate { $0.folderID == id })) { c.folderID = nil }
        for o in try context.fetch(FetchDescriptor<Outfit>(predicate: #Predicate { $0.folderID == id })) { o.folderID = nil }
        context.delete(folder)
        do { try context.save() } catch { context.rollback(); throw error }
    }
}
