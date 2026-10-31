import Foundation
import UIKit
import ImageIO
import CryptoKit

/// Контентно-адресуемое хранилище изображений.
///
/// * Оригинал сохраняется «как есть» (без перекодирования) под именем `<sha256>.<ext>`.
///   Одинаковые файлы не дублируются, ссылки (имена файлов) постоянны и не зависят от кеша/временных путей.
/// * Миниатюры лежат отдельно (`Thumbs/`) и пересоздаются при необходимости.
/// * Удаление выполняется только сборщиком мусора по списку реально используемых файлов.
final class ImageStore: @unchecked Sendable {
    static let thumbPixel = 400

    static let shared: ImageStore = {
        do { return try ImageStore(root: ImageStore.defaultRoot()) } catch {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("AmyWardrobeFallback", isDirectory: true)
            return try! ImageStore(root: tmp)
        }
    }()

    let root: URL
    let imagesDir: URL
    let thumbsDir: URL

    init(root: URL) throws {
        self.root = root
        self.imagesDir = root.appendingPathComponent("Images", isDirectory: true)
        self.thumbsDir = root.appendingPathComponent("Thumbs", isDirectory: true)
        try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: thumbsDir, withIntermediateDirectories: true)
    }

    static func defaultRoot() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AmyWardrobe", isDirectory: true)
    }

    // MARK: - Имена файлов

    static func fileName(for data: Data) -> String {
        sha256Hex(data) + "." + fileExtension(for: data)
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func fileExtension(for data: Data) -> String {
        let b = [UInt8](data.prefix(16))
        if b.count >= 8, b[0] == 0x89, b[1] == 0x50, b[2] == 0x4E, b[3] == 0x47 { return "png" }
        if b.count >= 3, b[0] == 0xFF, b[1] == 0xD8, b[2] == 0xFF { return "jpg" }
        if b.count >= 12, b[4] == 0x66, b[5] == 0x74, b[6] == 0x79, b[7] == 0x70 { return "heic" }
        if b.count >= 4, b[0] == 0x47, b[1] == 0x49, b[2] == 0x46 { return "gif" }
        if b.count >= 12, b[0] == 0x52, b[1] == 0x49, b[2] == 0x46, b[3] == 0x46, b[8] == 0x57, b[9] == 0x45 { return "webp" }
        return "img"
    }

    /// Допустимое имя файла хранилища: `<64 hex>.<ext>`. Используется при импорте архивов (защита от подмены путей).
    static func isValidFileName(_ s: String) -> Bool {
        s.range(of: #"^[0-9a-f]{64}\.[a-z0-9]{2,5}$"#, options: .regularExpression) != nil
    }

    // MARK: - Запись и чтение

    @discardableResult
    func save(data: Data) throws -> String {
        guard !data.isEmpty, Self.pixelSize(of: data) != nil else { throw AppError.imageDecodeFailed }
        let name = Self.fileName(for: data)
        let url = imagesDir.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) { return name }
        do {
            try data.write(to: url, options: .atomic) // защита от частично записанных файлов
        } catch {
            throw Self.map(error)
        }
        return name
    }

    /// Сохраняет UIImage: PNG (если есть прозрачность) или JPEG.
    @discardableResult
    func save(image: UIImage) throws -> String {
        let data = Self.hasAlpha(image) ? image.pngData() : image.jpegData(compressionQuality: 0.95)
        guard let d = data else { throw AppError.imageDecodeFailed }
        return try save(data: d)
    }

    static func hasAlpha(_ image: UIImage) -> Bool {
        guard let a = image.cgImage?.alphaInfo else { return false }
        return a != .none && a != .noneSkipFirst && a != .noneSkipLast
    }

    func url(for fileName: String) -> URL { imagesDir.appendingPathComponent(fileName) }

    func exists(_ fileName: String) -> Bool { FileManager.default.fileExists(atPath: url(for: fileName).path) }

    func loadData(_ fileName: String) throws -> Data {
        do { return try Data(contentsOf: url(for: fileName), options: .mappedIfSafe) }
        catch { throw AppError.missingImage(fileName) }
    }

    func remove(_ fileName: String) {
        try? FileManager.default.removeItem(at: url(for: fileName))
        let base = (fileName as NSString).deletingPathExtension
        for ext in ["png", "jpg"] {
            try? FileManager.default.removeItem(at: thumbsDir.appendingPathComponent(base + "." + ext))
        }
    }

    func allFileNames() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: imagesDir.path)) ?? []
    }

    /// Удаляет файлы, на которые нет ссылок. Файлы младше `grace` секунд не трогаются
    /// (они могли быть только что записаны, но ещё не привязаны к записи БД).
    @discardableResult
    func collectGarbage(referenced: Set<String>, grace: TimeInterval = 600) -> Int {
        var removed = 0
        for name in allFileNames() where !referenced.contains(name) {
            let url = self.url(for: name)
            if grace > 0,
               let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let touched = (attrs[.modificationDate] as? Date) ?? (attrs[.creationDate] as? Date),
               Date().timeIntervalSince(touched) < grace { continue }
            remove(name)
            removed += 1
        }
        return removed
    }

    // MARK: - Миниатюры и показ

    func displayImage(fileName: String, maxPixel: Int) -> UIImage? {
        maxPixel <= Self.thumbPixel ? thumbnail(fileName: fileName) : downsampledImage(fileName: fileName, maxPixel: maxPixel)
    }

    /// Миниатюра с дисковым кешем. Альфа-канал сохраняется (PNG), непрозрачные — JPEG.
    func thumbnail(fileName: String) -> UIImage? {
        let base = (fileName as NSString).deletingPathExtension
        for ext in ["png", "jpg"] {
            let t = thumbsDir.appendingPathComponent(base + "." + ext)
            if FileManager.default.fileExists(atPath: t.path),
               let img = Self.downsample(url: t, maxPixel: Self.thumbPixel) { return img }
        }
        guard let img = Self.downsample(url: url(for: fileName), maxPixel: Self.thumbPixel) else { return nil }
        let alpha = Self.hasAlpha(img)
        let data = alpha ? img.pngData() : img.jpegData(compressionQuality: 0.82)
        try? data?.write(to: thumbsDir.appendingPathComponent(base + (alpha ? ".png" : ".jpg")), options: .atomic)
        return img
    }

    func downsampledImage(fileName: String, maxPixel: Int) -> UIImage? {
        Self.downsample(url: url(for: fileName), maxPixel: maxPixel)
    }

    func pixelSize(fileName: String) -> CGSize? {
        guard let src = CGImageSourceCreateWithURL(url(for: fileName) as CFURL, nil) else { return nil }
        return Self.pixelSize(source: src)
    }

    static func pixelSize(of data: Data) -> CGSize? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return pixelSize(source: src)
    }

    private static func pixelSize(source: CGImageSource) -> CGSize? {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? CGFloat,
              let h = props[kCGImagePropertyPixelHeight] as? CGFloat, w > 0, h > 0 else { return nil }
        let orientation = (props[kCGImagePropertyOrientation] as? Int) ?? 1
        return orientation >= 5 ? CGSize(width: h, height: w) : CGSize(width: w, height: h)
    }

    /// Декодирование с уменьшением через ImageIO: полноразмерный оригинал в память не загружается.
    static func downsample(url: URL, maxPixel: Int) -> UIImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let size = pixelSize(source: src) else { return nil }
        let target = max(16, min(maxPixel, Int(max(size.width, size.height))))
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: target
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }

    static func map(_ error: Error) -> AppError {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain && ns.code == NSFileWriteOutOfSpaceError { return .diskFull }
        if ns.domain == NSPOSIXErrorDomain && ns.code == Int(ENOSPC) { return .diskFull }
        return .fileWriteFailed(error.localizedDescription)
    }
}
