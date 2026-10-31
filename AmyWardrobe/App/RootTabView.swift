import SwiftUI
import SwiftData

struct RootTabView: View {
    @Environment(\.modelContext) private var context

    var body: some View {
        TabView {
            HomeView().tabItem { Label("Главная", systemImage: "house") }
            WardrobeView().tabItem { Label("Гардероб", systemImage: "tshirt") }
            CollagesView().tabItem { Label("Коллажи", systemImage: "square.on.square.dashed") }
            OutfitsView().tabItem { Label("Образы", systemImage: "sparkles") }
            ProfileView().tabItem { Label("Профиль", systemImage: "person") }
        }
        .task {
            // Отложенная уборка неиспользуемых файлов; свежие файлы (< 10 мин) не трогаются.
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            GarbageCollector.run(context: context)
        }
    }
}
