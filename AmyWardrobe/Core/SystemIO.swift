import SwiftUI
import UIKit
import Photos
import AVFoundation
import UniformTypeIdentifiers

/// Сохранение в «Фото» с корректной обработкой разрешений. Сохраняет байты как есть (PNG сохраняет прозрачность).
enum PhotoSaver {
    static func save(data: Data) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw AppError.permissionDenied("Нет разрешения на добавление в «Фото». Откройте Настройки → AmyWardrobe → Фото и разрешите добавление.")
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            }
        } catch {
            throw AppError.exportFailed(error.localizedDescription)
        }
    }
}

enum CameraAccess {
    static var isCameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    /// true — можно открывать камеру; false — доступ запрещён.
    static func ensureAuthorized() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }
}

struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

/// «Сохранить в Файлы» (в т.ч. iCloud Drive) через системный выбор папки.
struct FileExportPicker: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        UIDocumentPickerViewController(forExporting: [url], asCopy: true)
    }
    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}
}

struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraPicker
        init(_ p: CameraPicker) { parent = p }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.onImage(img) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

/// Универсальное меню экспорта: «Фото», «Поделиться», «Файлы». Рендер выполняется вне главного потока.
struct ExportMenu: View {
    let baseName: String
    let makeImage: @Sendable () -> UIImage?
    @EnvironmentObject private var settings: AppSettings
    @State private var busy = false
    @State private var alert: AppAlert?
    @State private var shareItem: IdentifiableURL?
    @State private var filesItem: IdentifiableURL?

    private enum Action { case photos, share, files }

    var body: some View {
        Menu {
            Button { run(.photos) } label: { Label("Сохранить в «Фото»", systemImage: "photo.on.rectangle") }
            Button { run(.share) } label: { Label("Поделиться…", systemImage: "square.and.arrow.up") }
            Button { run(.files) } label: { Label("Сохранить в «Файлы»", systemImage: "folder") }
        } label: {
            if busy { ProgressView() } else { Image(systemName: "square.and.arrow.up") }
        }
        .disabled(busy)
        .accessibilityLabel("Экспорт изображения")
        .sheet(item: $shareItem) { ShareSheet(items: [$0.url]) }
        .sheet(item: $filesItem) { FileExportPicker(url: $0.url) }
        .appAlert($alert)
    }

    private func run(_ action: Action) {
        busy = true
        let asJPEG = settings.data.exportAsJPEG
        let make = makeImage
        let name = baseName
        Task {
            let data: Data? = await Task.detached(priority: .userInitiated) {
                guard let img = make() else { return nil }
                return asJPEG ? img.jpegData(compressionQuality: 0.95) : img.pngData()
            }.value
            defer { busy = false }
            guard let data else {
                alert = AppAlert(title: "Экспорт не удался", message: "Не удалось подготовить изображение.")
                return
            }
            do {
                switch action {
                case .photos:
                    try await PhotoSaver.save(data: data)
                    alert = AppAlert(title: "Готово", message: "Изображение сохранено в «Фото».")
                case .share, .files:
                    let url = try Self.writeTemp(data: data, name: name, ext: asJPEG ? "jpg" : "png")
                    if action == .share { shareItem = IdentifiableURL(url: url) } else { filesItem = IdentifiableURL(url: url) }
                }
            } catch {
                alert = AppAlert(error: error, title: "Экспорт не удался")
            }
        }
    }

    static func writeTemp(data: Data, name: String, ext: String) throws -> URL {
        let safe = name.components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|")).joined(separator: "_")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe.isEmpty ? "AmyWardrobe" : safe).\(ext)")
        do { try data.write(to: url, options: .atomic) } catch { throw ImageStore.map(error) }
        return url
    }
}
