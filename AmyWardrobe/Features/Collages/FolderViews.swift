import SwiftUI
import SwiftData

/// Управление папками (создание, переименование, удаление). Удаление папки не удаляет содержимое.
struct FolderManagerView: View {
    let kind: FolderKind
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Folder.name) private var all: [Folder]
    @State private var newName = ""
    @State private var renaming: Folder?
    @State private var renameText = ""
    @State private var alert: AppAlert?

    private var folders: [Folder] { all.filter { $0.kind == kind } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Новая папка", text: $newName).onSubmit(add)
                        Button("Создать", action: add).disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                Section {
                    if folders.isEmpty { Text("Папок пока нет").foregroundStyle(AW.textSecondary) }
                    ForEach(folders) { f in
                        Text(f.name)
                            .swipeActions {
                                Button(role: .destructive) { delete(f) } label: { Label("Удалить", systemImage: "trash") }
                                Button { renameText = f.name; renaming = f } label: { Label("Переименовать", systemImage: "pencil") }.tint(AW.primary)
                            }
                    }
                } footer: { Text("При удалении папки её содержимое не удаляется — оно переносится в общий список.") }
            }
            .navigationTitle("Папки").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
            .alert("Переименовать папку", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Название", text: $renameText)
                Button("Сохранить") { renaming?.name = renameText; renaming?.updatedAt = Date(); try? context.save(); renaming = nil }
                Button("Отмена", role: .cancel) { renaming = nil }
            }
            .appAlert($alert)
        }
        .presentationDetents([.medium, .large])
    }

    private func add() {
        let n = newName.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        context.insert(Folder(name: n, kind: kind))
        do { try context.save() } catch { context.rollback(); alert = AppAlert(error: error) }
        newName = ""
    }

    private func delete(_ f: Folder) {
        do { try FolderService.delete(f, context: context) } catch { alert = AppAlert(error: error) }
    }
}

/// Выбор папки и тегов для коллажа или образа.
struct OrganizeSheet: View {
    let title: String
    @Binding var tags: [String]
    @Binding var folderID: UUID?
    let kind: FolderKind
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Folder.name) private var all: [Folder]
    private var folders: [Folder] { all.filter { $0.kind == kind } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Папка") {
                    Picker("Папка", selection: $folderID) {
                        Text("Без папки").tag(UUID?.none)
                        ForEach(folders) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
                Section("Теги") { TagEditor(tags: $tags) }
            }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
