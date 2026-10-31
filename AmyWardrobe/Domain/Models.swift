import Foundation
import SwiftData

/// Вещь гардероба. Изображение хранится в `ImageStore`, здесь — только имя файла (устойчивая ссылка).
@Model
final class WardrobeItem {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    var categoryID: String = "tops"
    var subcategory: String = ""
    var imageFile: String = ""
    var extraImageFiles: [String] = []
    var primaryColorHex: String = "#FFFFFF"
    var secondaryColorHexes: [String] = []
    var sizeSystem: String = SizeSystem.letter.rawValue
    var sizeValue: String = ""
    var material: String = ""
    var details: String = ""
    var seasonRaws: [String] = []
    var tags: [String] = []
    var isFavorite: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var notes: String = ""
    var wearCount: Int = 0
    var lastWornAt: Date? = nil

    init(name: String, categoryID: String, imageFile: String) {
        self.name = name
        self.categoryID = categoryID
        self.imageFile = imageFile
    }

    var seasons: Set<Season> {
        get { Set(seasonRaws.compactMap(Season.init(rawValue:))) }
        set { seasonRaws = Season.allCases.filter { newValue.contains($0) }.map(\.rawValue) }
    }
}

enum FolderKind: String, Codable {
    case collage, outfit
}

@Model
final class Folder {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    var kindRaw: String = FolderKind.collage.rawValue
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(name: String, kind: FolderKind) {
        self.name = name
        self.kindRaw = kind.rawValue
    }

    var kind: FolderKind { FolderKind(rawValue: kindRaw) ?? .collage }
}

/// Коллаж — редактируемый проект. Структура лежит в `documentData` (JSON `CollageDocument`).
@Model
final class CollageProject {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    var documentData: Data = Data()
    var tags: [String] = []
    var isFavorite: Bool = false
    var folderID: UUID? = nil
    var previewFile: String? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(name: String, document: CollageDocument) {
        self.name = name
        self.documentData = (try? JSONEncoder().encode(document)) ?? Data()
    }

    var document: CollageDocument {
        get { (try? JSONDecoder().decode(CollageDocument.self, from: documentData)) ?? CollageDocument() }
        set { documentData = (try? JSONEncoder().encode(newValue)) ?? documentData }
    }
}

/// Запись внутри образа: ссылка на вещь + «снимок» (имя/картинка), чтобы образ пережил удаление вещи.
struct OutfitEntry: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var itemID: UUID?
    var name: String
    var categoryID: String
    var subcategory: String
    var imageFile: String
}

enum OutfitOrigin: String, Codable {
    case items, collage, tryOn
    var title: String {
        switch self {
        case .items: return "Из вещей"
        case .collage: return "Из коллажа"
        case .tryOn: return "Из примерки"
        }
    }
}

@Model
final class Outfit {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    var details: String = ""
    var entriesData: Data = Data()
    var tags: [String] = []
    var isFavorite: Bool = false
    var folderID: UUID? = nil
    var previewFile: String? = nil
    var tryOnFile: String? = nil
    var sourceCollageID: UUID? = nil
    var originRaw: String = OutfitOrigin.items.rawValue
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(name: String, entries: [OutfitEntry], origin: OutfitOrigin) {
        self.name = name
        self.originRaw = origin.rawValue
        self.entriesData = (try? JSONEncoder().encode(entries)) ?? Data()
    }

    var entries: [OutfitEntry] {
        get { (try? JSONDecoder().decode([OutfitEntry].self, from: entriesData)) ?? [] }
        set { entriesData = (try? JSONEncoder().encode(newValue)) ?? entriesData; updatedAt = Date() }
    }

    var origin: OutfitOrigin { OutfitOrigin(rawValue: originRaw) ?? .items }
}

/// История результатов примерки.
@Model
final class TryOnRecord {
    @Attribute(.unique) var id: UUID = UUID()
    var createdAt: Date = Date()
    var imageFile: String = ""
    var modeRaw: String = "compose"
    var outfitID: UUID? = nil
    var note: String = ""

    init(imageFile: String, modeRaw: String, outfitID: UUID?) {
        self.imageFile = imageFile
        self.modeRaw = modeRaw
        self.outfitID = outfitID
    }
}

// MARK: - Схема и миграции

enum AmySchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [WardrobeItem.self, Folder.self, CollageProject.self, Outfit.self, TryOnRecord.self]
    }
}

/// Все поля имеют значения по умолчанию, поэтому добавление новых полей в будущих версиях
/// выполняется лёгкой (lightweight) миграцией. Новые этапы добавляются сюда.
enum AmyMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [AmySchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

enum PersistenceController {
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: AmySchemaV1.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, migrationPlan: AmyMigrationPlan.self, configurations: config)
    }
}
