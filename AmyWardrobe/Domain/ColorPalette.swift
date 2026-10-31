import Foundation
import UIKit

struct ColorPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let hex: String
}

enum ColorPalette {
    static let presets: [ColorPreset] = [
        ColorPreset(id: "white", name: "Белый", hex: "#FFFFFF"),
        ColorPreset(id: "milk", name: "Молочный", hex: "#F3ECE0"),
        ColorPreset(id: "beige", name: "Бежевый", hex: "#D8C3A5"),
        ColorPreset(id: "brown", name: "Коричневый", hex: "#7B5A44"),
        ColorPreset(id: "black", name: "Чёрный", hex: "#1E1B22"),
        ColorPreset(id: "gray", name: "Серый", hex: "#9A97A0"),
        ColorPreset(id: "red", name: "Красный", hex: "#D64550"),
        ColorPreset(id: "pink", name: "Розовый", hex: "#F2A6C1"),
        ColorPreset(id: "orange", name: "Оранжевый", hex: "#F2994A"),
        ColorPreset(id: "yellow", name: "Жёлтый", hex: "#F4D35E"),
        ColorPreset(id: "green", name: "Зелёный", hex: "#6BAA75"),
        ColorPreset(id: "olive", name: "Оливковый", hex: "#7D8456"),
        ColorPreset(id: "blue", name: "Голубой", hex: "#8EC5E8"),
        ColorPreset(id: "navy", name: "Синий", hex: "#3F5FB5"),
        ColorPreset(id: "lilac", name: "Сиреневый", hex: "#C7B2EE"),
        ColorPreset(id: "purple", name: "Фиолетовый", hex: "#7553B8"),
        ColorPreset(id: "gold", name: "Золотой", hex: "#D4AF37"),
        ColorPreset(id: "silver", name: "Серебряный", hex: "#C0C0C8")
    ]

    static func preset(id: String) -> ColorPreset? { presets.first { $0.id == id } }

    /// Ближайший «цветовой тип» (для фильтрации по пользовательским цветам).
    static func nearest(to hex: String) -> ColorPreset {
        let c = rgb(hex)
        var best = presets[0]
        var bestD = Double.greatestFiniteMagnitude
        for p in presets {
            let q = rgb(p.hex)
            let d = 0.3 * pow(c.0 - q.0, 2) + 0.59 * pow(c.1 - q.1, 2) + 0.11 * pow(c.2 - q.2, 2)
            if d < bestD { bestD = d; best = p }
        }
        return best
    }

    static func name(for hex: String) -> String { nearest(to: hex).name }

    private static func rgb(_ hex: String) -> (Double, Double, Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(hex: hex).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r) * 255, Double(g) * 255, Double(b) * 255)
    }
}
