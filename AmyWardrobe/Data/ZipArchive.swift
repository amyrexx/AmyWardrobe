import Foundation

/// Минимальная реализация ZIP (метод STORE, без сжатия, без ZIP64) для резервных копий.
/// Результат открывается любым архиватором, в т.ч. в приложении «Файлы». Лимит: архив < 4 ГиБ, < 65 535 файлов.
enum ZipError: Error, Equatable {
    case tooLarge
    case notAZip
    case corrupt(String)
    case unsupported(String)
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1) }
        return c
    }
    static func checksum(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            for b in buf { c = table[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        }
        return c ^ 0xFFFFFFFF
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ v: T) {
        var le = v.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }
}

final class ZipWriter {
    private struct Entry { let name: String; let crc: UInt32; let size: UInt32; let offset: UInt32 }
    private let handle: FileHandle
    private var entries: [Entry] = []
    private var offset: UInt64 = 0
    private var finished = false

    init(url: URL) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
    }

    func add(name: String, data: Data) throws {
        guard entries.count < 65_000, data.count < Int(UInt32.max), offset + UInt64(data.count) + 1024 < UInt64(UInt32.max) else { throw ZipError.tooLarge }
        let nameData = Data(name.utf8)
        let crc = CRC32.checksum(data)
        var h = Data()
        h.appendLE(UInt32(0x04034b50)); h.appendLE(UInt16(20)); h.appendLE(UInt16(0x0800)); h.appendLE(UInt16(0))
        h.appendLE(UInt16(0)); h.appendLE(UInt16(0x21))          // время 00:00:00, дата 1980-01-01
        h.appendLE(crc); h.appendLE(UInt32(data.count)); h.appendLE(UInt32(data.count))
        h.appendLE(UInt16(nameData.count)); h.appendLE(UInt16(0))
        h.append(nameData)
        let start = UInt32(offset)
        try handle.write(contentsOf: h)
        try handle.write(contentsOf: data)
        offset += UInt64(h.count) + UInt64(data.count)
        entries.append(Entry(name: name, crc: crc, size: UInt32(data.count), offset: start))
    }

    func finish() throws {
        guard !finished else { return }
        finished = true
        let cdStart = offset
        var cd = Data()
        for e in entries {
            let n = Data(e.name.utf8)
            cd.appendLE(UInt32(0x02014b50)); cd.appendLE(UInt16(20)); cd.appendLE(UInt16(20)); cd.appendLE(UInt16(0x0800)); cd.appendLE(UInt16(0))
            cd.appendLE(UInt16(0)); cd.appendLE(UInt16(0x21))
            cd.appendLE(e.crc); cd.appendLE(e.size); cd.appendLE(e.size)
            cd.appendLE(UInt16(n.count)); cd.appendLE(UInt16(0)); cd.appendLE(UInt16(0))
            cd.appendLE(UInt16(0)); cd.appendLE(UInt16(0)); cd.appendLE(UInt32(0)); cd.appendLE(e.offset)
            cd.append(n)
        }
        var end = Data()
        end.appendLE(UInt32(0x06054b50)); end.appendLE(UInt16(0)); end.appendLE(UInt16(0))
        end.appendLE(UInt16(entries.count)); end.appendLE(UInt16(entries.count))
        end.appendLE(UInt32(cd.count)); end.appendLE(UInt32(cdStart)); end.appendLE(UInt16(0))
        try handle.write(contentsOf: cd)
        try handle.write(contentsOf: end)
        try handle.synchronize()
        try handle.close()
    }
}

final class ZipReader {
    struct Entry { let name: String; let method: UInt16; let compressedSize: Int; let size: Int; let crc: UInt32; let localOffset: Int }
    private let data: Data
    private(set) var entries: [String: Entry] = [:]
    private(set) var orderedNames: [String] = []

    init(url: URL) throws {
        do { data = try Data(contentsOf: url, options: .alwaysMapped) } catch { throw ZipError.notAZip }
        try parse()
    }

    init(data: Data) throws {
        self.data = data
        try parse()
    }

    private func u16(_ o: Int) throws -> Int {
        guard o >= 0, o + 2 <= data.count else { throw ZipError.corrupt("выход за границы") }
        let i = data.startIndex + o
        return Int(data[i]) | (Int(data[i + 1]) << 8)
    }
    private func u32(_ o: Int) throws -> Int {
        guard o >= 0, o + 4 <= data.count else { throw ZipError.corrupt("выход за границы") }
        let i = data.startIndex + o
        return Int(data[i]) | (Int(data[i + 1]) << 8) | (Int(data[i + 2]) << 16) | (Int(data[i + 3]) << 24)
    }

    private func parse() throws {
        guard data.count >= 22 else { throw ZipError.notAZip }
        var eocd = -1
        var i = data.count - 22
        let lowest = max(0, data.count - 22 - 65_535)
        while i >= lowest {
            if try u32(i) == 0x06054b50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ZipError.notAZip }
        let total = try u16(eocd + 10)
        let cdSize = try u32(eocd + 12)
        let cdOffset = try u32(eocd + 16)
        guard cdOffset + cdSize <= data.count else { throw ZipError.corrupt("каталог архива выходит за границы файла") }
        var p = cdOffset
        for _ in 0..<total {
            guard try u32(p) == 0x02014b50 else { throw ZipError.corrupt("неверная запись каталога") }
            let method = UInt16(try u16(p + 10))
            let crc = UInt32(try u32(p + 16))
            let csize = try u32(p + 20)
            let size = try u32(p + 24)
            let nlen = try u16(p + 28), xlen = try u16(p + 30), clen = try u16(p + 32)
            let off = try u32(p + 42)
            guard p + 46 + nlen <= data.count else { throw ZipError.corrupt("имя файла выходит за границы") }
            let nameBytes = data.subdata(in: (data.startIndex + p + 46)..<(data.startIndex + p + 46 + nlen))
            guard let name = String(data: nameBytes, encoding: .utf8) else { throw ZipError.corrupt("имя не в UTF-8") }
            entries[name] = Entry(name: name, method: method, compressedSize: csize, size: size, crc: crc, localOffset: off)
            orderedNames.append(name)
            p += 46 + nlen + xlen + clen
        }
    }

    func has(_ name: String) -> Bool { entries[name] != nil }

    /// Читает файл и проверяет CRC32.
    func read(_ name: String) throws -> Data {
        guard let e = entries[name] else { throw ZipError.corrupt("нет файла \(name)") }
        guard e.method == 0 else { throw ZipError.unsupported("сжатие метода \(e.method)") }
        guard try u32(e.localOffset) == 0x04034b50 else { throw ZipError.corrupt("неверный заголовок \(name)") }
        let nlen = try u16(e.localOffset + 26), xlen = try u16(e.localOffset + 28)
        let start = e.localOffset + 30 + nlen + xlen
        guard e.size == e.compressedSize, start + e.size <= data.count else { throw ZipError.corrupt("данные \(name) обрезаны") }
        let out = data.subdata(in: (data.startIndex + start)..<(data.startIndex + start + e.size))
        guard CRC32.checksum(out) == e.crc else { throw ZipError.corrupt("контрольная сумма CRC не совпала: \(name)") }
        return out
    }
}
