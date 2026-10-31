import SwiftUI
import SwiftData
import PhotosUI

private enum EditorSheet: String, Identifiable {
    case items, background, text, frame
    var id: String { rawValue }
}

struct CollageEditorView: View {
    @StateObject private var model: CollageEditorModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var zoom: CGFloat = 1
    @State private var panMode = false
    @State private var sheet: EditorSheet?
    @State private var showExitDialog = false
    @State private var photoItem: PhotosPickerItem?

    init(project: CollageProject, context: ModelContext) {
        _model = StateObject(wrappedValue: CollageEditorModel(project: project, context: context))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                canvasArea
                if model.selected != nil { selectionBar }
                toolBar
            }
            .awScreen()
            .navigationTitle(model.project.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Закрыть") { requestClose() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                        .disabled(!model.canUndo).accessibilityLabel("Отменить")
                    Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                        .disabled(!model.canRedo).accessibilityLabel("Повторить")
                    ExportMenu(baseName: model.project.name, makeImage: exportRender)
                }
            }
            .sheet(item: $sheet) { s in
                switch s {
                case .items:
                    ItemPickerView(title: "Добавить вещи", multiple: true) { model.addItems($0) }
                case .background:
                    BackgroundSheet(model: model).presentationDetents([.medium, .large])
                case .text:
                    TextEditSheet(model: model).presentationDetents([.medium, .large])
                case .frame:
                    FrameEditSheet(model: model).presentationDetents([.medium])
                }
            }
            .confirmationDialog("Есть изменения в этой сессии", isPresented: $showExitDialog, titleVisibility: .visible) {
                Button("Сохранить и выйти") { closeAndSave() }
                Button("Отменить изменения сессии", role: .destructive) { model.revertSession(); closeAndSave() }
                Button("Продолжить редактирование", role: .cancel) {}
            } message: {
                Text("Коллаж сохраняется автоматически. Можно вернуть его к состоянию на момент открытия.")
            }
            .onChange(of: scenePhase) { _, phase in if phase != .active { model.saveNow() } }
            .onChange(of: photoItem) { _, item in loadPhoto(item) }
            .appAlert($model.lastError)
        }
        .interactiveDismissDisabled()
    }

    private var exportRender: @Sendable () -> UIImage? {
        let doc = model.document
        return { CollageRenderer.render(doc, store: ImageStore.shared) }
    }

    private func requestClose() {
        if model.hasSessionChanges { showExitDialog = true } else { closeAndSave() }
    }

    private func closeAndSave() {
        Task { await model.finish(); dismiss() }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                model.addImageData(data)
            } else {
                model.lastError = AppAlert(title: "Не удалось добавить фото", message: "Фото не удалось прочитать.")
            }
            photoItem = nil
        }
    }

    // MARK: Полотно

    private var canvasArea: some View {
        GeometryReader { geo in
            let doc = model.document
            let fit = min((geo.size.width - 24) / doc.canvasWidth, (geo.size.height - 24) / doc.canvasHeight)
            let s = max(0.01, fit) * zoom
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                CollageCanvasView(model: model, scale: s, interactive: !panMode)
                    .frame(width: doc.canvasWidth * s, height: doc.canvasHeight * s)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                    .padding(12)
                    .frame(minWidth: geo.size.width, minHeight: geo.size.height)
            }
            .scrollDisabled(!panMode)
        }
    }

    // MARK: Панели

    private var toolBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 14) {
                Button { zoom = max(1, zoom - 0.5) } label: { Image(systemName: "minus.magnifyingglass") }
                    .disabled(zoom <= 1).accessibilityLabel("Уменьшить полотно")
                Text("\(Int(zoom * 100))%").font(AW.caption).foregroundStyle(AW.textSecondary).frame(width: 44)
                Button { zoom = min(3, zoom + 0.5) } label: { Image(systemName: "plus.magnifyingglass") }
                    .disabled(zoom >= 3).accessibilityLabel("Увеличить полотно")
                Toggle(isOn: $panMode) { Image(systemName: "hand.draw") }
                    .toggleStyle(.button).tint(AW.primaryDark)
                    .accessibilityLabel("Режим перемещения полотна")
                Spacer()
            }
            .padding(.horizontal, 16).foregroundStyle(AW.primaryDark)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    toolButton("Вещи", "tshirt") { sheet = .items }
                    PhotosPicker(selection: $photoItem, matching: .images) { toolLabel("Фото", "photo") }
                    toolButton("Текст", "textformat") { model.addText(); sheet = .text }
                    toolButton("Рамка", "square.dashed") { model.addFrame(); sheet = .frame }
                    toolButton("Фон", "paintpalette") { sheet = .background }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 8)
        .background(AW.card)
    }

    private var selectionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("Дублировать", "plus.square.on.square") { model.duplicateSelected() }
                chip("Вперёд", "square.2.layers.3d.top.filled") { model.bringForward() }
                chip("Назад", "square.2.layers.3d.bottom.filled") { model.sendBackward() }
                chip("На верх", "arrow.up.to.line") { model.bringToFront() }
                chip("На низ", "arrow.down.to.line") { model.sendToBack() }
                chip("По центру", "align.horizontal.center") { model.centerSelected() }
                if model.selected?.kind == .image { chip("Отразить", "arrow.left.and.right.righttriangle.left.righttriangle.right") { model.flipSelected() } }
                if model.selected?.kind == .text { chip("Текст", "pencil") { sheet = .text } }
                if model.selected?.kind == .frame { chip("Рамка", "slider.horizontal.3") { sheet = .frame } }
                Button(role: .destructive) { model.deleteSelected() } label: {
                    Label("Удалить", systemImage: "trash").font(.system(.subheadline, design: .rounded).weight(.medium))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(AW.card, in: Capsule()).foregroundStyle(AW.danger)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .background(AW.pink.opacity(0.6))
    }

    private func chip(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { AWChip(title: title, icon: icon) }
    }

    private func toolButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { toolLabel(title, icon) }
    }

    private func toolLabel(_ title: String, _ icon: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.title3)
            Text(title).font(AW.caption)
        }
        .foregroundStyle(AW.primaryDark)
        .frame(width: 64, height: 50)
        .background(AW.pink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Полотно

struct CollageCanvasView: View {
    @ObservedObject var model: CollageEditorModel
    let scale: CGFloat
    let interactive: Bool

    var body: some View {
        let doc = model.document
        ZStack(alignment: .topLeading) {
            CanvasBackgroundView(background: doc.background, scale: scale)
                .frame(width: doc.canvasWidth * scale, height: doc.canvasHeight * scale)
                .contentShape(Rectangle())
                .onTapGesture { model.select(nil) }
            ForEach(doc.objects) { obj in
                objectView(obj)
            }
        }
        .frame(width: doc.canvasWidth * scale, height: doc.canvasHeight * scale, alignment: .topLeading)
    }

    @ViewBuilder
    private func objectView(_ obj: CollageObject) -> some View {
        let w = obj.width * obj.scale * scale
        let h = obj.height * obj.scale * scale
        let isSelected = model.selectedID == obj.id
        content(obj)
            .frame(width: w, height: h)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(AW.primaryDark, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                }
            }
            .rotationEffect(.radians(obj.rotation))
            .offset(x: obj.centerX * scale - w / 2, y: obj.centerY * scale - h / 2)
            .allowsHitTesting(interactive)
            .onTapGesture { model.select(obj.id) }
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { v in
                        model.select(obj.id)
                        model.dragChanged(obj.id, translation: CGSize(width: v.translation.width / scale, height: v.translation.height / scale))
                    }
                    .onEnded { _ in model.dragEnded() }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { v in model.select(obj.id); model.magnifyChanged(obj.id, factor: Double(v.magnification)) }
                    .onEnded { _ in model.magnifyEnded() }
            )
            .simultaneousGesture(
                RotateGesture()
                    .onChanged { v in model.select(obj.id); model.rotateChanged(obj.id, delta: v.rotation.radians) }
                    .onEnded { _ in model.rotateEnded() }
            )
            .accessibilityLabel(accessibilityName(obj))
    }

    @ViewBuilder
    private func content(_ obj: CollageObject) -> some View {
        switch obj.kind {
        case .image:
            StoreImage(fileName: obj.imageFile, maxPixel: 1200, contentMode: .fill)
                .scaleEffect(x: obj.flippedX ? -1 : 1, y: 1)
        case .text, .frame:
            LayerImageView(object: obj, pixelScale: max(1, scale * obj.scale * 2))
        }
    }

    private func accessibilityName(_ obj: CollageObject) -> String {
        switch obj.kind {
        case .image: return "Изображение"
        case .text: return "Текст: \(obj.text?.content ?? "")"
        case .frame: return "Рамка"
        }
    }
}

/// Слой текста/рамки: рисуется тем же кодом, что и экспорт.
struct LayerImageView: View {
    let object: CollageObject
    let pixelScale: CGFloat
    var body: some View {
        if let img = CollageRenderer.layerImage(for: object, renderScale: pixelScale) {
            Image(uiImage: img).resizable()
        } else {
            Color.clear
        }
    }
}

struct CanvasBackgroundView: View {
    let background: CollageBackground
    let scale: CGFloat
    var body: some View {
        switch background {
        case .solid(let hex):
            Color(hex: hex)
        case .gradient(let top, let bottom):
            LinearGradient(colors: [Color(hex: top), Color(hex: bottom)], startPoint: .top, endPoint: .bottom)
        case .dots(let base, let dot):
            ZStack {
                Color(hex: base)
                Canvas { ctx, size in
                    let step = 54 * scale
                    var y = step / 2
                    while y < size.height {
                        var x = step / 2
                        while x < size.width {
                            ctx.fill(Path(ellipseIn: CGRect(x: x - 4 * scale, y: y - 4 * scale, width: 8 * scale, height: 8 * scale)),
                                     with: .color(Color(hex: dot).opacity(0.5)))
                            x += step
                        }
                        y += step
                    }
                }
            }
        }
    }
}

// MARK: - Листы настройки

private struct BackgroundSheet: View {
    @ObservedObject var model: CollageEditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var kind = 0
    @State private var hexA = "#F5F0FC"
    @State private var hexB = "#F4E5F0"

    var body: some View {
        NavigationStack {
            Form {
                Section("Тип фона") {
                    Picker("Тип", selection: $kind) {
                        Text("Цвет").tag(0); Text("Градиент").tag(1); Text("Точки").tag(2)
                    }.pickerStyle(.segmented)
                }
                Section("Цвета") {
                    colorRow("Основной", hex: $hexA)
                    if kind != 0 { colorRow(kind == 1 ? "Нижний" : "Цвет точек", hex: $hexB) }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(CollageBackground.pastelPresets, id: \.self) { h in
                                Button { hexA = h; apply() } label: {
                                    Circle().fill(Color(hex: h)).frame(width: 34, height: 34)
                                        .overlay(Circle().stroke(AW.divider, lineWidth: 1))
                                }.accessibilityLabel("Пастельный цвет \(h)")
                            }
                        }
                    }
                }
                Section("Размер полотна") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(CollageAspect.allCases) { a in
                                Button { model.resizeCanvas(a) } label: {
                                    AWChip(title: a.title, selected: isCurrent(a))
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Фон и полотно")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
            .onAppear(perform: load)
            .onChange(of: kind) { _, _ in apply() }
            .onChange(of: hexA) { _, _ in apply() }
            .onChange(of: hexB) { _, _ in apply() }
        }
    }

    private func isCurrent(_ a: CollageAspect) -> Bool {
        Int(model.document.canvasWidth) == Int(a.size.width) && Int(model.document.canvasHeight) == Int(a.size.height)
    }

    private func colorRow(_ title: String, hex: Binding<String>) -> some View {
        ColorPicker(title, selection: Binding(get: { Color(hex: hex.wrappedValue) }, set: { hex.wrappedValue = $0.hexString }), supportsOpacity: false)
    }

    private func load() {
        switch model.document.background {
        case .solid(let h): kind = 0; hexA = h
        case .gradient(let t, let b): kind = 1; hexA = t; hexB = b
        case .dots(let b, let d): kind = 2; hexA = b; hexB = d
        }
    }

    private func apply() {
        let bg: CollageBackground
        switch kind {
        case 1: bg = .gradient(topHex: hexA, bottomHex: hexB)
        case 2: bg = .dots(baseHex: hexA, dotHex: hexB)
        default: bg = .solid(hex: hexA)
        }
        if bg != model.document.background { model.setBackground(bg) }
    }
}

private struct TextEditSheet: View {
    @ObservedObject var model: CollageEditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var style = TextStyle()

    var body: some View {
        NavigationStack {
            Form {
                Section("Текст") {
                    TextField("Введите текст", text: $style.content, axis: .vertical).lineLimit(1...4)
                }
                Section("Оформление") {
                    Picker("Шрифт", selection: $style.font) {
                        ForEach(CollageFont.allCases) { Text($0.title).tag($0) }
                    }
                    HStack { Text("Размер"); Slider(value: $style.fontSize, in: 20...240) }
                    ColorPicker("Цвет", selection: Binding(get: { Color(hex: style.colorHex) }, set: { style.colorHex = $0.hexString }), supportsOpacity: false)
                    Picker("Выравнивание", selection: $style.alignment) {
                        ForEach(CollageTextAlignment.allCases) { Image(systemName: $0.icon).tag($0) }
                    }.pickerStyle(.segmented)
                }
            }
            .navigationTitle("Текст")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
            .onAppear {
                if let t = model.selected?.text { style = t }
                model.checkpoint()
            }
            .onChange(of: style) { _, new in model.updateText { $0 = new } }
        }
    }
}

private struct FrameEditSheet: View {
    @ObservedObject var model: CollageEditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var style = FrameStyle()

    var body: some View {
        NavigationStack {
            Form {
                Picker("Вид", selection: $style.style) {
                    ForEach(FrameLineStyle.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                ColorPicker("Цвет", selection: Binding(get: { Color(hex: style.colorHex) }, set: { style.colorHex = $0.hexString }), supportsOpacity: false)
                HStack { Text("Толщина"); Slider(value: $style.lineWidth, in: 2...40) }
                HStack { Text("Скругление"); Slider(value: $style.cornerRadius, in: 0...300) }
            }
            .navigationTitle("Рамка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
            .onAppear {
                if let f = model.selected?.frame { style = f }
                model.checkpoint()
            }
            .onChange(of: style) { _, new in model.updateFrame { $0 = new } }
        }
    }
}
