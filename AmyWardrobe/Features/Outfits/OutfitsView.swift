import SwiftUI
import SwiftData

struct OutfitsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Outfit.updatedAt, order: .reverse) private var outfits: [Outfit]
    @Query(sort: \Folder.name) private var allFolders: [Folder]
    @Query(sort: \CollageProject.updatedAt, order: .reverse) private var collages: [CollageProject]
    @Query private var allItems: [WardrobeItem]

    @State private var search = ""
    @State private var favoritesOnly = false
    @State private var folderFilter: UUID?
    @State private var showNew = false
    @State private var showFromCollage = false
    @State private var showFolders = false
    @State private var organizing: Outfit?
    @State private var deleting: Outfit?
    @State private var alert: AppAlert?

    private var folders: [Folder] { allFolders.filter { $0.kind == .outfit } }
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    private var visible: [Outfit] {
        outfits.filter { o in
            if favoritesOnly && !o.isFavorite { return false }
            if let f = folderFilter, o.folderID != f { return false }
            if !search.isEmpty, !o.name.localizedCaseInsensitiveContains(search),
               !o.tags.contains(where: { $0.localizedCaseInsensitiveContains(search) }) { return false }
            return true
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if outfits.isEmpty {
                    ScrollView { EmptyStateView(icon: "sparkles", title: "Образов пока нет",
                                                message: "Соберите образ из вещей гардероба или превратите коллаж в образ.",
                                                actionTitle: "Создать образ") { showNew = true } }
                } else {
                    ScrollView {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                Button { favoritesOnly.toggle() } label: { AWChip(title: "Избранное", icon: "heart", selected: favoritesOnly) }
                                ForEach(folders) { f in
                                    Button { folderFilter = folderFilter == f.id ? nil : f.id } label: { AWChip(title: f.name, icon: "folder", selected: folderFilter == f.id) }
                                }
                            }.padding(.horizontal, AW.spacing).padding(.top, 8)
                        }
                        if visible.isEmpty {
                            EmptyStateView(icon: "magnifyingglass", title: "Ничего не найдено", message: "Измените запрос или фильтры.")
                        } else {
                            LazyVGrid(columns: columns, spacing: 14) { ForEach(visible) { card($0) } }.padding(AW.spacing)
                        }
                    }
                }
            }
            .awScreen()
            .navigationTitle("Образы")
            .searchable(text: $search, prompt: "Поиск образов")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showFolders = true } label: { Image(systemName: "folder") }.accessibilityLabel("Папки")
                    Menu {
                        Button { showNew = true } label: { Label("Из вещей гардероба", systemImage: "tshirt") }
                        Button { showFromCollage = true } label: { Label("Из коллажа", systemImage: "square.on.square.dashed") }
                    } label: { Image(systemName: "plus") }.accessibilityLabel("Новый образ")
                }
            }
            .sheet(isPresented: $showNew) { NewOutfitSheet(preselected: []) {} }
            .sheet(isPresented: $showFolders) { FolderManagerView(kind: .outfit) }
            .sheet(isPresented: $showFromCollage) { collagePicker }
            .sheet(item: $organizing) { o in
                OrganizeSheet(title: "Образ", tags: Binding(get: { o.tags }, set: { o.tags = $0; save(o) }),
                              folderID: Binding(get: { o.folderID }, set: { o.folderID = $0; save(o) }), kind: .outfit)
            }
            .confirmationDialog("Удалить образ?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible, presenting: deleting) { o in
                Button("Удалить «\(o.name)»", role: .destructive) { delete(o) }
                Button("Отмена", role: .cancel) { deleting = nil }
            } message: { _ in Text("Вещи гардероба и коллажи не затрагиваются.") }
            .appAlert($alert)
        }
    }

    private func card(_ o: Outfit) -> some View {
        NavigationLink { OutfitDetailView(outfit: o) } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    StoreImage(fileName: o.tryOnFile ?? o.previewFile, maxPixel: 400)
                        .frame(maxWidth: .infinity).frame(height: 190)
                        .background(AW.card, in: RoundedRectangle(cornerRadius: AW.corner, style: .continuous))
                        .shadow(color: AW.primaryDark.opacity(0.07), radius: 8, y: 3)
                    if o.isFavorite { FavoriteBadge(isFavorite: true).padding(6) }
                }
                Text(o.name).font(.system(.subheadline, design: .rounded).weight(.semibold)).foregroundStyle(AW.textPrimary).lineLimit(1)
                Text("\(o.entries.count) вещ. · \(o.origin.title)").font(AW.caption).foregroundStyle(AW.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { o.isFavorite.toggle(); save(o) } label: { Label(o.isFavorite ? "Убрать из избранного" : "В избранное", systemImage: "heart") }
            Button { organizing = o } label: { Label("Папка и теги", systemImage: "folder.badge.plus") }
            Button { do { _ = try OutfitService.duplicate(o, context: context) } catch { alert = AppAlert(error: error) } } label: { Label("Дублировать", systemImage: "plus.square.on.square") }
            Button(role: .destructive) { deleting = o } label: { Label("Удалить", systemImage: "trash") }
        }
    }

    private var collagePicker: some View {
        NavigationStack {
            List(collages) { c in
                Button {
                    do { _ = try OutfitService.create(from: c, items: allItems, context: context); showFromCollage = false }
                    catch { alert = AppAlert(error: error, title: "Не удалось создать образ") }
                } label: {
                    HStack { StoreImage(fileName: c.previewFile, maxPixel: 200).frame(width: 52, height: 64); Text(c.name); Spacer() }
                }
            }
            .overlay { if collages.isEmpty { EmptyStateView(icon: "square.on.square.dashed", title: "Нет коллажей", message: "Сначала создайте коллаж.") } }
            .navigationTitle("Выберите коллаж").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Отмена") { showFromCollage = false } } }
        }
    }

    private func save(_ o: Outfit) { o.updatedAt = Date(); do { try context.save() } catch { context.rollback(); alert = AppAlert(error: error) } }

    private func delete(_ o: Outfit) {
        context.delete(o)
        do { try context.save(); GarbageCollector.run(context: context) } catch { context.rollback(); alert = AppAlert(error: error) }
        deleting = nil
    }
}

struct NewOutfitSheet: View {
    let preselected: [WardrobeItem]
    let onDone: () -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var chosen: [WardrobeItem] = []
    @State private var showPicker = false
    @State private var alert: AppAlert?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Название образа", text: $name)
                Section("Вещи (\(chosen.count))") {
                    ForEach(chosen) { i in
                        HStack { StoreImage(fileName: i.imageFile, maxPixel: 120).frame(width: 40, height: 40); Text(i.name) }
                    }
                    .onDelete { chosen.remove(atOffsets: $0) }
                    Button { showPicker = true } label: { Label("Добавить вещи", systemImage: "plus") }
                }
            }
            .navigationTitle("Новый образ").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Создать") { create() }.disabled(chosen.isEmpty) }
            }
            .sheet(isPresented: $showPicker) {
                ItemPickerView(title: "Вещи для образа", multiple: true, excluding: Set(chosen.map(\.id))) { chosen.append(contentsOf: $0) }
            }
            .onAppear { if chosen.isEmpty { chosen = preselected } }
            .appAlert($alert)
        }
    }

    private func create() {
        do { _ = try OutfitService.create(from: chosen, name: name, context: context); onDone(); dismiss() }
        catch { alert = AppAlert(error: error, title: "Не удалось создать образ") }
    }
}

struct OutfitDetailView: View {
    let outfit: Outfit
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var showTryOn = false
    @State private var replacing: OutfitEntry?
    @State private var showAdd = false
    @State private var alert: AppAlert?
    @State private var refresh = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                StoreImage(fileName: outfit.tryOnFile ?? outfit.previewFile, maxPixel: 1200)
                    .frame(maxWidth: .infinity).frame(height: 420).padding(8).awCard()
                    .id(refresh)

                VStack(alignment: .leading, spacing: 10) {
                    TextField("Название", text: Binding(get: { outfit.name }, set: { outfit.name = $0; touch() }))
                        .font(.system(.title3, design: .rounded).weight(.bold))
                    TextField("Описание", text: Binding(get: { outfit.details }, set: { outfit.details = $0; touch() }), axis: .vertical)
                        .font(AW.body).foregroundStyle(AW.textSecondary)
                    Text("\(outfit.origin.title) · создан \(outfit.createdAt.formatted(date: .abbreviated, time: .omitted)) · изменён \(outfit.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(AW.caption).foregroundStyle(AW.textSecondary)
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading).awCard()

                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Вещи образа", actionTitle: "Добавить") { showAdd = true }
                    ForEach(outfit.entries) { e in
                        HStack(spacing: 12) {
                            StoreImage(fileName: e.imageFile, maxPixel: 200).frame(width: 52, height: 52)
                            VStack(alignment: .leading) { Text(e.name).font(AW.body); Text(e.subcategory).font(AW.caption).foregroundStyle(AW.textSecondary) }
                            Spacer()
                            Button { replacing = e } label: { Image(systemName: "arrow.triangle.2.circlepath") }.accessibilityLabel("Заменить вещь")
                            Button(role: .destructive) { remove(e) } label: { Image(systemName: "minus.circle") }.accessibilityLabel("Убрать вещь")
                        }
                        .buttonStyle(.borderless).foregroundStyle(AW.textPrimary)
                    }
                }
                .padding(16).awCard()

                VStack(spacing: 10) {
                    Button { regeneratePreview() } label: { Label("Пересоздать превью", systemImage: "arrow.clockwise") }.buttonStyle(SecondaryButtonStyle())
                    Button { showTryOn = true } label: { Label("Примерить на аватаре", systemImage: "figure.stand.dress") }.buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding(AW.spacing)
        }
        .awScreen()
        .navigationTitle("Образ").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { outfit.isFavorite.toggle(); touch() } label: { Image(systemName: outfit.isFavorite ? "heart.fill" : "heart") }
                ExportMenu(baseName: outfit.name, makeImage: exportRender)
            }
        }
        .fullScreenCover(isPresented: $showTryOn, onDismiss: { refresh += 1 }) {
            TryOnView(entries: outfit.entries, outfit: outfit)
        }
        .sheet(item: $replacing) { e in
            ItemPickerView(title: "Заменить: \(e.name)", multiple: false) { picked in
                guard let item = picked.first else { return }
                var list = outfit.entries
                if let i = list.firstIndex(where: { $0.id == e.id }) {
                    list[i] = OutfitEntry(id: e.id, itemID: item.id, name: item.name, categoryID: item.categoryID, subcategory: item.subcategory, imageFile: item.imageFile)
                    outfit.entries = list; outfit.tryOnFile = nil; touch(); regeneratePreview()
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            ItemPickerView(title: "Добавить в образ", multiple: true, excluding: Set(outfit.entries.compactMap(\.itemID))) { items in
                outfit.entries = outfit.entries + OutfitService.entries(from: items); outfit.tryOnFile = nil; touch(); regeneratePreview()
            }
        }
        .appAlert($alert)
    }

    private var exportRender: @Sendable () -> UIImage? {
        let file = outfit.tryOnFile ?? outfit.previewFile
        let entries = outfit.entries
        return {
            if let file, let img = ImageStore.shared.downsampledImage(fileName: file, maxPixel: 3000) { return img }
            return CollageRenderer.render(OutfitService.autoLayoutDocument(for: entries, store: .shared), store: .shared)
        }
    }

    private func touch() { outfit.updatedAt = Date(); do { try context.save() } catch { context.rollback(); alert = AppAlert(error: error) } }

    private func remove(_ e: OutfitEntry) {
        guard outfit.entries.count > 1 else { alert = AppAlert(title: "Нельзя убрать", message: "В образе должна остаться хотя бы одна вещь."); return }
        outfit.entries = outfit.entries.filter { $0.id != e.id }
        outfit.tryOnFile = nil
        touch(); regeneratePreview()
    }

    private func regeneratePreview() {
        OutfitService.renderPreview(for: outfit)
        touch(); refresh += 1
    }
}
