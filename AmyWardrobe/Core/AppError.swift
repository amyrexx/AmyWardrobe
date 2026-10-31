import Foundation
import SwiftUI

/// Единый тип ошибок приложения с русскоязычными сообщениями.
enum AppError: LocalizedError, Equatable {
    case imageDecodeFailed
    case fileReadFailed(String)
    case fileWriteFailed(String)
    case diskFull
    case missingImage(String)
    case backupCorrupt(String)
    case backupUnsupportedVersion(Int)
    case exportFailed(String)
    case permissionDenied(String)
    case tryOnUnavailable(String)
    case tryOnFailed(String)
    case tryOnTimeout
    case cancelled
    case validation(String)

    var errorDescription: String? {
        switch self {
        case .imageDecodeFailed:
            return "Не удалось прочитать изображение. Выберите другой файл (поддерживаются PNG, JPEG, HEIC)."
        case .fileReadFailed(let m): return "Ошибка чтения файла: \(m)"
        case .fileWriteFailed(let m): return "Ошибка записи файла: \(m)"
        case .diskFull: return "Недостаточно свободного места на устройстве. Освободите память и повторите."
        case .missingImage(let n): return "Файл изображения не найден: \(n)"
        case .backupCorrupt(let m): return "Резервная копия повреждена или имеет неверный формат: \(m)"
        case .backupUnsupportedVersion(let v):
            return "Версия формата резервной копии (\(v)) не поддерживается этой версией приложения. Обновите приложение."
        case .exportFailed(let m): return "Не удалось экспортировать: \(m)"
        case .permissionDenied(let m): return m
        case .tryOnUnavailable(let m): return "ИИ-примерка недоступна: \(m)"
        case .tryOnFailed(let m): return "Не удалось выполнить ИИ-примерку: \(m)"
        case .tryOnTimeout: return "Сервер примерки не ответил вовремя. Попробуйте ещё раз."
        case .cancelled: return "Действие отменено."
        case .validation(let m): return m
        }
    }
}

/// Данные для показа системного алерта.
struct AppAlert: Identifiable {
    let id = UUID()
    var title: String
    var message: String

    init(title: String, message: String) {
        self.title = title
        self.message = message
    }

    init(error: Error, title: String = "Что-то пошло не так") {
        self.title = title
        self.message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

extension View {
    func appAlert(_ alert: Binding<AppAlert?>) -> some View {
        self.alert(
            alert.wrappedValue?.title ?? "",
            isPresented: Binding(
                get: { alert.wrappedValue != nil },
                set: { if !$0 { alert.wrappedValue = nil } }
            ),
            presenting: alert.wrappedValue
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { a in
            Text(a.message)
        }
    }
}
