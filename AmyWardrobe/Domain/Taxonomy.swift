import Foundation

/// Сезон. Вещь может иметь несколько сезонов одновременно.
enum Season: String, CaseIterable, Codable, Identifiable, Hashable {
    case spring, summer, autumn, winter
    var id: String { rawValue }
    var title: String {
        switch self {
        case .spring: return "Весна"
        case .summer: return "Лето"
        case .autumn: return "Осень"
        case .winter: return "Зима"
        }
    }
    var icon: String {
        switch self {
        case .spring: return "leaf"
        case .summer: return "sun.max"
        case .autumn: return "wind"
        case .winter: return "snowflake"
        }
    }
    /// Сезон по месяцу (северное полушарие).
    static func current(_ date: Date = Date(), calendar: Calendar = .current) -> Season {
        switch calendar.component(.month, from: date) {
        case 3, 4, 5: return .spring
        case 6, 7, 8: return .summer
        case 9, 10, 11: return .autumn
        default: return .winter
        }
    }
}

struct ItemCategory: Identifiable, Hashable {
    let id: String
    let title: String
    let icon: String
    let subcategories: [String]
    var isCustom = false
}

/// Встроенные категории. Список подкатегорий и сами категории можно дополнять (см. `AppSettings`).
enum Taxonomy {
    static let builtIn: [ItemCategory] = [
        ItemCategory(id: "outerwear", title: "Верхняя одежда", icon: "cloud.snow",
                     subcategories: ["Пальто", "Плащ и тренч", "Куртка", "Пуховик", "Жакет и пиджак", "Жилет", "Шуба и мех"]),
        ItemCategory(id: "tops", title: "Верх", icon: "tshirt",
                     subcategories: ["Футболка", "Топ", "Блузка", "Рубашка", "Свитер и джемпер", "Худи и свитшот", "Кардиган", "Водолазка", "Боди"]),
        ItemCategory(id: "bottoms", title: "Низ", icon: "figure.walk",
                     subcategories: ["Джинсы", "Брюки", "Юбка", "Шорты", "Леггинсы", "Спортивные штаны"]),
        ItemCategory(id: "dresses", title: "Платья и комбинезоны", icon: "sparkles",
                     subcategories: ["Платье мини", "Платье миди", "Платье макси", "Сарафан", "Комбинезон", "Костюм"]),
        ItemCategory(id: "shoes", title: "Обувь", icon: "shoeprints.fill",
                     subcategories: ["Кроссовки", "Кеды", "Ботинки", "Сапоги", "Туфли", "Балетки", "Босоножки", "Лоферы"]),
        ItemCategory(id: "bags", title: "Сумки", icon: "handbag",
                     subcategories: ["Через плечо", "Тоут", "Рюкзак", "Клатч", "Поясная сумка", "Шоппер"]),
        ItemCategory(id: "hats", title: "Головные уборы", icon: "crown",
                     subcategories: ["Шапка", "Кепка", "Шляпа", "Берет", "Панама", "Повязка"]),
        ItemCategory(id: "scarves", title: "Шарфы и платки", icon: "wind",
                     subcategories: ["Шарф", "Платок", "Палантин", "Снуд"]),
        ItemCategory(id: "jewelry", title: "Украшения", icon: "diamond",
                     subcategories: ["Серьги", "Колье и цепочки", "Браслет", "Кольцо", "Брошь", "Часы"]),
        ItemCategory(id: "accessories", title: "Аксессуары", icon: "eyeglasses",
                     subcategories: ["Ремень", "Перчатки", "Очки", "Зонт", "Заколки", "Колготки и носки"]),
        ItemCategory(id: "other", title: "Прочее", icon: "tag", subcategories: [])
    ]

    static func builtInCategory(_ id: String) -> ItemCategory? { builtIn.first { $0.id == id } }
}

struct CustomCategory: Codable, Hashable, Identifiable {
    var id: String
    var title: String
}

// MARK: - Размеры

enum SizeSystem: String, CaseIterable, Codable, Identifiable {
    case letter, eu, us, shoesEU, shoesUS, shoesUK, headCm, ring, oneSize, custom
    var id: String { rawValue }

    var title: String {
        switch self {
        case .letter: return "Буквенный (XS–XL)"
        case .eu: return "Европейский (EU)"
        case .us: return "США (US)"
        case .shoesEU: return "Обувь EU"
        case .shoesUS: return "Обувь US"
        case .shoesUK: return "Обувь UK"
        case .headCm: return "Обхват головы, см"
        case .ring: return "Размер кольца"
        case .oneSize: return "Единый размер"
        case .custom: return "Свой вариант"
        }
    }

    var values: [String] {
        func seq(_ from: Double, _ to: Double, _ step: Double) -> [String] {
            stride(from: from, through: to, by: step).map { v in
                v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
            }
        }
        switch self {
        case .letter: return ["XXS", "XS", "S", "M", "L", "XL", "XXL", "XXXL"]
        case .eu: return seq(32, 56, 2)
        case .us: return seq(0, 20, 2)
        case .shoesEU: return seq(34, 46, 0.5)
        case .shoesUS: return seq(4, 13, 0.5)
        case .shoesUK: return seq(2, 12, 0.5)
        case .headCm: return seq(52, 62, 1)
        case .ring: return seq(14, 22, 0.5)
        case .oneSize: return ["Единый"]
        case .custom: return []
        }
    }
}

enum SizeCatalog {
    /// Разные типы вещей используют разные размерные системы.
    static func systems(for categoryID: String) -> [SizeSystem] {
        switch categoryID {
        case "outerwear", "tops", "bottoms", "dresses": return [.letter, .eu, .us, .custom]
        case "shoes": return [.shoesEU, .shoesUS, .shoesUK, .custom]
        case "hats": return [.headCm, .letter, .oneSize, .custom]
        case "jewelry": return [.ring, .oneSize, .custom]
        default: return [.oneSize, .letter, .custom]
        }
    }
}

enum MaterialCatalog {
    static let common = ["Хлопок", "Лён", "Шёлк", "Шерсть", "Кашемир", "Вискоза", "Полиэстер", "Эластан",
                         "Деним", "Кожа", "Экокожа", "Замша", "Трикотаж", "Атлас", "Бархат", "Мех", "Металл", "Пластик"]
}
