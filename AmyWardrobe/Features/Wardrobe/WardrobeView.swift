import SwiftUI
import SwiftData

struct ItemCard: View {
    let item: WardrobeItem
    var selected: Bool? = nil
    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                StoreImage(fileName: item.imageFile)
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .background(AW.card, in: RoundedRectangle(cornerRadius: AW.corner, style: .continuous))
                    .shadow(color: AW.primaryDark.opacity(0.07), radius: 8, y: 3)
                if let selected {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.title3).foregroundStyle(selected ? AW.primaryDark : AW.textSecondary).padding(8)
                } else if item.isFavorite {
                    FavoriteBadge(isFavorite: true).padding(6)
                }
            }
            Text(item.name).font(.system(.footnote, design: .rounded).weight(.medium))
                .foregroundStyle(AW.textPrimary).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.name)
    }
}

struct WardrobeView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var settings: AppSettings
    @Query(sort: \WardrobeItem.createdAt, order: .reverse) private var items: [WardrobeItem]

    @State private var criteria = WardrobeCriteria()
    @State private var sort: WardrobeSort = .newest
    @State private var showFilters = false
    @State private var showAdd = false
    @State private var selecting = false
    @State private var selection = Set<UUID>()
    @State private var confirmDelete = false
    @State private var alert: AppAlert?
    @State private var tagAlert = false
    @State private var tagInput = ""
    @State private var showNewOutfit = false

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 14)]

    private var visible: [WardrobeItem] { WardrobeFilter.apply(items, criteria: criteria, sort: sort) }
    private var selectedItems: [WardrobeItem] { items.filter { selection.contains($0.id) } }

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ScrollView { EmptyStateView(icon: "hanger", title: "Гардероб пуст",
                                                message: "Добавьте первую вещь — фото без фона отлично подойдёт для коллажей.",
                                                actionTitle: "Добавить вещь") { showAdd = true } }
                } else if visible.isEmpty {
                    ScrollView { EmptyStateView(icon: "magnifyingglass", title: "Ничего не найдено",
                                                message: "Измените запрос или сбросьте фильтры.",
                                                actionTitle: "Сбросить фильтры") { criteria = WardrobeCriteria() } }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(visible) { item in cell(item) }
                        }
                        .padding(AW.spacing)
                        if selecting { Color.clear.frame(height: 70) }
                    }
                }
            }
            .awScreen()
            .navigationTitle("Гардероб")
            .searchable(text: $criteria.search, prompt: "Поиск по вещам")
            .toolbar { toolbarContent }
            .safeAreaInset(edge: .bottom) { if selecting { selectionBar } }
            .sheet(isPresented: $showAdd) { ItemEditorView(mode: .new) }
            .sheet(isPresented: $showFilters) { WardrobeFilterSheet(criteria: $criteria, sort: $sort, tags: WardrobeFilter.allTags(items)) }
            .sheet(isPresented: $showNewOutfit) {
                NewOutfitSheet(preselected: selectedItems) { selecting = false; selection = [] }
            }
            .confirmationDialog("Удалить выбранные вещи (\(selection.count))?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Удалить", role: .destructive) { deleteSelected() }
                Button("Отмена", role: .cancel) {}
            } message: { Text("Образы и коллажи, где они использованы, сохранят изображения.") }
            .alert("Добавить тег", isPresented: $tagAlert) {
                TextField("Тег", text: $tagInput)
                Button("Добавить") { addTagToSelection() }
                Button("Отмена", role: .cancel) {}
            }
            .appAlert($alert)
        }
    }

    @ViewBuilder
    private func cell(_ item: WardrobeItem) -> some View {
        if selecting {
            Button {
                if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
            } label: { ItemCard(item: item, selected: selection.contains(item.id)) }
            .buttonStyle(.plain)
        } else {
            NavigationLink { ItemDetailView(item: item) } label: { ItemCard(item: item) }.buttonStyle(.plain)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if !items.isEmpty {
                Button(selecting ? "Готово" : "Выбрать") { selecting.toggle(); selection = [] }
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if !items.isEmpty {
                Button { showFilters = true } label: {
                    Image(systemName: criteria.activeFilterCount > 0 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }.accessibilityLabel("Фильтры и сортировка")
            }
            Button { showAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("Добавить вещь")
        }
    }

    private var selectionBar: some View {
        HStack(spacing: 10) {
            Text("Выбрано: \(selection.count)").font(AW.caption).foregroundStyle(AW.textSecondary)
            Spacer()
            Button { toggleFavorite() } label: { Image(systemName: "heart") }
            Button { tagInput = ""; tagAlert = true } label: { Image(systemName: "tag") }
            Button { showNewOutfit = true } label: { Image(systemName: "rectangle.stack.badge.plus") }
            Button(role: .destructive) { confirmDelete = true } label: { Image(systemName: "trash") }
        }
        .disabled(selection.isEmpty)
        .font(.title3).foregroundStyle(AW.primaryDark)
        .padding(14).background(.ultraThinMaterial)
    }

    private func toggleFavorite() {
        let sel = selectedItems
        let makeFav = sel.contains { !$0.isFavorite }
        for i in sel { i.isFavorite = makeFav; i.updatedAt = Date() }
        do { try context.save() } catch { context.rollback(); alert = AppAlert(error: error) }
    }

    private func addTagToSelection() {
        let t = tagInput.trimmingCharacters(in: .whitespaces).lowercased()
        guard !t.isEmpty else { return }
        for i in selectedItems where !i.tags.contains(t) { i.tags.append(t); i.updatedAt = Date() }
        do { try context.save() } catch { context.rollback(); alert = AppAlert(error: error) }
    }

    private func deleteSelected() {
        do {
            try WardrobeService.delete(selectedItems, context: context)
            selection = []; selecting = false
        } catch { alert = AppAlert(error: error, title: "Не удалось удалить") }
    }
}

struct WardrobeFilterSheet: View {
    @Binding var criteria: WardrobeCriteria
    @Binding var sort: WardrobeSort
    let tags: [String]
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Сортировка") {
                    Picker("Порядок", selection: $sort) { ForEach(WardrobeSort.allCases) { Text($0.title).tag($0) } }
                }
                Section("Категория") {
                    Picker("Категория", selection: $criteria.categoryID) {
                        Text("Все").tag(String?.none)
                        ForEach(settings.allCategories) { Text($0.title).tag(Optional($0.id)) }
                    }
                }
                Section("Цвет") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(ColorPalette.presets) { p in
                                Button { criteria.colorFamilyID = criteria.colorFamilyID == p.id ? nil : p.id } label: {
                                    Circle().fill(Color(hex: p.hex)).frame(width: 34, height: 34)
                                        .overlay(Circle().stroke(criteria.colorFamilyID == p.id ? AW.primaryDark : AW.divider,
                                                                 lineWidth: criteria.colorFamilyID == p.id ? 3 : 1))
                                }.accessibilityLabel(p.name)
                            }
                        }.padding(.vertical, 4)
                    }
                }
                Section("Сезон") {
                    FlowLayout {
                        ForEach(Season.allCases) { s in
                            Button {
                                if criteria.seasons.contains(s) { criteria.seasons.remove(s) } else { criteria.seasons.insert(s) }
                            } label: { AWChip(title: s.title, icon: s.icon, selected: criteria.seasons.contains(s)) }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if !tags.isEmpty {
                    Section("Тег") {
                        Picker("Тег", selection: $criteria.tag) {
                            Text("Любой").tag(String?.none)
                            ForEach(tags, id: \.self) { Text("#\($0)").tag(Optional($0)) }
                        }
                    }
                }
                Section { Toggle("Только избранное", isOn: $criteria.favoritesOnly).tint(AW.primaryDark) }
                Section { Button("Сбросить фильтры", role: .destructive) { criteria = WardrobeCriteria(search: criteria.search) } }
            }
            .navigationTitle("Фильтры")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
        .presentationDetents([.large])
    }
}

/// Универсальный выбор вещей (для коллажа, образа, замены вещи).
struct ItemPickerView: View {
    let title: String
    var multiple = true
    var excluding: Set<UUID> = []
    let onPick: ([WardrobeItem]) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings
    @Query(sort: \WardrobeItem.createdAt, order: .reverse) private var items: [WardrobeItem]
    @State private var criteria = WardrobeCriteria()
    @State private var selection: [UUID] = []

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 12)]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        Button { criteria.categoryID = nil } label: { AWChip(title: "Все", selected: criteria.categoryID == nil) }
                        ForEach(settings.allCategories) { c in
                            Button { criteria.categoryID = c.id } label: { AWChip(title: c.title, selected: criteria.categoryID == c.id) }
                        }
                    }.padding(.horizontal, 16).padding(.vertical, 8)
                }
                let list = WardrobeFilter.apply(items, criteria: criteria, sort: .newest).filter { !excluding.contains($0.id) }
                if list.isEmpty {
                    ScrollView { EmptyStateView(icon: "hanger", title: items.isEmpty ? "Гардероб пуст" : "Нет подходящих вещей",
                                                message: items.isEmpty ? "Сначала добавьте вещи во вкладке «Гардероб»." : "Попробуйте другую категорию или запрос.") }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(list) { item in
                                Button { tap(item) } label: {
                                    ItemCard(item: item, selected: multiple ? selection.contains(item.id) : nil)
                                }.buttonStyle(.plain)
                            }
                        }.padding(16)
                    }
                }
            }
            .awScreen()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $criteria.search, prompt: "Поиск")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                if multiple {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Добавить (\(selection.count))") { confirm() }.disabled(selection.isEmpty)
                    }
                }
            }
        }
    }

    private func tap(_ item: WardrobeItem) {
        if multiple {
            if let i = selection.firstIndex(of: item.id) { selection.remove(at: i) } else { selection.append(item.id) }
        } else {
            onPick([item]); dismiss()
        }
    }

    private func confirm() {
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        onPick(selection.compactMap { byID[$0] })
        dismiss()
    }
}
