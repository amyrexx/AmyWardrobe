import Foundation
import UIKit
import SwiftData

struct TryOnGarmentPayload {
    let name: String
    let categoryID: String
    let imageData: Data
}

struct TryOnRequest {
    let avatarPNG: Data
    let garments: [TryOnGarmentPayload]
}

struct TryOnResult {
    let imageData: Data
    let providerID: String
    let createdAt: Date
    let durationSeconds: Double
}

enum TryOnAvailability: Equatable {
    case available
    case unavailable(reason: String)
}

/// Заменяемый интерфейс генеративной примерки. Основное приложение от него не зависит.
protocol VirtualTryOnProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    func availability() -> TryOnAvailability
    func generate(_ request: TryOnRequest, progress: @escaping @Sendable (Double) -> Void) async throws -> TryOnResult
}

/// Провайдер по умолчанию: честно сообщает, что генеративная модель не подключена.
struct UnavailableTryOnProvider: VirtualTryOnProvider {
    let id = "none"
    let displayName = "Не подключена"
    var reason = "Генеративная модель не подключена. Укажите адрес собственного сервера в Профиль → Аватар и примерка."
    func availability() -> TryOnAvailability { .unavailable(reason: reason) }
    func generate(_ request: TryOnRequest, progress: @escaping @Sendable (Double) -> Void) async throws -> TryOnResult {
        throw AppError.tryOnUnavailable(reason)
    }
}

/// Клиент к пользовательскому серверу примерки (см. docs/VIRTUAL_TRYON.md): multipart POST → изображение.
/// Секретных ключей в приложении нет; адрес задаёт пользователь. Не проверялся с реальной моделью.
struct HTTPTryOnProvider: VirtualTryOnProvider {
    let endpoint: URL
    var timeout: TimeInterval = 240
    var session: URLSession = .shared
    var id: String { "http" }
    var displayName: String { "Собственный сервер (\(endpoint.host ?? "?"))" }

    func availability() -> TryOnAvailability { .available }

    func generate(_ request: TryOnRequest, progress: @escaping @Sendable (Double) -> Void) async throws -> TryOnResult {
        let started = Date()
        progress(0)
        var parts: [MultipartBody.Part] = [
            .file(name: "avatar", filename: "avatar.png", mime: "image/png", data: request.avatarPNG),
            .field(name: "categories", value: request.garments.map(\.categoryID).joined(separator: ","))
        ]
        for (i, g) in request.garments.enumerated() {
            parts.append(.file(name: "garment_\(i)", filename: "garment_\(i).png", mime: "image/png", data: g.imageData))
        }
        let body = MultipartBody.build(parts)
        var req = URLRequest(url: endpoint, timeoutInterval: timeout)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(body.boundary)", forHTTPHeaderField: "Content-Type")
        do {
            let (data, resp) = try await session.upload(for: req, from: body.data)
            guard let http = resp as? HTTPURLResponse else { throw AppError.tryOnFailed("неверный ответ сервера") }
            guard (200..<300).contains(http.statusCode) else { throw AppError.tryOnFailed("сервер вернул код \(http.statusCode)") }
            guard UIImage(data: data) != nil else { throw AppError.tryOnFailed("сервер вернул не изображение") }
            progress(1)
            return TryOnResult(imageData: data, providerID: id, createdAt: Date(), durationSeconds: Date().timeIntervalSince(started))
        } catch let e as AppError {
            throw e
        } catch let e as URLError where e.code == .timedOut {
            throw AppError.tryOnTimeout
        } catch let e as URLError where e.code == .cancelled {
            throw AppError.cancelled
        } catch is CancellationError {
            throw AppError.cancelled
        } catch {
            throw AppError.tryOnFailed(error.localizedDescription)
        }
    }
}

enum MultipartBody {
    enum Part {
        case field(name: String, value: String)
        case file(name: String, filename: String, mime: String, data: Data)
    }
    static func build(_ parts: [Part], boundary: String = "AW-" + UUID().uuidString) -> (data: Data, boundary: String) {
        var d = Data()
        func add(_ s: String) { d.append(Data(s.utf8)) }
        for p in parts {
            add("--\(boundary)\r\n")
            switch p {
            case .field(let n, let v):
                add("Content-Disposition: form-data; name=\"\(n)\"\r\n\r\n\(v)\r\n")
            case .file(let n, let f, let m, let data):
                add("Content-Disposition: form-data; name=\"\(n)\"; filename=\"\(f)\"\r\nContent-Type: \(m)\r\n\r\n")
                d.append(data); add("\r\n")
            }
        }
        add("--\(boundary)--\r\n")
        return (d, boundary)
    }
}

enum TryOnProviderFactory {
    @MainActor
    static func make(settings: SettingsData) -> any VirtualTryOnProvider {
        let s = settings.tryOnEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard settings.tryOnEnabled, let url = URL(string: s), let scheme = url.scheme, ["http", "https"].contains(scheme), url.host != nil else {
            return UnavailableTryOnProvider()
        }
        return HTTPTryOnProvider(endpoint: url)
    }
}

/// Состояние генерации. Основной интерфейс не блокируется: операция выполняется в отдельной Task и отменяема.
@MainActor
final class TryOnGenerationController: ObservableObject {
    enum State: Equatable {
        case idle
        case running(since: Date)
        case failed(String)
        case succeeded(Data)
    }
    @Published private(set) var state: State = .idle
    private var task: Task<Void, Never>?
    private var provider: any VirtualTryOnProvider

    init(provider: any VirtualTryOnProvider) { self.provider = provider }

    /// Подключает актуального провайдера (настройки могли измениться после создания экрана).
    func attach(provider: any VirtualTryOnProvider) { self.provider = provider }

    var providerName: String { provider.displayName }
    var availability: TryOnAvailability { provider.availability() }

    func start(_ request: TryOnRequest) {
        guard case .available = provider.availability() else {
            if case .unavailable(let r) = provider.availability() { state = .failed(AppError.tryOnUnavailable(r).errorDescription ?? r) }
            return
        }
        task?.cancel()
        state = .running(since: Date())
        let provider = self.provider
        task = Task { [weak self] in
            do {
                let result = try await provider.generate(request) { _ in }
                try Task.checkCancellation()
                self?.state = .succeeded(result.imageData)   // результат сохраняется только после успеха
            } catch is CancellationError {
                self?.state = .idle
            } catch {
                if let e = error as? AppError, e == .cancelled { self?.state = .idle; return }
                self?.state = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    func cancel() { task?.cancel(); state = .idle }
    func reset() { task?.cancel(); state = .idle }
}

/// Репозиторий истории примерок.
enum TryOnRepository {
    @MainActor
    @discardableResult
    static func save(imageData: Data, mode: String, outfit: Outfit?, context: ModelContext, store: ImageStore = .shared) throws -> TryOnRecord {
        let file = try store.save(data: imageData)
        let rec = TryOnRecord(imageFile: file, modeRaw: mode, outfitID: outfit?.id)
        context.insert(rec)
        if let outfit { outfit.tryOnFile = file; outfit.updatedAt = Date() }
        do { try context.save() } catch { context.rollback(); throw error }
        return rec
    }
}
