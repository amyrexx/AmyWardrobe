import Foundation

struct WardrobeCriteria: Equatable {
    var search = ""
    var categoryID: String? = nil
    var colorFamilyID: String? = nil
    var seasons: Set<Season> = []
    var favoritesOnly = false
    var tag: String? = nil

    var isActive: Bool {
        !search.isEmpty || categoryID != nil || colorFamilyID != nil || !seasons.isEmpty || favoritesOnly || tag != nil
    }
    /// Количество активных фильтров (без поиска) — для бейджа на кнопке.
    var activeFilterCount: Int {
        (categoryID != nil ? 1 : 0) + (colorFamilyID != nil ? 1 : 0) + (seasons.isEmpty ? 0 : 1) + (favoritesOnly ? 1 : 0) + (tag != nil ? 1 : 0)
    }
}

enum WardrobeSort: String, CaseIterable, Identifiable {
    case newest, oldest, name, mostWorn, leastWorn, recentlyEdited
    var id: String { rawValue }
    var title: String {
        switch self {
        case .newest: return "Сначала новые"
        case .oldest: return "Сначала старые"
        case .name: return "По названию"
        case .mostWorn: return "Чаще носимые"
        case .leastWorn: return "Реже носимые"
        case .recentlyEdited: return "Недавно изменённые"
        }
    }
}

/// Чистые функции фильтрации/сортировки — легко тестируются.
enum WardrobeFilter {
    static func apply(_ items: [WardrobeItem], criteria: WardrobeCriteria, sort: WardrobeSort) -> [WardrobeItem] {
        let q = criteria.search.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = items.filter { item in
            if criteria.favoritesOnly && !item.isFavorite { return false }
            if let c = criteria.categoryID, item.categoryID != c { return false }
            if let f = criteria.colorFamilyID, ColorPalette.nearest(to: item.primaryColorHex).id != f { return false }
            if !criteria.seasons.isEmpty, item.seasons.isDisjoint(with: criteria.seasons) { return false }
            if let t = criteria.tag, !item.tags.contains(t) { return false }
            if !q.isEmpty {
                let haystack = [item.name, item.subcategory, item.material, item.details, item.notes, item.tags.joined(separator: " ")]
                if !haystack.contains(where: { $0.localizedCaseInsensitiveContains(q) }) { return false }
            }
            return true
        }
        switch sort {
        case .newest: return filtered.sorted { $0.createdAt > $1.createdAt }
        case .oldest: return filtered.sorted { $0.createdAt < $1.createdAt }
        case .name: return filtered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .mostWorn: return filtered.sorted { $0.wearCount > $1.wearCount }
        case .leastWorn: return filtered.sorted { $0.wearCount < $1.wearCount }
        case .recentlyEdited: return filtered.sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    static func allTags(_ items: [WardrobeItem]) -> [String] {
        Array(Set(items.flatMap(\.tags))).sorted()
    }
}
