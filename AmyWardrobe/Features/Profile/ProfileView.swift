import SwiftUI
import SwiftData

struct ProfileView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.modelContext) private var context
    @Query private var items: [WardrobeItem]
    @Query private var collages: [CollageProject]
    @Query private var outfits: [Outfit]
    @State private var alert: AppAlert?

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        ZStack { Circle().fill(AW.pink).frame(width: 56, height: 56); Image(systemName: "person.fill").foregroundStyle(AW.primaryDark) }
                        VStack(alignment: .leading) {
                            TextField("Ваше имя", text: $settings.data.userName).font(.system(.title3, design: .rounded).weight(.semibold))
                            Text("Вещей: \(items.count) · коллажей: \(collages.count) · образов: \(outfits.count)").font(AW.caption).foregroundStyle(AW.textSecondary)
                        }
                    }
                }
                Section("Данные") {
                    NavigationLink { BackupView() } label: { Label("Резервные копии и восстановление", systemImage: "externaldrive.badge.icloud") }
                    NavigationLink { AvatarSettingsView() } label: { Label("Аватар и мерки", systemImage: "figure.stand.dress") }
                    NavigationLink { TryOnSettingsView() } label: { Label("ИИ-примерка (экспериментально)", systemImage: "wand.and.stars") }
                }
                Section("Экспорт") {
                    Toggle("Экспорт в JPEG (по умолчанию PNG)", isOn: $settings.data.exportAsJPEG).tint(AW.primaryDark)
                }
                Section("Уведомления") {
                    Label("Появятся в будущих версиях", systemImage: "bell.slash").foregroundStyle(AW.textSecondary)
                }
                Section("Хранилище") {
                    Button("Очистить неиспользуемые изображения") {
                        let n = GarbageCollector.run(context: context, grace: 0)
                        alert = AppAlert(title: "Готово", message: n == 0 ? "Неиспользуемых файлов не найдено." : "Удалено файлов: \(n).")
                    }
                }
                Section("О приложении") {
                    LabeledContent("Версия", value: version)
                    NavigationLink("Лицензии и технологии") { LicensesView() }
                    Text("Все данные хранятся локально на устройстве. Аккаунты, сервер и подписка не требуются.").font(AW.caption).foregroundStyle(AW.textSecondary)
                }
            }
            .scrollContentBackground(.hidden).awScreen()
            .navigationTitle("Профиль")
            .appAlert($alert)
        }
    }
}

struct TryOnSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    var body: some View {
        Form {
            Section {
                Text("В приложении нет встроенной генеративной модели. Режим «ИИ-примерка» работает только если вы сами развернули сервер по протоколу из docs/VIRTUAL_TRYON.md (нужен GPU) и указали его адрес. Без этого доступна «Композиция на аватаре».")
                    .font(AW.caption).foregroundStyle(AW.textSecondary)
            }
            Section("Свой сервер") {
                Toggle("Включить", isOn: $settings.data.tryOnEnabled).tint(AW.primaryDark)
                TextField("https://адрес-сервера/tryon", text: $settings.data.tryOnEndpoint)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                Text("Изображения вашего аватара и вещей отправляются на указанный сервер. Не указывайте чужие серверы, которым не доверяете.")
                    .font(AW.caption).foregroundStyle(AW.textSecondary)
            }
        }
        .scrollContentBackground(.hidden).awScreen().navigationTitle("ИИ-примерка")
    }
}

struct LicensesView: View {
    var body: some View {
        List {
            Section("Зависимости") {
                Text("Сторонние библиотеки в приложении не используются. Только системные фреймворки Apple: SwiftUI, SwiftData, Core Graphics, ImageIO, PhotosUI, CryptoKit.")
            }
            Section("Шрифты") {
                Text("Используются только системные шрифты iOS (SF, New York, Georgia, Didot, Snell Roundhand, Avenir Next, Marker Felt) — отдельные лицензии не требуются.")
            }
            Section("Модели ИИ") {
                Text("Генеративные модели в приложение не встроены. Подключаемые пользователем модели имеют собственные лицензии (см. docs/VIRTUAL_TRYON.md).")
            }
            Section("Генерация IPA") {
                Text("Сборка проекта выполняется с помощью XcodeGen (MIT) в GitHub Actions; в приложение XcodeGen не входит.")
            }
        }
        .navigationTitle("Лицензии")
    }
}
