import SwiftUI
import SwiftData

struct ItemDetailView: View {
    let item: WardrobeItem
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings
    @State private var showEdit = false
    @State private var confirmDelete = false
    @State private var alert: AppAlert?
    @State private var showTryOn = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                StoreImage(fileName: item.imageFile, maxPixel: 1400)
                    .padding(16).frame(maxWidth: .infinity).frame(height: 340)
                    .awCard()

                VStack(alignment: .leading, spacing: 10) {
                    Text(item.name).font(.system(.title2, design: .rounded).weight(.bold))
                    Text([settings.categoryTitle(item.categoryID), item.subcategory].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(AW.body).foregroundStyle(AW.textSecondary)
                    detailRow("Цвет", ColorPalette.name(for: item.primaryColorHex), swatch: item.primaryColorHex)
                    if !item.sizeValue.isEmpty {
                        detailRow("Размер", "\(item.sizeValue) (\((SizeSystem(rawValue: item.sizeSystem) ?? .custom).title))")
                    }
                    if !item.material.isEmpty { detailRow("Материал", item.material) }
                    if !item.seasons.isEmpty { detailRow("Сезоны", Season.allCases.filter { item.seasons.contains($0) }.map(\.title).joined(separator: ", ")) }
                    detailRow("Надето раз", "\(item.wearCount)")
                    detailRow("Добавлено", item.createdAt.formatted(date: .abbreviated, time: .omitted))
                    if !item.tags.isEmpty {
                        FlowLayout { ForEach(item.tags, id: \.self) { Text("#\($0)").font(AW.caption).padding(.horizontal, 10).padding(.vertical, 5).background(AW.pink, in: Capsule()).foregroundStyle(AW.primaryDark) } }
                    }
                    if !item.details.isEmpty { Text(item.details).font(AW.body) }
                    if !item.notes.isEmpty { Text("Заметки: \(item.notes)").font(AW.body).foregroundStyle(AW.textSecondary) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16).awCard()

                VStack(spacing: 10) {
                    Button { WardrobeService.markWorn(item, context: context) } label: { Label("Отметить «надето сегодня»", systemImage: "checkmark.circle") }
                        .buttonStyle(SecondaryButtonStyle())
                    Button { showTryOn = true } label: { Label("Примерить на аватаре", systemImage: "figure.stand.dress") }
                        .buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding(AW.spacing)
        }
        .awScreen()
        .navigationTitle("Вещь")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { item.isFavorite.toggle(); item.updatedAt = Date(); try? context.save() } label: {
                    Image(systemName: item.isFavorite ? "heart.fill" : "heart")
                }.accessibilityLabel("Избранное")
                Button { showEdit = true } label: { Image(systemName: "pencil") }.accessibilityLabel("Редактировать")
                Button(role: .destructive) { confirmDelete = true } label: { Image(systemName: "trash") }.accessibilityLabel("Удалить")
            }
        }
        .sheet(isPresented: $showEdit) { ItemEditorView(mode: .edit(item)) }
        .fullScreenCover(isPresented: $showTryOn) {
            TryOnView(entries: OutfitService.entries(from: [item]), outfit: nil)
        }
        .confirmationDialog("Удалить «\(item.name)»?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                do { try WardrobeService.delete([item], context: context); dismiss() }
                catch { alert = AppAlert(error: error, title: "Не удалось удалить") }
            }
            Button("Отмена", role: .cancel) {}
        } message: { Text("Образы и коллажи с этой вещью сохранят её изображение.") }
        .appAlert($alert)
    }

    private func detailRow(_ title: String, _ value: String, swatch: String? = nil) -> some View {
        HStack {
            Text(title).foregroundStyle(AW.textSecondary)
            Spacer()
            if let swatch { Circle().fill(Color(hex: swatch)).frame(width: 16, height: 16).overlay(Circle().stroke(AW.divider)) }
            Text(value).foregroundStyle(AW.textPrimary)
        }.font(AW.body)
    }
}
