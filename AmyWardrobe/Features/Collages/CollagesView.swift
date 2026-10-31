import SwiftUI
import SwiftData

struct CollagesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CollageProject.updatedAt, order: .reverse) private var projects: [CollageProject]
    @Query(sort: \Folder.name) private var allFolders: [Folder]
    @Query private var allItems: [WardrobeItem]

    @State private var search = ""
    @State private var folderFilter: UUID?
    @State private var favoritesOnly = false
    @State private var tagFilter: String?
    @State private var showNew = false
    @State private var editing: CollageProject?
    @State private var renaming: CollageProject?
    @State private var renameText = ""
    @State private var organizing: CollageProject?
    @State private var deleting: CollageProject?
    @State private var showFolders = false
    @State private var alert: AppAlert?
    @State private var createdOutfit: Outfit?

    private var folders: [Folder] { allFolders.filter { $0.kind == .collage } }
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    private var visible: [CollageProject] {
        projects.filter { p in
            if favoritesOnly && !p.isFavorite { return false }
            if let f = folderFilter, p.folderID != f { return false }
            if let t = tagFilter, !p.tags.contains(t) { return false }
            if !search.isEmpty, !p.name.localizedCaseInsensitiveContains(search),
               !p.tags.contains(where: { $0.localizedCaseInsensitiveContains(search) }) { return false }
            return true
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if projects.isEmpty {
                    ScrollView { EmptyStateView(icon: "square.on.square.dashed", title: "Коллажей пока нет",
                                                message: "Создайте свободную композицию из вещей, текста и рамок.",
                                                actionTitle: "Создать коллаж") { showNew = true } }
                } else {
                    ScrollView {
                        filterBar
                        if visible.isEmpty {
                            EmptyStateView(icon: "magnifyingglass", title: "Ничего не найдено", message: "Измените запрос или фильтры.")
                        } else {
                            LazyVGrid(columns: columns, spacing: 14) { ForEach(visible) { card($0) } }.padding(AW.spacing)
                        }
                    }
                }
            }
            .awScreen()
            .navigationTitle("Коллажи")
            .searchable(text: $search, prompt: "Поиск коллажей")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showFolders = true } label: { Image(systemName: "folder") }.accessibilityLabel("Папки")
                    Button { showNew = true } label: { Image(systemName: "plus") }.accessibilityLabel("Новый коллаж")
                }
            }
            .sheet(isPresented: $showNew) { NewCollageSheet { open($0) } }
            .sheet(isPresented: $showFolders) { FolderManagerView(kind: .collage) }
            .sheet(item: $organizing) { p in
                OrganizeSheet(title: "Коллаж", tags: Binding(get: { p.tags }, set: { p.tags = $0; save() }),
                              folderID: Binding(get: { p.folderID }, set: { p.folderID = $0; save() }), kind: .collage)
            }
            .fullScreenCover(item: $editing) { p in CollageEditorView(project: p, context: context) }
            .alert("Переименовать", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Название", text: $renameText)
                Button("Сохранить") { renaming?.name = renameText; renaming?.updatedAt = Date(); save(); renaming = nil }
                Button("Отмена", role: .cancel) { renaming = nil }
            }
            .confirmationDialog("Удалить коллаж?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible, presenting: deleting) { p in
                Button("Удалить «\(p.name)»", role: .destructive) {
                    do { try CollageService.delete(p, context: context) } catch { alert = AppAlert(error: error) }
                    deleting = nil
                }
                Button("Отмена", role: .cancel) { deleting = nil }
            } message: { _ in Text("Действие нельзя отменить. Образы, созданные из этого коллажа, останутся.") }
            .sheet(item: $createdOutfit) { o in NavigationStack { OutfitDetailView(outfit: o) } }
            .appAlert($alert)
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                Button { favoritesOnly.toggle() } label: { AWChip(title: "Избранное", icon: "heart", selected: favoritesOnly) }
                ForEach(folders) { f in
                    Button { folderFilter = folderFilter == f.id ? nil : f.id } label: { AWChip(title: f.name, icon: "folder", selected: folderFilter == f.id) }
                }
                ForEach(Array(Set(projects.flatMap(\.tags))).sorted(), id: \.self) { t in
                    Button { tagFilter = tagFilter == t ? nil : t } label: { AWChip(title: "#\(t)", selected: tagFilter == t) }
                }
            }.padding(.horizontal, AW.spacing).padding(.top, 8)
        }
    }

    private func card(_ p: CollageProject) -> some View {
        Button { editing = p } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let f = p.previewFile { StoreImage(fileName: f, maxPixel: 400, contentMode: .fit) }
                        else { Image(systemName: "square.on.square.dashed").font(.largeTitle).foregroundStyle(AW.primary) }
                    }
                    .frame(maxWidth: .infinity).frame(height: 190)
                    .background(AW.card, in: RoundedRectangle(cornerRadius: AW.corner, style: .continuous))
                    .shadow(color: AW.primaryDark.opacity(0.07), radius: 8, y: 3)
                    if p.isFavorite { FavoriteBadge(isFavorite: true).padding(6) }
                }
                Text(p.name).font(.system(.subheadline, design: .rounded).weight(.semibold)).foregroundStyle(AW.textPrimary).lineLimit(1)
                Text(p.updatedAt.formatted(date: .abbreviated, time: .omitted)).font(AW.caption).foregroundStyle(AW.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { editing = p } label: { Label("Открыть", systemImage: "pencil.and.outline") }
            Button { renameText = p.name; renaming = p } label: { Label("Переименовать", systemImage: "textformat") }
            Button { p.isFavorite.toggle(); save() } label: { Label(p.isFavorite ? "Убрать из избранного" : "В избранное", systemImage: "heart") }
            Button { organizing = p } label: { Label("Папка и теги", systemImage: "folder.badge.plus") }
            Button { duplicate(p) } label: { Label("Дублировать", systemImage: "plus.square.on.square") }
            Button { makeOutfit(p) } label: { Label("Создать образ", systemImage: "sparkles") }
            Button(role: .destructive) { deleting = p } label: { Label("Удалить", systemImage: "trash") }
        }
    }

    private func open(_ p: CollageProject) { DispatchQueue.main.async { editing = p } }
    private func save() { do { try context.save() } catch { context.rollback(); alert = AppAlert(error: error) } }
    private func duplicate(_ p: CollageProject) { do { _ = try CollageService.duplicate(p, context: context) } catch { alert = AppAlert(error: error) } }
    private func makeOutfit(_ p: CollageProject) {
        do { createdOutfit = try OutfitService.create(from: p, items: allItems, context: context) }
        catch { alert = AppAlert(error: error, title: "Не удалось создать образ") }
    }
}

struct NewCollageSheet: View {
    let onCreate: (CollageProject) -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var aspect: CollageAspect = .portrait45
    @State private var bg = "#F5F0FC"
    @State private var alert: AppAlert?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Название", text: $name)
                Picker("Соотношение сторон", selection: $aspect) { ForEach(CollageAspect.allCases) { Text($0.title).tag($0) } }
                    .pickerStyle(.segmented)
                Section("Цвет фона") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack { ForEach(CollageBackground.pastelPresets, id: \.self) { h in
                            Button { bg = h } label: {
                                Circle().fill(Color(hex: h)).frame(width: 38, height: 38)
                                    .overlay(Circle().stroke(bg == h ? AW.primaryDark : AW.divider, lineWidth: bg == h ? 3 : 1))
                            }.accessibilityLabel("Цвет \(h)")
                        } }
                    }
                }
            }
            .navigationTitle("Новый коллаж").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Создать") { create() } }
            }
            .appAlert($alert)
        }
        .presentationDetents([.medium])
    }

    private func create() {
        do {
            let p = try CollageService.create(name: name, aspect: aspect, backgroundHex: bg, context: context)
            dismiss(); onCreate(p)
        } catch { alert = AppAlert(error: error, title: "Не удалось создать коллаж") }
    }
}
