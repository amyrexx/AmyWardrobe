import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct BackupView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var settings: AppSettings
    @State private var working = false
    @State private var status: String?
    @State private var alert: AppAlert?
    @State private var shareItem: IdentifiableURL?
    @State private var filesItem: IdentifiableURL?
    @State private var showImporter = false
    @State private var pending: PendingRestore?
    @State private var restoreSettings = true
    @State private var backups: [URL] = []

    struct PendingRestore: Identifiable {
        let id = UUID()
        let inspection: BackupInspection
    }

    var body: some View {
        List {
            Section {
                Text("Резервная копия — это ZIP-файл со всем гардеробом, коллажами и образами. Это ручной экспорт, а не автоматическая синхронизация между устройствами. Чтобы копия пережила переустановку, сохраните её в «Файлы» (например, в iCloud Drive) или отправьте себе.")
                    .font(AW.caption).foregroundStyle(AW.textSecondary)
                if let d = settings.data.lastBackupAt {
                    Label("Последняя копия: \(d.formatted(date: .abbreviated, time: .shortened))", systemImage: "clock")
                } else {
                    Label("Копия ещё не создавалась", systemImage: "exclamationmark.triangle").foregroundStyle(AW.danger)
                }
            }
            Section("Создать") {
                Button { create(then: .share) } label: { Label("Создать копию и поделиться…", systemImage: "square.and.arrow.up") }
                Button { create(then: .files) } label: { Label("Создать и сохранить в «Файлы» / iCloud Drive", systemImage: "icloud.and.arrow.up") }
                Button { create(then: .none) } label: { Label("Создать копию в памяти приложения", systemImage: "externaldrive") }
            }
            Section("Восстановить") {
                Button { showImporter = true } label: { Label("Восстановить из файла…", systemImage: "arrow.down.doc") }
                Text("Восстановление объединяет данные: существующие вещи не удаляются и не дублируются; запись заменяется только если в копии она новее.")
                    .font(AW.caption).foregroundStyle(AW.textSecondary)
            }
            if !backups.isEmpty {
                Section("Копии на устройстве (Файлы → AmyWardrobe → Backups)") {
                    ForEach(backups, id: \.self) { url in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(url.lastPathComponent).font(.footnote)
                                Text(size(url)).font(AW.caption).foregroundStyle(AW.textSecondary)
                            }
                            Spacer()
                            Button { shareItem = IdentifiableURL(url: url) } label: { Image(systemName: "square.and.arrow.up") }.buttonStyle(.borderless)
                        }
                        .swipeActions { Button(role: .destructive) { try? FileManager.default.removeItem(at: url); reload() } label: { Label("Удалить", systemImage: "trash") } }
                    }
                }
            }
            if let status { Section { Text(status).font(AW.caption) } }
        }
        .scrollContentBackground(.hidden).awScreen()
        .navigationTitle("Резервные копии")
        .overlay { if working { ProgressView().controlSize(.large).padding(24).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
        .disabled(working)
        .onAppear(perform: reload)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.zip]) { result in inspect(result) }
        .sheet(item: $shareItem) { ShareSheet(items: [$0.url]) }
        .sheet(item: $filesItem) { FileExportPicker(url: $0.url) }
        .confirmationDialog("Восстановить из копии?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                            titleVisibility: .visible, presenting: pending) { p in
            Button("Восстановить (с настройками)") { restore(p, withSettings: true) }
            Button("Восстановить только данные") { restore(p, withSettings: false) }
            Button("Отмена", role: .cancel) { pending = nil }
        } message: { p in Text("Копия проверена. " + p.inspection.summary) }
        .appAlert($alert)
    }

    private enum After { case share, files, none }

    private func create(then after: After) {
        working = true
        Task {
            defer { working = false }
            do {
                let payload = try BackupService.makePayload(context: context, settings: settings.data)
                let dir = BackupService.backupsDirectory()
                let url = try await Task.detached(priority: .userInitiated) {
                    try BackupService.writeArchive(payload: payload, store: .shared, to: dir)
                }.value
                settings.data.lastBackupAt = Date()
                status = "Создано: \(url.lastPathComponent) (\(size(url)))"
                reload()
                switch after {
                case .share: shareItem = IdentifiableURL(url: url)
                case .files: filesItem = IdentifiableURL(url: url)
                case .none: break
                }
            } catch { alert = AppAlert(error: error, title: "Не удалось создать копию") }
        }
    }

    private func inspect(_ result: Result<URL, Error>) {
        working = true
        Task {
            defer { working = false }
            do {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                // копируем во временный файл, чтобы не зависеть от security-scoped доступа
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("restore-\(UUID().uuidString).zip")
                try FileManager.default.copyItem(at: url, to: tmp)
                let inspection = try await Task.detached(priority: .userInitiated) { try BackupService.inspect(archive: tmp) }.value
                pending = PendingRestore(inspection: inspection)
            } catch { alert = AppAlert(error: error, title: "Копия не прошла проверку") }
        }
    }

    private func restore(_ p: PendingRestore, withSettings: Bool) {
        do {
            let report = try BackupService.restore(p.inspection, into: context, store: .shared, settings: settings, restoreSettings: withSettings)
            ImageCache.shared.removeAll()
            var msg = report.summary
            if !report.warnings.isEmpty { msg += "\n\nПредупреждения:\n" + report.warnings.prefix(5).joined(separator: "\n") }
            alert = AppAlert(title: "Восстановление завершено", message: msg)
        } catch { alert = AppAlert(error: error, title: "Не удалось восстановить") }
        pending = nil
    }

    private func reload() {
        let dir = BackupService.backupsDirectory()
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        backups = urls.filter { $0.pathExtension == "zip" && !$0.lastPathComponent.hasPrefix(".") }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    private func size(_ url: URL) -> String {
        let n = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
    }
}
