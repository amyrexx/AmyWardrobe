import Foundation
import UIKit

enum CollageAspect: String, CaseIterable, Identifiable {
    case portrait45, square, story, portrait34, landscape
    var id: String { rawValue }
    var title: String {
        switch self {
        case .portrait45: return "4:5"
        case .square: return "1:1"
        case .story: return "9:16"
        case .portrait34: return "3:4"
        case .landscape: return "16:9"
        }
    }
    var size: CGSize {
        switch self {
        case .portrait45: return CGSize(width: 1080, height: 1350)
        case .square: return CGSize(width: 1080, height: 1080)
        case .story: return CGSize(width: 1080, height: 1920)
        case .portrait34: return CGSize(width: 1080, height: 1440)
        case .landscape: return CGSize(width: 1920, height: 1080)
        }
    }
}

enum CollageBackground: Codable, Equatable {
    case solid(hex: String)
    case gradient(topHex: String, bottomHex: String)
    case dots(baseHex: String, dotHex: String)

    static let pastelPresets: [String] = ["#F5F0FC", "#F4E5F0", "#FFFFFF", "#F3ECE0", "#E3DAF5", "#DDEBF5", "#E5F0E3", "#FBEFD9"]
}

enum CollageFont: String, Codable, CaseIterable, Identifiable {
    case system, rounded, serif, georgia, didot, script, avenir, marker
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "Системный"
        case .rounded: return "Округлый"
        case .serif: return "Serif"
        case .georgia: return "Georgia"
        case .didot: return "Didot"
        case .script: return "Рукописный"
        case .avenir: return "Avenir"
        case .marker: return "Маркер"
        }
    }
    func uiFont(size: CGFloat) -> UIFont {
        func design(_ d: UIFontDescriptor.SystemDesign) -> UIFont {
            let base = UIFont.systemFont(ofSize: size, weight: .semibold)
            if let desc = base.fontDescriptor.withDesign(d) { return UIFont(descriptor: desc, size: size) }
            return base
        }
        switch self {
        case .system: return UIFont.systemFont(ofSize: size, weight: .semibold)
        case .rounded: return design(.rounded)
        case .serif: return design(.serif)
        case .georgia: return UIFont(name: "Georgia", size: size) ?? UIFont.systemFont(ofSize: size)
        case .didot: return UIFont(name: "Didot", size: size) ?? UIFont.systemFont(ofSize: size)
        case .script: return UIFont(name: "SnellRoundhand-Bold", size: size) ?? UIFont.systemFont(ofSize: size)
        case .avenir: return UIFont(name: "AvenirNext-DemiBold", size: size) ?? UIFont.systemFont(ofSize: size)
        case .marker: return UIFont(name: "MarkerFelt-Wide", size: size) ?? UIFont.systemFont(ofSize: size)
        }
    }
}

enum CollageTextAlignment: String, Codable, CaseIterable, Identifiable {
    case left, center, right
    var id: String { rawValue }
    var ns: NSTextAlignment {
        switch self {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        }
    }
    var icon: String {
        switch self {
        case .left: return "text.alignleft"
        case .center: return "text.aligncenter"
        case .right: return "text.alignright"
        }
    }
}

struct TextStyle: Codable, Equatable {
    var content: String = "Мой образ"
    var font: CollageFont = .rounded
    var fontSize: Double = 72
    var colorHex: String = "#30283A"
    var alignment: CollageTextAlignment = .center
}

enum FrameLineStyle: String, Codable, CaseIterable, Identifiable {
    case solid, dashed, double, filled
    var id: String { rawValue }
    var title: String {
        switch self {
        case .solid: return "Линия"
        case .dashed: return "Пунктир"
        case .double: return "Двойная"
        case .filled: return "Заливка"
        }
    }
}

struct FrameStyle: Codable, Equatable {
    var colorHex: String = "#9B7AD8"
    var lineWidth: Double = 8
    var cornerRadius: Double = 40
    var style: FrameLineStyle = .solid
}

enum CollageObjectKind: String, Codable {
    case image, text, frame
}

/// Один объект коллажа. Координаты — в системе документа (не экрана); `width/height` — базовый размер,
/// итоговый = базовый × `scale`. Порядок слоёв определяется позицией в `CollageDocument.objects`.
struct CollageObject: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var kind: CollageObjectKind
    var itemID: UUID? = nil
    var imageFile: String? = nil
    var centerX: Double
    var centerY: Double
    var width: Double
    var height: Double
    var scale: Double = 1
    var rotation: Double = 0       // радианы, по часовой стрелке
    var flippedX: Bool = false
    var text: TextStyle? = nil
    var frame: FrameStyle? = nil

    static func image(file: String, itemID: UUID?, pixelSize: CGSize, at center: CGPoint, maxSide: Double) -> CollageObject {
        let (w, h) = fit(pixelSize, maxSide: maxSide)
        return CollageObject(kind: .image, itemID: itemID, imageFile: file,
                             centerX: center.x, centerY: center.y, width: w, height: h)
    }

    static func text(_ style: TextStyle = TextStyle(), at center: CGPoint, width: Double = 760) -> CollageObject {
        var o = CollageObject(kind: .text, centerX: center.x, centerY: center.y, width: width, height: 100, text: style)
        o.refitText()
        return o
    }

    static func frame(_ style: FrameStyle = FrameStyle(), at center: CGPoint, size: CGSize = CGSize(width: 520, height: 680)) -> CollageObject {
        CollageObject(kind: .frame, centerX: center.x, centerY: center.y, width: size.width, height: size.height, frame: style)
    }

    static func fit(_ size: CGSize, maxSide: Double) -> (Double, Double) {
        guard size.width > 0, size.height > 0 else { return (maxSide, maxSide) }
        let k = maxSide / Double(max(size.width, size.height))
        return (Double(size.width) * k, Double(size.height) * k)
    }

    /// Пересчитывает высоту текстового блока по содержимому и ширине.
    mutating func refitText() {
        guard let t = text else { return }
        height = Double(CollageRenderer.textHeight(t, width: CGFloat(width)))
    }
}

struct CollageDocument: Codable, Equatable {
    var version: Int = 1
    var canvasWidth: Double = 1080
    var canvasHeight: Double = 1350
    var background: CollageBackground = .solid(hex: "#F5F0FC")
    /// Снизу вверх: последний элемент — самый верхний слой.
    var objects: [CollageObject] = []

    static func blank(aspect: CollageAspect, backgroundHex: String = "#F5F0FC") -> CollageDocument {
        CollageDocument(canvasWidth: Double(aspect.size.width), canvasHeight: Double(aspect.size.height),
                        background: .solid(hex: backgroundHex))
    }

    var canvasCenter: CGPoint { CGPoint(x: canvasWidth / 2, y: canvasHeight / 2) }

    func index(of id: UUID) -> Int? { objects.firstIndex { $0.id == id } }
    func object(_ id: UUID) -> CollageObject? { objects.first { $0.id == id } }

    // MARK: Слои

    mutating func bringToFront(_ id: UUID) {
        guard let i = index(of: id) else { return }
        objects.append(objects.remove(at: i))
    }
    mutating func sendToBack(_ id: UUID) {
        guard let i = index(of: id) else { return }
        objects.insert(objects.remove(at: i), at: 0)
    }
    mutating func moveForward(_ id: UUID) {
        guard let i = index(of: id), i < objects.count - 1 else { return }
        objects.swapAt(i, i + 1)
    }
    mutating func moveBackward(_ id: UUID) {
        guard let i = index(of: id), i > 0 else { return }
        objects.swapAt(i, i - 1)
    }

    // MARK: Операции

    mutating func remove(_ id: UUID) { objects.removeAll { $0.id == id } }

    @discardableResult
    mutating func duplicate(_ id: UUID) -> UUID? {
        guard let i = index(of: id) else { return nil }
        var copy = objects[i]
        copy.id = UUID()
        copy.centerX += 40
        copy.centerY += 40
        objects.insert(copy, at: i + 1)
        return copy.id
    }

    mutating func centerOnCanvas(_ id: UUID) {
        guard let i = index(of: id) else { return }
        objects[i].centerX = canvasWidth / 2
        objects[i].centerY = canvasHeight / 2
    }

    /// Меняет размер полотна, пропорционально смещая и масштабируя объекты.
    mutating func resizeCanvas(to size: CGSize) {
        let fx = Double(size.width) / canvasWidth
        let fy = Double(size.height) / canvasHeight
        let fs = min(fx, fy)
        for i in objects.indices {
            objects[i].centerX *= fx
            objects[i].centerY *= fy
            objects[i].scale *= fs
        }
        canvasWidth = Double(size.width)
        canvasHeight = Double(size.height)
    }

    /// Все файлы изображений, на которые ссылается документ.
    var referencedFiles: Set<String> { Set(objects.compactMap(\.imageFile)) }

    static let minScale = 0.1
    static let maxScale = 8.0
}
