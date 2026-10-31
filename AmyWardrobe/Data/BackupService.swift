import Foundation
import SwiftData
import CryptoKit

// MARK: - Формат архива v1
//
//   manifest.json   — версия формата, счётчики, список файлов с SHA-256 (создаётся последним)
//   data.json       — вся структурированная информация (вещи, коллажи, образы, папки, история примерки, настройки)
//   images/<sha256>.<ext> — оригиналы изображений (контентно-адресуемые имена)
//
// Миниатюры в архив не кладутся: они пересоздаются автоматически.

struct BackupManifest: Codable, Equatable {
    static let currentFormat = 1
    struct Counts: Codable, Equatable { var items = 0, collages = 0, outfits = 0, folders = 0, tryOns = 0, images = 0 }
    struct FileEntry: Codable, Equatable { var path: String; var size: Int; var sha256: String }
    var formatVersion: Int
    var appVersion: String
    var createdAt: Date
    var counts: Counts
    var files: [FileEntry]
    var warnings: [String] = []
}

struct ItemDTO: Codable, Equatable {
    var id: UUID, name: String, categoryID: String, subcategory: String, imageFile: String, extraImageFiles: [String]
    var primaryColorHex: String, secondaryColorHexes: [String], sizeSystem: String, sizeValue: String, material: String
    var details: String, seasonRaws: [String], tags: [String], isFavorite: Bool, createdAt: Date, updatedAt: Date
    var notes: String, wearCount: Int, lastWornAt: Date?

    init(_ m: WardrobeItem) {
        id = m.id; name = m.name; categoryID = m.categoryID; subcategory = m.subcategory; imageFile = m.imageFile
        extraImageFiles = m.extraImageFiles; primaryColorHex = m.primaryColorHex; secondaryColorHexes = m.secondaryColorHexes
        sizeSystem = m.sizeSystem; sizeValue = m.sizeValue; material = m.material; details = m.details
        seasonRaws = m.seasonRaws; tags = m.tags; isFavorite = m.isFavorite; createdAt = m.createdAt
        updatedAt = m.updatedAt; notes = m.notes; wearCount = m.wearCount; lastWornAt = m.lastWornAt
    }
    func apply(to m: WardrobeItem) {
        m.name = name; m.categoryID = categoryID; m.subcategory = subcategory; m.imageFile = imageFile
        m.extraImageFiles = extraImageFiles; m.primaryColorHex = primaryColorHex; m.secondaryColorHexes = secondaryColorHexes
        m.sizeSystem = sizeSystem; m.sizeValue = sizeValue; m.material = material; m.details = details
        m.seasonRaws = seasonRaws; m.tags = tags; m.isFavorite = isFavorite; m.createdAt = createdAt
        m.updatedAt = updatedAt; m.notes = notes; m.wearCount = wearCount; m.lastWornAt = lastWornAt
    }
}

struct FolderDTO: Codable, Equatable {
    var id: UUID, name: String, kind: String, createdAt: Date, updatedAt: Date
    init(_ m: Folder) { id = m.id; name = m.name; kind = m.kindRaw; createdAt = m.createdAt; updatedAt = m.updatedAt }
}

struct CollageDTO: Codable, Equatable {
    var id: UUID, name: String, document: CollageDocument, tags: [String], isFavorite: Bool
    var folderID: UUID?, previewFile: String?, createdAt: Date, updatedAt: Date
    init(_ m: CollageProject) {
        id = m.id; name = m.name; document = m.document; tags = m.tags; isFavorite = m.isFavorite
        folderID = m.folderID; previewFile = m.previewFile; createdAt = m.createdAt; updatedAt = m.updatedAt
    }
}

struct OutfitDTO: Codable, Equatable {
    var id: UUID, name: String, details: String, entries: [OutfitEntry], tags: [String], isFavorite: Bool
    var folderID: UUID?, previewFile: String?, tryOnFile: String?, sourceCollageID: UUID?, origin: String
    var createdAt: Date, updatedAt: Date
    init(_ m: Outfit) {
        id = m.id; name = m.name; details = m.details; entries = m.entries; tags = m.tags; isFavorite = m.isFavorite
        folderID = m.folderID; previewFile = m.previewFile; tryOnFile = m.tryOnFile; sourceCollageID = m.sourceCollageID
        origin = m.originRaw; createdAt = m.createdAt; updatedAt = m.updatedAt
    }
}

struct TryOnDTO: Codable, Equatable {
    var id: UUID, createdAt: Date, imageFile: String, mode: String, outfitID: UUID?, note: String
    init(_ m: TryOnRecord) { id = m.id; createdAt = m.createdAt; imageFile = m.imageFile; mode = m.modeRaw; outfitID = m.outfitID; note = m.note }
}

struct BackupPayload: Codable, Equatable {
    var items: [ItemDTO] = []
    var collages: [CollageDTO] = []
    var outfits: [OutfitDTO] = []
    var folders: [FolderDTO] = []
    var tryOns: [TryOnDTO] = []
    var settings = SettingsData()

    /// Все файлы изображений, которые нужны данным.
    var referencedFiles: Set<String> {
        var s = Set<String>()
        for i in items { s.insert(i.imageFile); s.formUnion(i.extraImageFiles) }
        for c in collages { s.formUnion(c.document.referencedFiles); if let p = c.previewFile { s.insert(p) } }
        for o in outfits { s.formUnion(o.entries.map(\.imageFile)); if let p = o.previewFile { s.insert(p) }; if let t = o.tryOnFile { s.insert(t) } }
        for t in tryOns { s.insert(t.imageFile) }
        return s
    }
}

struct BackupInspection {
    let manifest: BackupManifest
    let payload: BackupPayload
    let reader: ZipReader
    var summary: String {
        "Вещей: \(manifest.counts.items), коллажей: \(manifest.counts.collages), образов: \(manifest.counts.outfits), "
        + "изображений: \(manifest.counts.images). Создана \(manifest.createdAt.formatted(date: .abbreviated, time: .shortened))."
    }
}

struct RestoreReport: Equatable {
    var added = 0, updated = 0, skipped = 0, imagesCopied = 0
    var warnings: [String] = []
    var summary: String {
        "Добавлено: \(added), обновлено: \(updated), без изменений: \(skipped), изображений: \(imagesCopied)."
    }
}

enum BackupService {
    static var encoder: JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys, .prettyPrinted]; return e
    }
    static var decoder: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }

    // MARK: Экспорт

    @MainActor
    static func makePayload(context: ModelContext, settings: SettingsData) throws -> BackupPayload {
        var p = BackupPayload()
        p.items = try context.fetch(FetchDescriptor<WardrobeItem>()).map(ItemDTO.init)
        p.collages = try context.fetch(FetchDescriptor<CollageProject>()).map(CollageDTO.init)
        p.outfits = try context.fetch(FetchDescriptor<Outfit>()).map(OutfitDTO.init)
        p.folders = try context.fetch(FetchDescriptor<Folder>()).map(FolderDTO.init)
        p.tryOns = try context.fetch(FetchDescriptor<TryOnRecord>()).map(TryOnDTO.init)
        p.settings = settings
        return p
    }

    static func backupsDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Пишет архив во временный файл и только затем атомарно перемещает на место — частично записанных копий не бывает.
    static func writeArchive(payload: BackupPayload, store: ImageStore, to directory: URL, now: Date = Date(), appVersion: String = "1.0.0") throws -> URL {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyyMMdd-HHmmss"; fmt.locale = Locale(identifier: "en_US_POSIX")
        let finalURL = directory.appendingPathComponent("AmyWardrobe-Backup-\(fmt.string(from: now)).zip")
        let tmpURL = directory.appendingPathComponent(".tmp-\(UUID().uuidString).zip")
        do {
            let writer = try ZipWriter(url: tmpURL)
            var files: [BackupManifest.FileEntry] = []
            var warnings: [String] = []
            var imageCount = 0
            for name in payload.referencedFiles.sorted() {
                guard ImageStore.isValidFileName(name) else { warnings.append("Пропущено недопустимое имя файла: \(name)"); continue }
                guard let data = try? store.loadData(name) else { warnings.append("Нет файла изображения: \(name)"); continue }
                let path = "images/\(name)"
                try writer.add(name: path, data: data)
                files.append(.init(path: path, size: data.count, sha256: ImageStore.sha256Hex(data)))
                imageCount += 1
            }
            let dataJSON = try encoder.encode(payload)
            try writer.add(name: "data.json", data: dataJSON)
            files.append(.init(path: "data.json", size: dataJSON.count, sha256: ImageStore.sha256Hex(dataJSON)))
            let manifest = BackupManifest(
                formatVersion: BackupManifest.currentFormat, appVersion: appVersion, createdAt: now,
                counts: .init(items: payload.items.count, collages: payload.collages.count, outfits: payload.outfits.count,
                              folders: payload.folders.count, tryOns: payload.tryOns.count, images: imageCount),
                files: files, warnings: warnings)
            try writer.add(name: "manifest.json", data: try encoder.encode(manifest))
            try writer.finish()
            if FileManager.default.fileExists(atPath: finalURL.path) { try FileManager.default.removeItem(at: finalURL) }
            try FileManager.default.moveItem(at: tmpURL, to: finalURL)
            return finalURL
        } catch let e as ZipError where e == .tooLarge {
            try? FileManager.default.removeItem(at: tmpURL)
            throw AppError.exportFailed("Архив слишком большой для формата ZIP без ZIP64 (лимит 4 ГиБ).")
        } catch {
            try? FileManager.default.removeItem(at: tmpURL)
            throw ImageStore.map(error)
        }
    }

    // MARK: Проверка (ничего не меняет в данных приложения)

    static func inspect(archive url: URL) throws -> BackupInspection {
        let reader: ZipReader
        do { reader = try ZipReader(url: url) } catch { throw AppError.backupCorrupt("файл не является ZIP-архивом или повреждён") }
        guard reader.has("manifest.json") else { throw AppError.backupCorrupt("нет manifest.json") }
        let manifest: BackupManifest
        do { manifest = try decoder.decode(BackupManifest.self, from: try reader.read("manifest.json")) }
        catch { throw AppError.backupCorrupt("manifest.json не читается") }
        guard manifest.formatVersion <= BackupManifest.currentFormat else { throw AppError.backupUnsupportedVersion(manifest.formatVersion) }
        guard manifest.formatVersion >= 1 else { throw AppError.backupCorrupt("неизвестная версия формата") }

        // Целостность: каждый файл из манифеста существует, имеет верный размер и SHA-256 (и CRC в ZIP).
        for f in manifest.files {
            guard f.path == "data.json" || (f.path.hasPrefix("images/") && ImageStore.isValidFileName(String(f.path.dropFirst(7)))) else {
                throw AppError.backupCorrupt("недопустимый путь в архиве: \(f.path)")
            }
            let data: Data
            do { data = try reader.read(f.path) } catch { throw AppError.backupCorrupt("файл \(f.path) повреждён или отсутствует") }
            guard data.count == f.size, ImageStore.sha256Hex(data) == f.sha256 else { throw AppError.backupCorrupt("контрольная сумма не совпала: \(f.path)") }
            if f.path.hasPrefix("images/") {
                guard ImageStore.sha256Hex(data) == String(f.path.dropFirst(7).prefix(64)) else { throw AppError.backupCorrupt("имя файла не соответствует содержимому: \(f.path)") }
                guard ImageStore.pixelSize(of: data) != nil else { throw AppError.backupCorrupt("изображение не читается: \(f.path)") }
            }
        }
        guard manifest.files.contains(where: { $0.path == "data.json" }) else { throw AppError.backupCorrupt("нет data.json") }
        let payload: BackupPayload
        do { payload = try decoder.decode(BackupPayload.self, from: try reader.read("data.json")) }
        catch { throw AppError.backupCorrupt("обязательные поля в data.json отсутствуют или неверны") }

        let available = Set(manifest.files.map(\.path))
        var warnings = manifest.warnings
        for f in payload.referencedFiles where !available.contains("images/\(f)") {
            warnings.append("В архиве нет изображения \(f.prefix(8))… — соответствующие вещи покажут заглушку")
        }
        var m = manifest; m.warnings = warnings
        return BackupInspection(manifest: m, payload: payload, reader: reader)
    }

    // MARK: Восстановление (слияние без дублей)

    @MainActor
    static func restore(_ inspection: BackupInspection, into context: ModelContext, store: ImageStore,
                        settings: AppSettings? = nil, restoreSettings: Bool = true) throws -> RestoreReport {
        var report = RestoreReport(warnings: inspection.manifest.warnings)
        // 1. Копируем изображения (идемпотентно: имена — хэши содержимого)
        for f in inspection.manifest.files where f.path.hasPrefix("images/") {
            let data = try inspection.reader.read(f.path)
            let saved = try store.save(data: data)
            if saved != String(f.path.dropFirst(7)) { throw AppError.backupCorrupt("имя изображения не совпало: \(f.path)") }
            report.imagesCopied += 1
        }
        // 2. Обновляем БД одной транзакцией
        let p = inspection.payload
        do {
            let items = Dictionary(try context.fetch(FetchDescriptor<WardrobeItem>()).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for d in p.items {
                if let e = items[d.id] {
                    if d.updatedAt > e.updatedAt { d.apply(to: e); report.updated += 1 } else { report.skipped += 1 }
                } else {
                    let m = WardrobeItem(name: d.name, categoryID: d.categoryID, imageFile: d.imageFile)
                    m.id = d.id; d.apply(to: m); context.insert(m); report.added += 1
                }
            }
            let folders = Dictionary(try context.fetch(FetchDescriptor<Folder>()).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for d in p.folders {
                if let e = folders[d.id] {
                    if d.updatedAt > e.updatedAt { e.name = d.name; e.updatedAt = d.updatedAt; report.updated += 1 } else { report.skipped += 1 }
                } else {
                    let m = Folder(name: d.name, kind: FolderKind(rawValue: d.kind) ?? .collage)
                    m.id = d.id; m.createdAt = d.createdAt; m.updatedAt = d.updatedAt; context.insert(m); report.added += 1
                }
            }
            let collages = Dictionary(try context.fetch(FetchDescriptor<CollageProject>()).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for d in p.collages {
                func fill(_ m: CollageProject) {
                    m.name = d.name; m.document = d.document; m.tags = d.tags; m.isFavorite = d.isFavorite
                    m.folderID = d.folderID; m.previewFile = d.previewFile; m.createdAt = d.createdAt; m.updatedAt = d.updatedAt
                }
                if let e = collages[d.id] {
                    if d.updatedAt > e.updatedAt { fill(e); report.updated += 1 } else { report.skipped += 1 }
                } else {
                    let m = CollageProject(name: d.name, document: d.document); m.id = d.id; fill(m); context.insert(m); report.added += 1
                }
            }
            let outfits = Dictionary(try context.fetch(FetchDescriptor<Outfit>()).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for d in p.outfits {
                func fill(_ m: Outfit) {
                    m.name = d.name; m.details = d.details; m.entries = d.entries; m.tags = d.tags; m.isFavorite = d.isFavorite
                    m.folderID = d.folderID; m.previewFile = d.previewFile; m.tryOnFile = d.tryOnFile
                    m.sourceCollageID = d.sourceCollageID; m.originRaw = d.origin; m.createdAt = d.createdAt; m.updatedAt = d.updatedAt
                }
                if let e = outfits[d.id] {
                    if d.updatedAt > e.updatedAt { fill(e); report.updated += 1 } else { report.skipped += 1 }
                } else {
                    let m = Outfit(name: d.name, entries: d.entries, origin: OutfitOrigin(rawValue: d.origin) ?? .items)
                    m.id = d.id; fill(m); context.insert(m); report.added += 1
                }
            }
            let records = Set(try context.fetch(FetchDescriptor<TryOnRecord>()).map(\.id))
            for d in p.tryOns {
                if records.contains(d.id) { report.skipped += 1 } else {
                    let m = TryOnRecord(imageFile: d.imageFile, modeRaw: d.mode, outfitID: d.outfitID)
                    m.id = d.id; m.createdAt = d.createdAt; m.note = d.note; context.insert(m); report.added += 1
                }
            }
            try context.save()
        } catch {
            context.rollback()   // текущие данные остаются нетронутыми
            throw error
        }
        if restoreSettings, let settings {
            var s = p.settings
            s.lastBackupAt = settings.data.lastBackupAt
            settings.data = s
        }
        return report
    }
}
