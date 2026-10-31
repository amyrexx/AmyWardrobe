import UIKit

/// Настоящий рендер документа коллажа средствами Core Graphics (не скриншот интерфейса).
/// Тот же код рисует превью, экспорт и слои текста/рамок для редактора, поэтому результат совпадает с тем, что видит пользователь.
enum CollageRenderer {

    // MARK: Документ целиком

    static func render(_ doc: CollageDocument, store: ImageStore, maxSide: CGFloat = 2160) -> UIImage {
        let w = CGFloat(doc.canvasWidth), h = CGFloat(doc.canvasHeight)
        let k = min(1, maxSide / max(w, h))
        let size = CGSize(width: max(1, (w * k).rounded()), height: max(1, (h * k).rounded()))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            cg.scaleBy(x: size.width / w, y: size.height / h)
            drawBackground(doc.background, in: CGRect(x: 0, y: 0, width: w, height: h), cg)
            var cache: [String: UIImage] = [:]
            for obj in doc.objects { draw(obj, store: store, in: cg, pixelScale: k, cache: &cache) }
        }
    }

    // MARK: Фон

    static func drawBackground(_ bg: CollageBackground, in rect: CGRect, _ cg: CGContext) {
        switch bg {
        case .solid(let hex):
            cg.setFillColor(UIColor(hex: hex).cgColor)
            cg.fill(rect)
        case .gradient(let top, let bottom):
            let colors = [UIColor(hex: top).cgColor, UIColor(hex: bottom).cgColor] as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                cg.drawLinearGradient(g, start: CGPoint(x: rect.midX, y: rect.minY), end: CGPoint(x: rect.midX, y: rect.maxY), options: [])
            }
        case .dots(let base, let dot):
            cg.setFillColor(UIColor(hex: base).cgColor)
            cg.fill(rect)
            cg.setFillColor(UIColor(hex: dot).withAlphaComponent(0.5).cgColor)
            let step: CGFloat = 54
            var y: CGFloat = step / 2
            while y < rect.height {
                var x: CGFloat = step / 2
                while x < rect.width {
                    cg.fillEllipse(in: CGRect(x: x - 4, y: y - 4, width: 8, height: 8))
                    x += step
                }
                y += step
            }
        }
    }

    // MARK: Объекты

    private static func draw(_ obj: CollageObject, store: ImageStore, in cg: CGContext, pixelScale: CGFloat, cache: inout [String: UIImage]) {
        let w = CGFloat(obj.width * obj.scale), h = CGFloat(obj.height * obj.scale)
        guard w > 0, h > 0 else { return }
        cg.saveGState()
        cg.translateBy(x: CGFloat(obj.centerX), y: CGFloat(obj.centerY))
        cg.rotate(by: CGFloat(obj.rotation))
        let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
        switch obj.kind {
        case .image:
            if obj.flippedX { cg.scaleBy(x: -1, y: 1) }
            drawImage(file: obj.imageFile, store: store, in: rect, pixelScale: pixelScale, cache: &cache)
        case .text:
            if let t = obj.text { drawText(t, scale: CGFloat(obj.scale), in: rect) }
        case .frame:
            if let f = obj.frame { drawFrame(f, scale: CGFloat(obj.scale), in: rect, cg) }
        }
        cg.restoreGState()
    }

    private static func drawImage(file: String?, store: ImageStore, in rect: CGRect, pixelScale: CGFloat, cache: inout [String: UIImage]) {
        let needed = Int(min(3000, max(64, max(rect.width, rect.height) * pixelScale * 1.25)))
        if let file {
            let key = "\(file)@\(needed / 256)"
            var img = cache[key]
            if img == nil { img = store.downsampledImage(fileName: file, maxPixel: needed); if let i = img { cache[key] = i } }
            if let img { img.draw(in: rect); return }
        }
        drawMissingPlaceholder(in: rect)
    }

    /// Пустая заглушка для отсутствующего файла: проект не ломается.
    static func drawMissingPlaceholder(in rect: CGRect) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: min(rect.width, rect.height) * 0.08)
        UIColor(hex: "#E8E0F0").setFill()
        path.fill()
        UIColor(hex: "#9B7AD8").withAlphaComponent(0.6).setStroke()
        path.lineWidth = max(2, rect.width * 0.01)
        path.setLineDash([10, 8], count: 2, phase: 0)
        path.stroke()
    }

    // MARK: Текст

    static func attributed(_ t: TextStyle, scale: CGFloat) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.alignment = t.alignment.ns
        para.lineBreakMode = .byWordWrapping
        return NSAttributedString(string: t.content, attributes: [
            .font: t.font.uiFont(size: CGFloat(t.fontSize) * scale),
            .foregroundColor: UIColor(hex: t.colorHex),
            .paragraphStyle: para
        ])
    }

    static func textHeight(_ t: TextStyle, width: CGFloat) -> CGFloat {
        let r = attributed(t, scale: 1).boundingRect(
            with: CGSize(width: max(10, width), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        return ceil(r.height) + 8
    }

    static func drawText(_ t: TextStyle, scale: CGFloat, in rect: CGRect) {
        attributed(t, scale: scale).draw(with: rect.insetBy(dx: 0, dy: 4 * scale),
                                         options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
    }

    // MARK: Рамки

    static func drawFrame(_ f: FrameStyle, scale: CGFloat, in rect: CGRect, _ cg: CGContext) {
        let lw = CGFloat(f.lineWidth) * scale
        let radius = min(CGFloat(f.cornerRadius) * scale, min(rect.width, rect.height) / 2)
        let color = UIColor(hex: f.colorHex)
        func path(_ inset: CGFloat) -> UIBezierPath {
            UIBezierPath(roundedRect: rect.insetBy(dx: inset, dy: inset), cornerRadius: max(0, radius - inset + lw / 2))
        }
        switch f.style {
        case .filled:
            color.withAlphaComponent(0.35).setFill()
            path(0).fill()
        case .solid:
            color.setStroke(); let p = path(lw / 2); p.lineWidth = lw; p.stroke()
        case .dashed:
            color.setStroke(); let p = path(lw / 2); p.lineWidth = lw
            p.setLineDash([lw * 2.2, lw * 1.6], count: 2, phase: 0); p.lineCapStyle = .round; p.stroke()
        case .double:
            color.setStroke()
            let outer = path(lw / 2); outer.lineWidth = lw / 2; outer.stroke()
            let inner = path(lw * 1.6); inner.lineWidth = lw / 2; inner.stroke()
        }
    }

    // MARK: Слои для редактора (SwiftUI показывает их как изображения, чтобы совпадать с экспортом)

    static func layerImage(for obj: CollageObject, renderScale: CGFloat) -> UIImage? {
        let w = CGFloat(obj.width), h = CGFloat(obj.height)
        guard w > 0, h > 0 else { return nil }
        let size = CGSize(width: w, height: h)
        let format = UIGraphicsImageRendererFormat()
        format.scale = max(0.25, min(renderScale, 3))
        format.opaque = false
        let rect = CGRect(origin: .zero, size: size)
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            switch obj.kind {
            case .text: if let t = obj.text { drawText(t, scale: 1, in: rect) }
            case .frame: if let f = obj.frame { drawFrame(f, scale: 1, in: rect, ctx.cgContext) }
            case .image: break
            }
        }
    }
}
