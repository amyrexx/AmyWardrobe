import Foundation
import SwiftUI

/// Реальные мерки пользователя (необязательны). Не используются как «точная модель тела».
struct BodyMeasurements: Codable, Equatable {
    var heightCm: Double? = 168
    var weightKg: Double? = nil
    var bustCm: Double? = nil
    var waistCm: Double? = nil
    var hipsCm: Double? = nil
    var inseamCm: Double? = nil
    var torsoLengthCm: Double? = nil
    var shoulderWidthCm: Double? = nil
}

/// Визуальные параметры 2D-аватара — отдельно от реальных мерок, настраиваются вручную.
struct AvatarVisual: Codable, Equatable {
    var shoulder: Double = 1
    var bust: Double = 1
    var waist: Double = 1
    var hip: Double = 1
    var torso: Double = 1
    var leg: Double = 1
    var hairHex: String = "#5B4378"
    var skinHex: String = "#F3D5C4"
    var eyeHex: String = "#8F6BD6"

    /// Подсказка визуальных пропорций по меркам. Вес намеренно НЕ используется: по росту и весу фигуру восстановить нельзя.
    static func suggested(from m: BodyMeasurements) -> AvatarVisual {
        func ratio(_ value: Double?, _ reference: Double) -> Double {
            guard let v = value, v > 0 else { return 1 }
            return min(1.15, max(0.85, 1 + (v / reference - 1) * 0.8))
        }
        var a = AvatarVisual()
        a.shoulder = ratio(m.shoulderWidthCm, 38)
        a.bust = ratio(m.bustCm, 90)
        a.waist = ratio(m.waistCm, 70)
        a.hip = ratio(m.hipsCm, 96)
        a.torso = min(1.1, max(0.9, ratio(m.torsoLengthCm, 60)))
        a.leg = min(1.1, max(0.9, ratio(m.inseamCm, 78)))
        return a
    }
}

struct SettingsData: Codable, Equatable {
    var userName: String = ""
    var measurements = BodyMeasurements()
    var avatar = AvatarVisual()
    var useInches = false
    var useLbs = false
    var exportAsJPEG = false
    var customCategories: [CustomCategory] = []
    var customSubcategories: [String: [String]] = [:]
    var customMaterials: [String] = []
    var tryOnEndpoint: String = ""
    var tryOnEnabled = false
    var lastBackupAt: Date? = nil
}

/// Настройки приложения: хранятся локально в UserDefaults в виде JSON, переносятся в резервную копию.
@MainActor
final class AppSettings: ObservableObject {
    @Published var data: SettingsData {
        didSet { if data != oldValue { persist() } }
    }
    private let defaults: UserDefaults
    private let key = "amywardrobe.settings.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.data(forKey: key), let decoded = try? JSONDecoder().decode(SettingsData.self, from: raw) {
            data = decoded
        } else {
            data = SettingsData()
        }
    }

    private func persist() {
        if let raw = try? JSONEncoder().encode(data) { defaults.set(raw, forKey: key) }
    }

    // MARK: Категории (расширяемые)

    var allCategories: [ItemCategory] {
        Taxonomy.builtIn + data.customCategories.map {
            ItemCategory(id: $0.id, title: $0.title, icon: "tag", subcategories: [], isCustom: true)
        }
    }

    func category(_ id: String) -> ItemCategory? { allCategories.first { $0.id == id } }

    func categoryTitle(_ id: String) -> String { category(id)?.title ?? "Прочее" }

    func subcategories(for categoryID: String) -> [String] {
        let builtIn = category(categoryID)?.subcategories ?? []
        return builtIn + (data.customSubcategories[categoryID] ?? []).filter { !builtIn.contains($0) }
    }

    func addSubcategory(_ name: String, to categoryID: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, !subcategories(for: categoryID).contains(n) else { return }
        data.customSubcategories[categoryID, default: []].append(n)
    }

    @discardableResult
    func addCategory(title: String) -> String? {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !allCategories.contains(where: { $0.title.lowercased() == t.lowercased() }) else { return nil }
        let id = "custom." + UUID().uuidString.prefix(8).lowercased()
        data.customCategories.append(CustomCategory(id: id, title: t))
        return id
    }

    var materials: [String] {
        MaterialCatalog.common + data.customMaterials.filter { !MaterialCatalog.common.contains($0) }
    }

    func addMaterial(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, !materials.contains(n) else { return }
        data.customMaterials.append(n)
    }
}
