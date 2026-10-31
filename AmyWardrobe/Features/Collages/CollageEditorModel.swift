import SwiftUI
import SwiftData

/// Модель редактора коллажа: документ, выделение, undo/redo, автосохранение.
@MainActor
final class CollageEditorModel: ObservableObject {
    @Published private(set) var document: CollageDocument
    @Published var selectedID: UUID?
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published var lastError: AppAlert?

    let project: CollageProject
    private let context: ModelContext
    private let store: ImageStore
    private let initial: CollageDocument
    private var undoStack: [CollageDocument] = []
    private var redoStack: [CollageDocument] = []
    private var saveTask: Task<Void, Never>?
    private var activeGestures: Set<String> = []
    private var dragBase: CGPoint?
    private var scaleBase: Double?
    private var rotationBase: Double?
    private let maxHistory = 100

    init(project: CollageProject, context: ModelContext, store: ImageStore = .shared) {
        self.project = project
        self.context = context
        self.store = store
        self.document = project.document
        self.initial = project.document
    }

    var selected: CollageObject? { selectedID.flatMap { document.object($0) } }
    var hasSessionChanges: Bool { document != initial }

    // MARK: История

    /// Сохраняет снимок для отмены. Во время жеста снимок делается один раз.
    func checkpoint() {
        guard activeGestures.isEmpty else { return }
        pushUndo()
    }

    private func pushUndo() {
        undoStack.append(document)
        if undoStack.count > maxHistory { undoStack.removeFirst() }
        redoStack.removeAll()
        refreshFlags()
    }

    private func refreshFlags() { canUndo = !undoStack.isEmpty; canRedo = !redoStack.isEmpty }

    func undo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(document)
        document = prev
        fixSelection(); refreshFlags(); scheduleSave()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(document)
        document = next
        fixSelection(); refreshFlags(); scheduleSave()
    }

    private func fixSelection() {
        if let id = selectedID, document.object(id) == nil { selectedID = nil }
    }

    /// Изменение документа с записью в историю.
    func mutate(_ change: (inout CollageDocument) -> Void) {
        checkpoint()
        change(&document)
        scheduleSave()
    }

    /// Изменение без записи в историю (внутри жеста или после `checkpoint()`).
    func liveUpdate(_ id: UUID, _ change: (inout CollageObject) -> Void) {
        guard let i = document.index(of: id) else { return }
        change(&document.objects[i])
        scheduleSave()
    }

    func select(_ id: UUID?) { if selectedID != id { selectedID = id } }

    // MARK: Жесты

    private func beginGesture(_ kind: String) {
        if activeGestures.isEmpty { pushUndo() }
        activeGestures.insert(kind)
    }

    private func endGesture(_ kind: String) {
        activeGestures.remove(kind)
        if activeGestures.isEmpty { scheduleSave() }
    }

    func dragChanged(_ id: UUID, translation: CGSize) {
        if dragBase == nil, let o = document.object(id) {
            beginGesture("drag")
            dragBase = CGPoint(x: o.centerX, y: o.centerY)
        }
        guard let base = dragBase else { return }
        let w = document.canvasWidth, h = document.canvasHeight
        liveUpdate(id) {
            $0.centerX = min(max(Double(base.x + translation.width), 0), w)
            $0.centerY = min(max(Double(base.y + translation.height), 0), h)
        }
    }
    func dragEnded() { if dragBase != nil { dragBase = nil; endGesture("drag") } }

    func magnifyChanged(_ id: UUID, factor: Double) {
        if scaleBase == nil, let o = document.object(id) {
            beginGesture("scale")
            scaleBase = o.scale
        }
        guard let base = scaleBase else { return }
        liveUpdate(id) { $0.scale = min(max(base * factor, CollageDocument.minScale), CollageDocument.maxScale) }
    }
    func magnifyEnded() { if scaleBase != nil { scaleBase = nil; endGesture("scale") } }

    func rotateChanged(_ id: UUID, delta: Double) {
        if rotationBase == nil, let o = document.object(id) {
            beginGesture("rotate")
            rotationBase = o.rotation
        }
        guard let base = rotationBase else { return }
        liveUpdate(id) { $0.rotation = base + delta }
    }
    func rotateEnded() { if rotationBase != nil { rotationBase = nil; endGesture("rotate") } }

    // MARK: Добавление объектов

    private func nextCenter() -> CGPoint {
        let c = document.canvasCenter
        let n = Double(document.objects.count % 6)
        return CGPoint(x: c.x + n * 26, y: c.y + n * 26)
    }

    func addItems(_ items: [WardrobeItem]) {
        guard !items.isEmpty else { return }
        mutate { doc in
            let side = doc.canvasWidth * 0.42
            for (i, item) in items.enumerated() {
                let size = store.pixelSize(fileName: item.imageFile) ?? CGSize(width: 1, height: 1)
                let c = CGPoint(x: doc.canvasCenter.x + Double(i % 5) * 30, y: doc.canvasCenter.y + Double(i % 5) * 30)
                let o = CollageObject.image(file: item.imageFile, itemID: item.id, pixelSize: size, at: c, maxSide: side)
                doc.objects.append(o)
                selectedID = o.id
            }
        }
    }

    func addImageData(_ data: Data) {
        do {
            let file = try store.save(data: data)
            let size = store.pixelSize(fileName: file) ?? CGSize(width: 1, height: 1)
            let o = CollageObject.image(file: file, itemID: nil, pixelSize: size, at: nextCenter(), maxSide: document.canvasWidth * 0.5)
            mutate { $0.objects.append(o) }
            selectedID = o.id
        } catch {
            lastError = AppAlert(error: error, title: "Не удалось добавить фото")
        }
    }

    func addText() {
        let o = CollageObject.text(TextStyle(), at: document.canvasCenter, width: document.canvasWidth * 0.7)
        mutate { $0.objects.append(o) }
        selectedID = o.id
    }

    func addFrame(_ style: FrameStyle = FrameStyle()) {
        let o = CollageObject.frame(style, at: document.canvasCenter,
                                    size: CGSize(width: document.canvasWidth * 0.5, height: document.canvasHeight * 0.5))
        mutate { $0.objects.append(o) }
        selectedID = o.id
    }

    // MARK: Операции над выбранным

    func deleteSelected() { guard let id = selectedID else { return }; mutate { $0.remove(id) }; selectedID = nil }
    func duplicateSelected() { guard let id = selectedID else { return }; var n: UUID?; mutate { n = $0.duplicate(id) }; selectedID = n }
    func bringForward() { guard let id = selectedID else { return }; mutate { $0.moveForward(id) } }
    func sendBackward() { guard let id = selectedID else { return }; mutate { $0.moveBackward(id) } }
    func bringToFront() { guard let id = selectedID else { return }; mutate { $0.bringToFront(id) } }
    func sendToBack() { guard let id = selectedID else { return }; mutate { $0.sendToBack(id) } }
    func centerSelected() { guard let id = selectedID else { return }; mutate { $0.centerOnCanvas(id) } }
    func flipSelected() {
        guard let id = selectedID else { return }
        mutate { doc in if let i = doc.index(of: id) { doc.objects[i].flippedX.toggle() } }
    }

    func updateText(_ change: (inout TextStyle) -> Void) {
        guard let id = selectedID else { return }
        liveUpdate(id) { o in
            guard var t = o.text else { return }
            change(&t)
            o.text = t
            o.refitText()
        }
    }

    func updateFrame(_ change: (inout FrameStyle) -> Void) {
        guard let id = selectedID else { return }
        liveUpdate(id) { o in
            guard var f = o.frame else { return }
            change(&f)
            o.frame = f
        }
    }

    func setBackground(_ bg: CollageBackground) { mutate { $0.background = bg } }
    func resizeCanvas(_ aspect: CollageAspect) { mutate { $0.resizeCanvas(to: aspect.size) } }

    // MARK: Сохранение

    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            if Task.isCancelled { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        saveTask?.cancel()
        project.document = document
        project.updatedAt = Date()
        do { try context.save() } catch {
            context.rollback()
            lastError = AppAlert(error: error, title: "Не удалось сохранить коллаж")
        }
    }

    /// Отмена изменений текущей сессии редактирования.
    func revertSession() {
        document = initial
        selectedID = nil
        undoStack.removeAll(); redoStack.removeAll(); refreshFlags()
        saveNow()
    }

    /// Финальное сохранение + обновление превью (рендер вне главного потока).
    func finish() async {
        saveNow()
        let doc = document
        let st = store
        let data: Data? = await Task.detached(priority: .utility) {
            CollageRenderer.render(doc, store: st, maxSide: 720).jpegData(compressionQuality: 0.85)
        }.value
        if let data, let file = try? store.save(data: data) {
            project.previewFile = file
            try? context.save()
        }
    }
}
