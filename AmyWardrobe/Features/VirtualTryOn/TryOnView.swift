import SwiftUI
import SwiftData

struct TryOnGarment: Identifiable, Equatable {
    let id: UUID
    let name: String
    let categoryID: String
    let subcategory: String
    let imageFile: String
    var adjustment = PlacementAdjustment()
    var visible = true
}

@MainActor
final class TryOnViewModel: ObservableObject {
    @Published var garments: [TryOnGarment]
    @Published var selectedID: UUID?
    @Published private(set) var composed: UIImage?
    private var images: [UUID: UIImage] = [:]
    private var visual: AvatarVisual

    init(entries: [OutfitEntry], visual: AvatarVisual) {
        self.visual = visual
        garments = entries.map { TryOnGarment(id: $0.id, name: $0.name, categoryID: $0.categoryID, subcategory: $0.subcategory, imageFile: $0.imageFile) }
        selectedID = garments.first?.id
    }

    func load() async {
        for g in garments {
            let file = g.imageFile
            let img = await Task.detached(priority: .userInitiated) { ImageStore.shared.downsampledImage(fileName: file, maxPixel: 900) }.value
            if let img { images[g.id] = img }
        }
        refresh()
    }

    func updateVisual(_ v: AvatarVisual) { visual = v; refresh() }

    func placed(width: CGFloat = 720) -> [PlacedGarment] {
        let geometry = AvatarGeometry(visual: visual)
        return garments.compactMap { g in
            guard g.visible, let img = images[g.id] else { return nil }
            let p = GarmentPlacementEngine.place(imageSize: img.size, categoryID: g.categoryID, subcategory: g.subcategory,
                                                 geometry: geometry, adjustment: g.adjustment)
            return PlacedGarment(image: img, rect: p.rect, rotation: p.rotation, z: p.z)
        }
    }

    func refresh() { composed = TryOnCompositor.render(visual: visual, garments: placed(width: 720), width: 720) }

    func modify(_ id: UUID, _ change: (inout PlacementAdjustment) -> Void) {
        guard let i = garments.firstIndex(where: { $0.id == id }) else { return }
        change(&garments[i].adjustment)
        refresh()
    }

    func toggleVisible(_ id: UUID) {
        guard let i = garments.firstIndex(where: { $0.id == id }) else { return }
        garments[i].visible.toggle(); refresh()
    }

    func resetAdjustments() {
        for i in garments.indices { garments[i].adjustment = PlacementAdjustment() }
        refresh()
    }

    /// Финальный рендер в высоком разрешении (вне главного потока вызывается через замыкание).
    func exportRenderer() -> @Sendable () -> UIImage? {
        let placed = self.placed(width: 1200)
        let v = visual
        return { TryOnCompositor.render(visual: v, garments: placed, width: 1200) }
    }

    func avatarOnlyPNG() -> Data? { TryOnCompositor.render(visual: visual, garments: [], width: 768).pngData() }
}

struct TryOnView: View {
    let entries: [OutfitEntry]
    let outfit: Outfit?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var vm: TryOnViewModel
    @StateObject private var gen: TryOnGenerationController
    @State private var mode = 0
    @State private var alert: AppAlert?
    @State private var dragStart: CGSize = .zero
    @State private var dragging = false
    @State private var startedAt = Date()

    init(entries: [OutfitEntry], outfit: Outfit?) {
        self.entries = entries
        self.outfit = outfit
        let settingsData = SettingsData()   // реальные значения подставляются в onAppear
        _vm = StateObject(wrappedValue: TryOnViewModel(entries: entries, visual: settingsData.avatar))
        _gen = StateObject(wrappedValue: TryOnGenerationController(provider: UnavailableTryOnProvider()))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Режим", selection: $mode) {
                    Text("Композиция на аватаре").tag(0)
                    Text("ИИ-примерка (экспер.)").tag(1)
                }.pickerStyle(.segmented).padding(12)
                if mode == 0 { composeMode } else { aiMode }
            }
            .awScreen()
            .navigationTitle("Примерка").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
                ToolbarItemGroup(placement: .confirmationAction) {
                    if mode == 0 { ExportMenu(baseName: "AmyWardrobe-примерка", makeImage: vm.exportRenderer()) }
                }
            }
            .task {
                vm.updateVisual(settings.data.avatar)
                await vm.load()
            }
            .appAlert($alert)
        }
    }

    // MARK: Режим 1 — композиция

    private var composeMode: some View {
        VStack(spacing: 10) {
            Text("Это композиция: изображения вещей накладываются на нарисованный аватар. Это не генеративная ИИ-примерка.")
                .font(AW.caption).foregroundStyle(AW.textSecondary).padding(.horizontal, 16)
            GeometryReader { geo in
                if let img = vm.composed {
                    let aspect = AvatarGeometry.canvas.width / AvatarGeometry.canvas.height
                    let w = min(geo.size.width, geo.size.height * aspect)
                    Image(uiImage: img).resizable().scaledToFit()
                        .frame(width: w, height: w / aspect)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .gesture(DragGesture()
                            .onChanged { v in
                                guard let id = vm.selectedID else { return }
                                if !dragging { dragging = true; dragStart = CGSize(width: vm.garments.first { $0.id == id }?.adjustment.dx ?? 0, height: vm.garments.first { $0.id == id }?.adjustment.dy ?? 0) }
                                let k = AvatarGeometry.canvas.width / w
                                vm.modify(id) { $0.dx = Double(dragStart.width + v.translation.width * k); $0.dy = Double(dragStart.height + v.translation.height * k) }
                            }
                            .onEnded { _ in dragging = false })
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            controls
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(vm.garments) { g in
                        Button { vm.selectedID = g.id } label: {
                            VStack(spacing: 2) {
                                StoreImage(fileName: g.imageFile, maxPixel: 120).frame(width: 46, height: 46)
                                    .opacity(g.visible ? 1 : 0.35)
                                    .padding(4).background(vm.selectedID == g.id ? AW.pink : AW.card, in: RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(vm.selectedID == g.id ? AW.primaryDark : AW.divider))
                            }
                        }
                        .contextMenu { Button(g.visible ? "Скрыть" : "Показать") { vm.toggleVisible(g.id) } }
                        .accessibilityLabel(g.name)
                    }
                }.padding(.horizontal, 16)
            }
            if let id = vm.selectedID, let g = vm.garments.first(where: { $0.id == id }) {
                HStack { Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 24)
                    Slider(value: Binding(get: { g.adjustment.scale }, set: { v in vm.modify(id) { $0.scale = v } }), in: 0.4...2.0) }
                    .padding(.horizontal, 16)
                HStack { Image(systemName: "rotate.right").frame(width: 24)
                    Slider(value: Binding(get: { g.adjustment.rotation }, set: { v in vm.modify(id) { $0.rotation = v } }), in: -0.8...0.8) }
                    .padding(.horizontal, 16)
                Text("Перетащите вещь пальцем по аватару; нажмите и удерживайте миниатюру, чтобы скрыть вещь.")
                    .font(AW.caption).foregroundStyle(AW.textSecondary)
            }
            HStack(spacing: 10) {
                Button("Сбросить") { vm.resetAdjustments() }.buttonStyle(SecondaryButtonStyle())
                Button { saveResult() } label: { Label(outfit == nil ? "Сохранить результат" : "Сохранить в образ", systemImage: "square.and.arrow.down") }
                    .buttonStyle(PrimaryButtonStyle())
            }.padding(.horizontal, 16).padding(.bottom, 10)
        }
        .padding(.top, 6).background(AW.card)
    }

    private func saveResult() {
        let render = vm.exportRenderer()
        Task {
            let data = await Task.detached(priority: .userInitiated) { render()?.pngData() }.value
            guard let data else { alert = AppAlert(title: "Не удалось сохранить", message: "Не удалось подготовить изображение."); return }
            do {
                try TryOnRepository.save(imageData: data, mode: "compose", outfit: outfit, context: context)
                alert = AppAlert(title: "Сохранено", message: outfit == nil ? "Результат добавлен в историю примерок." : "Изображение стало превью образа.")
            } catch { alert = AppAlert(error: error, title: "Не удалось сохранить") }
        }
    }

    // MARK: Режим 2 — ИИ

    private var aiMode: some View {
        let provider = TryOnProviderFactory.make(settings: settings.data)
        return ScrollView {
            VStack(spacing: 14) {
                switch provider.availability() {
                case .unavailable(let reason):
                    EmptyStateView(icon: "wand.and.stars", title: "ИИ-примерка не подключена",
                                   message: reason + "\n\nПока доступна композиция на аватаре.")
                    Text("Подробности: docs/VIRTUAL_TRYON.md в репозитории. Для качественной генерации нужен GPU-сервер.")
                        .font(AW.caption).foregroundStyle(AW.textSecondary).multilineTextAlignment(.center)
                case .available:
                    Text("Сервер: \(provider.displayName)").font(AW.body)
                    Text("Эксперимент: модели обучены на фото реальных людей, на иллюстрированном аватаре результат может быть некорректным.")
                        .font(AW.caption).foregroundStyle(AW.textSecondary)
                    generationBody(provider: provider)
                }
            }.padding(16)
        }
    }

    @ViewBuilder
    private func generationBody(provider: any VirtualTryOnProvider) -> some View {
        switch gen.state {
        case .idle:
            Button("Запустить примерку") { startGeneration(provider) }.buttonStyle(PrimaryButtonStyle())
        case .running(let since):
            VStack(spacing: 10) {
                ProgressView()
                TimelineView(.periodic(from: since, by: 1)) { ctx in
                    Text("Генерация… \(Int(ctx.date.timeIntervalSince(since))) с").font(AW.caption)
                }
                Button("Отменить", role: .cancel) { gen.cancel() }.buttonStyle(SecondaryButtonStyle())
            }
        case .failed(let message):
            VStack(spacing: 10) {
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(AW.danger).font(AW.body)
                Button("Повторить") { startGeneration(provider) }.buttonStyle(PrimaryButtonStyle())
            }
        case .succeeded(let data):
            VStack(spacing: 10) {
                if let img = UIImage(data: data) { Image(uiImage: img).resizable().scaledToFit() }
                Button("Сохранить результат") {
                    do { try TryOnRepository.save(imageData: data, mode: "ai", outfit: outfit, context: context); alert = AppAlert(title: "Сохранено", message: "Результат добавлен в историю примерок.") }
                    catch { alert = AppAlert(error: error) }
                }.buttonStyle(PrimaryButtonStyle())
                Button("Повторить") { gen.reset(); startGeneration(provider) }.buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private func startGeneration(_ provider: any VirtualTryOnProvider) {
        guard let avatar = vm.avatarOnlyPNG() else { return }
        let garments: [TryOnGarmentPayload] = vm.garments.compactMap { g in
            guard let data = try? ImageStore.shared.loadData(g.imageFile) else { return nil }
            return TryOnGarmentPayload(name: g.name, categoryID: g.categoryID, imageData: data)
        }
        // контроллер привязан к провайдеру на момент создания — создаём актуальный
        gen.attach(provider: provider)
        gen.start(TryOnRequest(avatarPNG: avatar, garments: garments))
    }
}

/// Профиль → Аватар: мерки (необязательные) и визуальные параметры.
struct AvatarSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var tick = 0

    var body: some View {
        Form {
            Section {
                Image(uiImage: TryOnCompositor.render(visual: settings.data.avatar, garments: [], width: 360))
                    .resizable().scaledToFit().frame(height: 300).frame(maxWidth: .infinity)
                    .id(tick)
            }
            Section {
                Text("Мерки необязательны и хранятся только на устройстве. Вес не влияет на форму аватара: по росту и весу фигуру точно восстановить нельзя. Визуальные пропорции настраиваются вручную ниже.")
                    .font(AW.caption).foregroundStyle(AW.textSecondary)
            }
            Section("Реальные мерки") {
                measure("Рост", \.heightCm, unit: "см"); measure("Вес (необязательно)", \.weightKg, unit: "кг")
                measure("Обхват груди", \.bustCm, unit: "см"); measure("Обхват талии", \.waistCm, unit: "см")
                measure("Обхват бёдер", \.hipsCm, unit: "см"); measure("Длина ноги (внутр. шов)", \.inseamCm, unit: "см")
                measure("Длина корпуса", \.torsoLengthCm, unit: "см"); measure("Ширина плеч", \.shoulderWidthCm, unit: "см")
                Button("Подобрать пропорции аватара по меркам") {
                    let keep = settings.data.avatar
                    var s = AvatarVisual.suggested(from: settings.data.measurements)
                    s.hairHex = keep.hairHex; s.skinHex = keep.skinHex; s.eyeHex = keep.eyeHex
                    settings.data.avatar = s; tick += 1
                }
            }
            Section("Визуальные параметры аватара") {
                slider("Плечи", \.shoulder, 0.85...1.15); slider("Грудь", \.bust, 0.85...1.15); slider("Талия", \.waist, 0.85...1.15)
                slider("Бёдра", \.hip, 0.85...1.15); slider("Длина корпуса", \.torso, 0.9...1.1); slider("Длина ног", \.leg, 0.9...1.1)
                colorRow("Волосы", \.hairHex); colorRow("Тон кожи", \.skinHex); colorRow("Глаза", \.eyeHex)
                Button("Сбросить аватар") { settings.data.avatar = AvatarVisual(); tick += 1 }
            }
        }
        .scrollContentBackground(.hidden).awScreen()
        .navigationTitle("Аватар")
    }

    private func measure(_ title: String, _ kp: WritableKeyPath<BodyMeasurements, Double?>, unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("—", value: Binding(get: { settings.data.measurements[keyPath: kp] }, set: { settings.data.measurements[keyPath: kp] = $0 }), format: .number)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
            Text(unit).foregroundStyle(AW.textSecondary)
        }
    }

    private func slider(_ title: String, _ kp: WritableKeyPath<AvatarVisual, Double>, _ range: ClosedRange<Double>) -> some View {
        HStack { Text(title).frame(width: 110, alignment: .leading)
            Slider(value: Binding(get: { settings.data.avatar[keyPath: kp] }, set: { settings.data.avatar[keyPath: kp] = $0; tick += 1 }), in: range) }
    }

    private func colorRow(_ title: String, _ kp: WritableKeyPath<AvatarVisual, String>) -> some View {
        ColorPicker(title, selection: Binding(get: { Color(hex: settings.data.avatar[keyPath: kp]) },
                                              set: { settings.data.avatar[keyPath: kp] = $0.hexString; tick += 1 }), supportsOpacity: false)
    }
}
