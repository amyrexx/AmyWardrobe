import Foundation
import UIKit

enum Occasion: String, CaseIterable, Identifiable {
    case everyday, office, evening, sport, date
    var id: String { rawValue }
    var title: String {
        switch self {
        case .everyday: return "Повседневно"
        case .office: return "Офис"
        case .evening: return "Вечер"
        case .sport: return "Спорт"
        case .date: return "Свидание"
        }
    }
    /// Теги, которые повышают оценку вещи для повода.
    var keywords: [String] {
        switch self {
        case .everyday: return ["повседневное", "прогулка", "casual"]
        case .office: return ["офис", "работа", "деловое"]
        case .evening: return ["вечер", "праздник", "нарядное"]
        case .sport: return ["спорт", "тренировка"]
        case .date: return ["свидание", "романтика", "вечер"]
        }
    }
}

/// Предложенный набор. Это локальные правила, а не генеративный ИИ.
struct OutfitSuggestion: Identifiable {
    let id = UUID()
    let items: [WardrobeItem]
    let score: Double
    let reasons: [String]
}

/// Детерминированный (по seed) подбор сочетаний на основе правил: цвет, сезон, повод, разнообразие.
enum StylistEngine {
    static func suggest(items: [WardrobeItem], occasion: Occasion, season: Season, count: Int = 3,
                        now: Date = Date(), seed: UInt64 = 1) -> [OutfitSuggestion] {
        func pool(_ cats: [String]) -> [WardrobeItem] {
            items.filter { cats.contains($0.categoryID) }
                .sorted { score($0, occasion, season, now) > score($1, occasion, season, now) }
                .prefix(6).map { $0 }
        }
        let tops = pool(["tops"]), bottoms = pool(["bottoms"]), dresses = pool(["dresses"])
        let shoes = pool(["shoes"]), outer = pool(["outerwear"]), bags = pool(["bags"])
        var bases: [[WardrobeItem]] = dresses.map { [$0] }
        for t in tops { for b in bottoms { bases.append([t, b]) } }
        guard !bases.isEmpty else { return [] }

        var rng = SplitMix64(seed: seed)
        var results: [OutfitSuggestion] = []
        for base in bases {
            var set = base
            var reasons: [String] = []
            if let s = shoes.randomElement(using: &rng) { set.append(s) }
            if (season == .autumn || season == .winter), let o = outer.randomElement(using: &rng) {
                set.append(o); reasons.append("верхняя одежда по сезону")
            }
            if let b = bags.randomElement(using: &rng) { set.append(b) }
            var total = set.map { score($0, occasion, season, now) }.reduce(0, +) / Double(set.count)
            let harmony = colorHarmony(set.map(\.primaryColorHex))
            total += harmony.score
            if let r = harmony.reason { reasons.append(r) }
            if set.contains(where: { $0.seasons.contains(season) }) { reasons.append("подходит сезону: \(season.title.lowercased())") }
            if set.contains(where: { $0.tags.contains { occasion.keywords.contains($0) } }) { reasons.append("подходит поводу: \(occasion.title.lowercased())") }
            if set.contains(where: { $0.lastWornAt == nil }) { reasons.append("включает вещь, которую давно не надевали") }
            results.append(OutfitSuggestion(items: set, score: total, reasons: reasons))
        }
        return Array(results.sorted { $0.score > $1.score }.prefix(count))
    }

    static func score(_ item: WardrobeItem, _ occasion: Occasion, _ season: Season, _ now: Date) -> Double {
        var s = 0.0
        if item.seasons.contains(season) { s += 2 } else if item.seasons.isEmpty { s += 0.5 }
        if item.tags.contains(where: { occasion.keywords.contains($0) }) { s += 2 }
        if item.isFavorite { s += 0.5 }
        // разнообразие: давно не надетое — выше
        if let last = item.lastWornAt {
            let days = now.timeIntervalSince(last) / 86_400
            s += min(1.5, days / 30)
        } else { s += 1.5 }
        return s
    }

    /// Цветовая гармония: нейтральные сочетаются со всем; аналогичные и комплементарные оттенки — хорошо.
    static func colorHarmony(_ hexes: [String]) -> (score: Double, reason: String?) {
        let chromatic = hexes.map { UIColor(hex: $0).hsb }.filter { $0.s > 0.2 && $0.b > 0.2 && $0.b < 0.97 }
        if chromatic.count <= 1 { return (1.5, "спокойная палитра с нейтральными цветами") }
        var best = 0.0
        var reason: String? = nil
        for i in 0..<chromatic.count {
            for j in (i + 1)..<chromatic.count {
                var d = abs(chromatic[i].h - chromatic[j].h) * 360
                if d > 180 { d = 360 - d }
                if d < 30 { best = max(best, 1.5); reason = "родственные оттенки" }
                else if d > 150 { best = max(best, 1.2); reason = "контрастная пара цветов" }
                else { best = max(best, -0.5) }
            }
        }
        return (best, reason)
    }
}

struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
