import UIKit
import SwiftUI

/// Ограниченный по количеству и памяти кеш декодированных миниатюр.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, UIImage>()

    init() {
        cache.countLimit = 500
        cache.totalCostLimit = 96 * 1024 * 1024
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                               object: nil, queue: nil) { [weak self] _ in
            self?.cache.removeAllObjects()
        }
    }

    func image(for key: String) -> UIImage? { cache.object(forKey: key as NSString) }

    func set(_ image: UIImage, for key: String) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }

    func removeAll() { cache.removeAllObjects() }
}

/// Ленивая загрузка изображения из хранилища с кешем. Декодирование — вне главного потока.
struct StoreImage: View {
    let fileName: String?
    var maxPixel: Int = ImageStore.thumbPixel
    var contentMode: ContentMode = .fit
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else if failed || fileName == nil {
                Image(systemName: "photo").font(.title2).foregroundStyle(AW.textSecondary.opacity(0.6))
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: fileName) { await load() }
    }

    @MainActor
    private func load() async {
        guard let name = fileName else { image = nil; failed = true; return }
        let key = "\(name)@\(maxPixel)"
        if let cached = ImageCache.shared.image(for: key) { image = cached; failed = false; return }
        image = nil
        let px = maxPixel
        let result = await Task.detached(priority: .utility) {
            ImageStore.shared.displayImage(fileName: name, maxPixel: px)
        }.value
        if Task.isCancelled { return }
        if let result {
            ImageCache.shared.set(result, for: key)
            image = result; failed = false
        } else {
            failed = true
        }
    }
}
