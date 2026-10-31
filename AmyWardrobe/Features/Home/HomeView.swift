import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var settings: AppSettings
    @Query(sort: \WardrobeItem.createdAt, order: .reverse) private var items: [WardrobeItem]
    @Query(sort: \Outfit.updatedAt, order: .reverse) private var outfits: [Outfit]
    @Query(sort: \CollageProject.updatedAt, order: .reverse) private var collages: [CollageProject]

    @State private var showAdd = false
    @State private var showNewCollage = false
    @State private var showNewOutfit = false
    @State private var editing: CollageProject?
    @State private var occasion: Occasion = .everyday
    @State private var seed: UInt64 = 1
    @State private var alert: AppAlert?

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        let base = h < 6 ? "Доброй ночи" : h < 12 ? "Доброе утро" : h < 18 ? "Добрый день" : "Добрый вечер"
        let n = settings.data.userName.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? base : "\(base), \(n)"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(greeting).font(AW.title)
                        Text("Что наденем сегодня?").font(AW.body).foregroundStyle(AW.textSecondary)
                    }
                    quickActions
                    if !items.isEmpty { recentItems }
                    suggestions
                    if !outfits.filter(\.isFavorite).isEmpty { favoriteOutfits }
                    if !collages.isEmpty { recentCollages }
                }
                .padding(AW.spacing)
            }
            .awScreen()
            .navigationTitle("Главная").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showAdd) { ItemEditorView(mode: .new) }
            .sheet(isPresented: $showNewCollage) { NewCollageSheet { p in DispatchQueue.main.async { editing = p } } }
            .sheet(isPresented: $showNewOutfit) { NewOutfitSheet(preselected: []) {} }
            .fullScreenCover(item: $editing) { CollageEditorView(project: $0, context: context) }
            .appAlert($alert)
        }
    }

    private var quickActions: some View {
        HStack(spacing: 10) {
            action("Вещь", "plus.circle.fill") { showAdd = true }
            action("Коллаж", "square.on.square.dashed") { showNewCollage = true }
            action("Образ", "sparkles") { showNewOutfit = true }
        }
    }

    private func action(_ title: String, _ icon: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 6) { Image(systemName: icon).font(.title2); Text(title).font(.system(.footnote, design: .rounded).weight(.semibold)) }
                .foregroundStyle(AW.primaryDark).frame(maxWidth: .infinity).padding(.vertical, 14)
                .awCard()
        }
    }

    private var recentItems: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Недавно добавлено")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(items.prefix(10)) { i in
                        NavigationLink { ItemDetailView(item: i) } label: { ItemCard(item: i).frame(width: 104) }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var favoriteOutfits: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Избранные образы")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(outfits.filter(\.isFavorite).prefix(8)) { o in
                        NavigationLink { OutfitDetailView(outfit: o) } label: {
                            VStack(alignment: .leading) {
                                StoreImage(fileName: o.tryOnFile ?? o.previewFile, maxPixel: 300).frame(width: 130, height: 160)
                                    .background(AW.card, in: RoundedRectangle(cornerRadius: AW.corner, style: .continuous))
                                Text(o.name).font(AW.caption).foregroundStyle(AW.textPrimary).lineLimit(1)
                            }
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var recentCollages: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Последние коллажи")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(collages.prefix(8)) { c in
                        Button { editing = c } label: {
                            VStack(alignment: .leading) {
                                StoreImage(fileName: c.previewFile, maxPixel: 300).frame(width: 130, height: 160)
                                    .background(AW.card, in: RoundedRectangle(cornerRadius: AW.corner, style: .continuous))
                                Text(c.name).font(AW.caption).foregroundStyle(AW.textPrimary).lineLimit(1)
                            }
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var suggestions: some View {
        let list = StylistEngine.suggest(items: items, occasion: occasion, season: Season.current(), count: 3, seed: seed)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Подборка сочетаний", actionTitle: "Обновить") { seed &+= 1 }
            Text("Подбор по правилам (цвет, сезон, повод) — без ИИ.").font(AW.caption).foregroundStyle(AW.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack { ForEach(Occasion.allCases) { o in Button { occasion = o } label: { AWChip(title: o.title, selected: occasion == o) } } }
            }
            if list.isEmpty {
                Text("Добавьте верх и низ (или платье), чтобы появились сочетания.")
                    .font(AW.body).foregroundStyle(AW.textSecondary).padding(16).frame(maxWidth: .infinity).awCard()
            } else {
                ForEach(list) { s in
                    VStack(alignment: .leading, spacing: 8) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack { ForEach(s.items) { i in StoreImage(fileName: i.imageFile).frame(width: 70, height: 70) } }
                        }
                        if !s.reasons.isEmpty { Text(s.reasons.prefix(3).joined(separator: " · ")).font(AW.caption).foregroundStyle(AW.textSecondary) }
                        Button { save(s) } label: { Label("Сохранить как образ", systemImage: "plus") }.buttonStyle(SecondaryButtonStyle())
                    }
                    .padding(14).awCard()
                }
            }
        }
    }

    private func save(_ s: OutfitSuggestion) {
        do { _ = try OutfitService.create(from: s.items, name: "\(occasion.title) — подборка", context: context)
             alert = AppAlert(title: "Образ сохранён", message: "Он появился во вкладке «Образы».")
        } catch { alert = AppAlert(error: error, title: "Не удалось сохранить") }
    }
}
