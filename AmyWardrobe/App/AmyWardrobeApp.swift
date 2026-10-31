import SwiftUI
import SwiftData

@main
struct AmyWardrobeApp: App {
    @StateObject private var settings = AppSettings()
    private let container: ModelContainer?
    private let startupError: String?

    init() {
        do {
            container = try PersistenceController.makeContainer()
            startupError = nil
        } catch {
            container = nil
            startupError = error.localizedDescription
        }
        UITabBar.appearance().backgroundColor = UIColor(AW.card)
    }

    var body: some Scene {
        WindowGroup {
            if let container {
                RootTabView()
                    .modelContainer(container)
                    .environmentObject(settings)
                    .tint(AW.primaryDark)
            } else {
                StartupErrorView(message: startupError ?? "Неизвестная ошибка")
            }
        }
    }
}

/// Если база не открылась, данные НЕ удаляются автоматически — пользователю показывается объяснение.
struct StartupErrorView: View {
    let message: String
    var body: some View {
        EmptyStateView(icon: "exclamationmark.triangle", title: "Не удалось открыть данные",
                       message: "Ваши файлы не удалены. Закройте приложение и запустите заново; если ошибка повторяется, переустановите ту же сборку поверх (без удаления) или восстановите резервную копию.\n\nТехнические детали: \(message)")
            .awScreen()
    }
}
