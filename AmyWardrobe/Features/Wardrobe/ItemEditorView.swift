import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

/// Черновик вещи: редактируется отдельно, применяется к модели только при сохранении.
struct ItemDraft {
    var name = ""
    var categoryID = "tops"
    var subcategory = ""
    var primaryColorHex = "#F3ECE0"
    var secondaryColors: [String] = []
    var sizeSystem = SizeSystem.letter.rawValue
    var sizeValue = ""
    var material = ""
    var details = ""
    var seasons: Set<Season> = []
    var tags: [String] = []
    var isFavorite = false
    var notes = ""

    init() {}

    init(item: WardrobeItem) {
        name = item.name; categoryID = item.categoryID; subcategory = item.subcategory
        primaryColorHex = item.primaryColorHex; secondaryColors = item.secondaryColorHexes
        sizeSystem = item.sizeSystem; sizeValue = item.sizeValue; material = item.material
        details = item.details; seasons = item.seasons; tags = item.tags
        isFavorite = item.isFavorite; notes = item.notes
    }

    func apply(to item: WardrobeItem) {
        item.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        item.categoryID = categoryID; item.subcategory = subcategory
        item.primaryColorHex = primaryColorHex; item.secondaryColorHexes = secondaryColors
        item.sizeSystem = sizeSystem; item.sizeValue = sizeValue; item.material = material
        item.details = details; item.seasons = seasons; item.tags = tags
        item.isFavorite = isFavorite; item.notes = notes
        item.updatedAt = Date()
    }
}

struct ItemEditorView: View {
    enum Mode { case new, edit(WardrobeItem) }
    let mode: Mode
    var onSaved: ((WardrobeItem) -> Void)? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings

    @State private var draft = ItemDraft()
    @State private var newImageData: Data?
    @State private var previewImage: UIImage?
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showFiles = false
    @State private var saving = false
    @State private var alert: AppAlert?
    @State private var newSubcategory = ""
    @State private var showNewSubcategory = false
    @State private var newCategory = ""
    @State private var showNewCategory = false
    @State private var newMaterial = ""
    @State private var showNewMaterial = false

    init(mode: Mode, onSaved: ((WardrobeItem) -> Void)? = nil) {
        self.mode = mode
        self.onSaved = onSaved
        // Черновик инициализируется сразу, чтобы onChange категории не сбросил подкатегорию/размер загруженной вещи.
        if case .edit(let item) = mode { _draft = State(initialValue: ItemDraft(item: item)) }
    }

    private var isNew: Bool { if case .new = mode { return true } else { return false } }
    private var existingItem: WardrobeItem? { if case .edit(let i) = mode { return i } else { return nil } }
    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespaces).isEmpty && (!isNew || newImageData != nil) && !saving
    }

    var body: some View {
        NavigationStack {
            Form {
                photoSection
                Section("Основное") {
                    TextField("Название", text: $draft.name)
                    Picker("Категория", selection: $draft.categoryID) {
                        ForEach(settings.allCategories) { Text($0.title).tag($0.id) }
                    }
                    .onChange(of: draft.categoryID) { _, new in
                        draft.subcategory = ""
                        draft.sizeSystem = (SizeCatalog.systems(for: new).first ?? .oneSize).rawValue
                        draft.sizeValue = ""
                    }
                    Picker("Подкатегория", selection: $draft.subcategory) {
                        Text("Не выбрана").tag("")
                        ForEach(settings.subcategories(for: draft.categoryID), id: \.self) { Text($0).tag($0) }
                    }
                    Button("Добавить свою подкатегорию…") { newSubcategory = ""; showNewSubcategory = true }
                    Button("Добавить свою категорию…") { newCategory = ""; showNewCategory = true }
                }
                colorSection
                sizeSection
                Section("Материал") {
                    Picker("Материал", selection: $draft.material) {
                        Text("Не указан").tag("")
                        ForEach(settings.materials, id: \.self) { Text($0).tag($0) }
                        if !draft.material.isEmpty && !settings.materials.contains(draft.material) {
                            Text(draft.material).tag(draft.material)
                        }
                    }
                    Button("Свой материал…") { newMaterial = ""; showNewMaterial = true }
                }
                Section("Сезоны") {
                    FlowLayout {
                        ForEach(Season.allCases) { s in
                            Button {
                                if draft.seasons.contains(s) { draft.seasons.remove(s) } else { draft.seasons.insert(s) }
                            } label: { AWChip(title: s.title, icon: s.icon, selected: draft.seasons.contains(s)) }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Section("Теги") { TagEditor(tags: $draft.tags, suggestions: ["офис", "прогулка", "вечер", "спорт", "свидание", "путешествие"]) }
                Section("Описание и заметки") {
                    TextField("Описание", text: $draft.details, axis: .vertical).lineLimit(1...4)
                    TextField("Заметки", text: $draft.notes, axis: .vertical).lineLimit(1...4)
                }
                Section { Toggle("Избранное", isOn: $draft.isFavorite).tint(AW.primaryDark) }
            }
            .scrollContentBackground(.hidden)
            .awScreen()
            .navigationTitle(isNew ? "Новая вещь" : "Редактирование")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() } else { Button("Сохранить", action: save).disabled(!canSave) }
                }
            }
            .onChange(of: photoItem) { _, item in loadPhoto(item) }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { img in setImage(data: img.pngData()) }.ignoresSafeArea()
            }
            .fileImporter(isPresented: $showFiles, allowedContentTypes: [.image]) { result in importFile(result) }
            .alert("Новая подкатегория", isPresented: $showNewSubcategory) {
                TextField("Название", text: $newSubcategory)
                Button("Добавить") { settings.addSubcategory(newSubcategory, to: draft.categoryID); draft.subcategory = newSubcategory.trimmingCharacters(in: .whitespacesAndNewlines) }
                Button("Отмена", role: .cancel) {}
            }
            .alert("Новая категория", isPresented: $showNewCategory) {
                TextField("Название", text: $newCategory)
                Button("Добавить") { if let id = settings.addCategory(title: newCategory) { draft.categoryID = id } }
                Button("Отмена", role: .cancel) {}
            }
            .alert("Свой материал", isPresented: $showNewMaterial) {
                TextField("Например, букле", text: $newMaterial)
                Button("Добавить") { settings.addMaterial(newMaterial); draft.material = newMaterial.trimmingCharacters(in: .whitespacesAndNewlines) }
                Button("Отмена", role: .cancel) {}
            }
            .appAlert($alert)
        }
    }

    // MARK: Секции

    private var photoSection: some View {
        Section("Фото (без фона, PNG с прозрачностью)") {
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(AW.pink.opacity(0.5))
                if let previewImage {
                    Image(uiImage: previewImage).resizable().scaledToFit().padding(8)
                } else if let existing = existingItem {
                    StoreImage(fileName: existing.imageFile, maxPixel: 800).padding(8)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "photo.badge.plus").font(.largeTitle).foregroundStyle(AW.primaryDark)
                        Text("Добавьте изображение вещи").font(AW.caption).foregroundStyle(AW.textSecondary)
                    }
                }
            }
            .frame(height: 220)
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))

            PhotosPicker(selection: $photoItem, matching: .images) { Label("Из галереи", systemImage: "photo.on.rectangle") }
            Button { openCamera() } label: { Label("Снять на камеру", systemImage: "camera") }
            Button { showFiles = true } label: { Label("Из «Файлов»", systemImage: "folder") }
            Button { pasteFromClipboard() } label: { Label("Вставить из буфера", systemImage: "doc.on.clipboard") }
        }
    }

    private var colorSection: some View {
        Section("Цвет") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(ColorPalette.presets) { p in
                        Button { draft.primaryColorHex = p.hex } label: {
                            Circle().fill(Color(hex: p.hex)).frame(width: 34, height: 34)
                                .overlay(Circle().stroke(draft.primaryColorHex.uppercased() == p.hex.uppercased() ? AW.primaryDark : AW.divider,
                                                         lineWidth: draft.primaryColorHex.uppercased() == p.hex.uppercased() ? 3 : 1))
                        }
                        .accessibilityLabel(p.name)
                    }
                }.padding(.vertical, 4)
            }
            ColorPicker("Свой цвет", selection: Binding(get: { Color(hex: draft.primaryColorHex) }, set: { draft.primaryColorHex = $0.hexString }), supportsOpacity: false)
            Text("Определён как: \(ColorPalette.name(for: draft.primaryColorHex))").font(AW.caption).foregroundStyle(AW.textSecondary)
            ForEach(Array(draft.secondaryColors.enumerated()), id: \.offset) { idx, hex in
                HStack {
                    ColorPicker("Доп. цвет \(idx + 1)", selection: Binding(get: { Color(hex: hex) }, set: { draft.secondaryColors[idx] = $0.hexString }), supportsOpacity: false)
                    Button(role: .destructive) { draft.secondaryColors.remove(at: idx) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                }
            }
            if draft.secondaryColors.count < 3 {
                Button("Добавить дополнительный цвет") { draft.secondaryColors.append("#C7B2EE") }
            }
        }
    }

    private var sizeSection: some View {
        let systems = SizeCatalog.systems(for: draft.categoryID)
        let system = SizeSystem(rawValue: draft.sizeSystem) ?? systems.first ?? .oneSize
        return Section("Размер") {
            Picker("Система", selection: $draft.sizeSystem) {
                ForEach(systems) { Text($0.title).tag($0.rawValue) }
            }
            .onChange(of: draft.sizeSystem) { _, _ in draft.sizeValue = "" }
            if system == .custom {
                TextField("Размер", text: $draft.sizeValue)
            } else {
                Picker("Размер", selection: $draft.sizeValue) {
                    Text("Не указан").tag("")
                    ForEach(system.values, id: \.self) { Text($0).tag($0) }
                }
            }
        }
    }

    // MARK: Логика

    private func openCamera() {
        guard CameraAccess.isCameraAvailable else {
            alert = AppAlert(title: "Камера недоступна", message: "На этом устройстве камера недоступна (например, в симуляторе). Выберите фото из галереи или «Файлов».")
            return
        }
        Task {
            if await CameraAccess.ensureAuthorized() { showCamera = true } else {
                alert = AppAlert(title: "Нет доступа к камере", message: "Разрешите доступ в Настройки → AmyWardrobe → Камера.")
            }
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { throw AppError.imageDecodeFailed }
                setImage(data: data)
            } catch { alert = AppAlert(error: error, title: "Не удалось загрузить фото") }
            photoItem = nil
        }
    }

    private func importFile(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            setImage(data: data)
        } catch {
            alert = AppAlert(error: AppError.fileReadFailed(error.localizedDescription), title: "Не удалось открыть файл")
        }
    }

    private func pasteFromClipboard() {
        guard let img = UIPasteboard.general.image, let data = img.pngData() else {
            alert = AppAlert(title: "Буфер обмена пуст", message: "Скопируйте изображение (например, из «Фото» или Safari) и повторите.")
            return
        }
        setImage(data: data)
    }

    private func setImage(data: Data?) {
        guard let data, ImageStore.pixelSize(of: data) != nil, let img = UIImage(data: data) else {
            alert = AppAlert(error: AppError.imageDecodeFailed, title: "Не удалось загрузить фото")
            return
        }
        newImageData = data
        previewImage = img
    }

    private func save() {
        saving = true
        Task {
            defer { saving = false }
            do {
                switch mode {
                case .new:
                    guard let data = newImageData else { throw AppError.validation("Добавьте изображение вещи.") }
                    let d = draft
                    let item = try WardrobeService.addItem(name: d.name.trimmingCharacters(in: .whitespaces),
                                                           categoryID: d.categoryID, imageData: data, context: context) { d.apply(to: $0) }
                    onSaved?(item)
                case .edit(let item):
                    if let data = newImageData { item.imageFile = try ImageStore.shared.save(data: data) }
                    draft.apply(to: item)
                    do { try context.save() } catch { context.rollback(); throw error }
                    onSaved?(item)
                }
                dismiss()
            } catch {
                alert = AppAlert(error: error, title: "Не удалось сохранить вещь")
            }
        }
    }
}
