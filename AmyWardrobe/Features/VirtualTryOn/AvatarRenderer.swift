import UIKit

/// Геометрия аватара в условных единицах (холст 600×1240). Все зоны размещения одежды считаются отсюда.
struct AvatarGeometry {
    static let canvas = CGSize(width: 600, height: 1240)
    let cx: CGFloat = 300
    let headCenter = CGPoint(x: 300, y: 150)
    let headRX: CGFloat = 54, headRY: CGFloat = 64
    let chinY: CGFloat, shoulderY: CGFloat, bustY: CGFloat, waistY: CGFloat, hipY: CGFloat
    let crotchY: CGFloat, kneeY: CGFloat, ankleY: CGFloat, footY: CGFloat
    let shoulderHalf: CGFloat, bustHalf: CGFloat, waistHalf: CGFloat, hipHalf: CGFloat

    init(visual v: AvatarVisual) {
        func c(_ x: Double, _ lo: Double, _ hi: Double) -> CGFloat { CGFloat(min(hi, max(lo, x))) }
        let torso = c(v.torso, 0.9, 1.1), leg = c(v.leg, 0.9, 1.1)
        chinY = 216
        shoulderY = 255
        bustY = 255 + 85 * torso
        waistY = 255 + 190 * torso
        hipY = waistY + 80
        crotchY = hipY + 60
        let legLen = 500 * leg
        kneeY = crotchY + legLen * 0.5
        ankleY = crotchY + legLen
        footY = ankleY + 35
        shoulderHalf = 78 * c(v.shoulder, 0.85, 1.15)
        bustHalf = 66 * c(v.bust, 0.85, 1.15)
        waistHalf = 50 * c(v.waist, 0.85, 1.15)
        hipHalf = 76 * c(v.hip, 0.85, 1.15)
    }

    var legCenterLeft: CGFloat { cx - hipHalf * 0.46 }
    var legCenterRight: CGFloat { cx + hipHalf * 0.46 }
}

/// Базовый женский 2D-аватар в иллюстративном fashion/anime-стиле. Нарисован кодом (векторные пути),
/// это временная «заменяемая» графика: при желании можно подставить готовый арт, сохранив `AvatarGeometry`.
enum AvatarRenderer {
    static func drawBackLayer(_ g: AvatarGeometry, _ v: AvatarVisual, _ cg: CGContext) {
        // мягкая тень под ногами
        UIColor(hex: "#7553B8").withAlphaComponent(0.12).setFill()
        UIBezierPath(ovalIn: CGRect(x: g.cx - 120, y: g.footY - 12, width: 240, height: 28)).fill()
        // длинные волосы позади тела
        let hair = UIColor(hex: v.hairHex)
        hair.setFill()
        let p = UIBezierPath()
        p.move(to: CGPoint(x: g.cx - 70, y: 120))
        p.addCurve(to: CGPoint(x: g.cx - 96, y: 400), controlPoint1: CGPoint(x: g.cx - 100, y: 200), controlPoint2: CGPoint(x: g.cx - 110, y: 330))
        p.addQuadCurve(to: CGPoint(x: g.cx - 56, y: 520), controlPoint: CGPoint(x: g.cx - 90, y: 500))
        p.addLine(to: CGPoint(x: g.cx + 56, y: 520))
        p.addQuadCurve(to: CGPoint(x: g.cx + 96, y: 400), controlPoint: CGPoint(x: g.cx + 90, y: 500))
        p.addCurve(to: CGPoint(x: g.cx + 70, y: 120), controlPoint1: CGPoint(x: g.cx + 110, y: 330), controlPoint2: CGPoint(x: g.cx + 100, y: 200))
        p.addQuadCurve(to: CGPoint(x: g.cx - 70, y: 120), controlPoint: CGPoint(x: g.cx, y: 40))
        p.fill()
    }

    static func drawBody(_ g: AvatarGeometry, _ v: AvatarVisual, _ cg: CGContext) {
        let skin = UIColor(hex: v.skinHex)
        skin.setFill()
        // руки
        for side in [-1.0, 1.0] as [CGFloat] {
            let arm = UIBezierPath()
            let sx = g.cx + side * (g.shoulderHalf - 6)
            arm.move(to: CGPoint(x: sx, y: g.shoulderY + 14))
            arm.addLine(to: CGPoint(x: g.cx + side * (g.shoulderHalf + 16), y: g.waistY - 30))
            arm.addLine(to: CGPoint(x: g.cx + side * (g.shoulderHalf + 4), y: g.hipY + 60))
            arm.lineWidth = 24; arm.lineCapStyle = .round; arm.lineJoinStyle = .round
            skin.setStroke(); arm.stroke()
            UIBezierPath(ovalIn: CGRect(x: g.cx + side * (g.shoulderHalf + 4) - 13, y: g.hipY + 52, width: 26, height: 30)).fill()
        }
        // ноги
        for center in [g.legCenterLeft, g.legCenterRight] {
            let top = g.hipHalf * 0.5, knee = g.hipHalf * 0.34, ankle: CGFloat = 14
            let leg = UIBezierPath()
            leg.move(to: CGPoint(x: center - top, y: g.crotchY - 40))
            leg.addQuadCurve(to: CGPoint(x: center - knee, y: g.kneeY), controlPoint: CGPoint(x: center - top, y: (g.crotchY + g.kneeY) / 2))
            leg.addQuadCurve(to: CGPoint(x: center - ankle, y: g.ankleY), controlPoint: CGPoint(x: center - knee, y: (g.kneeY + g.ankleY) / 2 - 10))
            leg.addLine(to: CGPoint(x: center + ankle, y: g.ankleY))
            leg.addQuadCurve(to: CGPoint(x: center + knee, y: g.kneeY), controlPoint: CGPoint(x: center + knee, y: (g.kneeY + g.ankleY) / 2 - 10))
            leg.addQuadCurve(to: CGPoint(x: center + top, y: g.crotchY - 40), controlPoint: CGPoint(x: center + top, y: (g.crotchY + g.kneeY) / 2))
            leg.close(); leg.fill()
            UIBezierPath(ovalIn: CGRect(x: center - 20, y: g.ankleY - 4, width: 40, height: 40)).fill()
        }
        // шея и торс
        UIBezierPath(roundedRect: CGRect(x: g.cx - 20, y: g.chinY - 14, width: 40, height: 56), cornerRadius: 14).fill()
        let t = UIBezierPath()
        t.move(to: CGPoint(x: g.cx - g.shoulderHalf, y: g.shoulderY))
        t.addQuadCurve(to: CGPoint(x: g.cx - g.bustHalf, y: g.bustY), controlPoint: CGPoint(x: g.cx - g.shoulderHalf - 2, y: g.shoulderY + 45))
        t.addQuadCurve(to: CGPoint(x: g.cx - g.waistHalf, y: g.waistY), controlPoint: CGPoint(x: g.cx - g.waistHalf - 8, y: (g.bustY + g.waistY) / 2))
        t.addQuadCurve(to: CGPoint(x: g.cx - g.hipHalf, y: g.hipY), controlPoint: CGPoint(x: g.cx - g.hipHalf + 2, y: (g.waistY + g.hipY) / 2 + 6))
        t.addLine(to: CGPoint(x: g.cx - g.hipHalf * 0.9, y: g.crotchY))
        t.addLine(to: CGPoint(x: g.cx + g.hipHalf * 0.9, y: g.crotchY))
        t.addLine(to: CGPoint(x: g.cx + g.hipHalf, y: g.hipY))
        t.addQuadCurve(to: CGPoint(x: g.cx + g.waistHalf, y: g.waistY), controlPoint: CGPoint(x: g.cx + g.hipHalf - 2, y: (g.waistY + g.hipY) / 2 + 6))
        t.addQuadCurve(to: CGPoint(x: g.cx + g.bustHalf, y: g.bustY), controlPoint: CGPoint(x: g.cx + g.waistHalf + 8, y: (g.bustY + g.waistY) / 2))
        t.addQuadCurve(to: CGPoint(x: g.cx + g.shoulderHalf, y: g.shoulderY), controlPoint: CGPoint(x: g.cx + g.shoulderHalf + 2, y: g.shoulderY + 45))
        t.addQuadCurve(to: CGPoint(x: g.cx - g.shoulderHalf, y: g.shoulderY), controlPoint: CGPoint(x: g.cx, y: g.shoulderY - 14))
        t.close(); t.fill()
        // базовое бельё нейтрального цвета — силуэт без анатомических деталей
        UIColor(hex: "#EBDCE8").setFill()
        let base = UIBezierPath(roundedRect: CGRect(x: g.cx - g.hipHalf * 0.9, y: g.hipY - 8, width: g.hipHalf * 1.8, height: g.crotchY - g.hipY + 12), cornerRadius: 22)
        base.fill()
    }

    static func drawHead(_ g: AvatarGeometry, _ v: AvatarVisual, _ cg: CGContext) {
        let skin = UIColor(hex: v.skinHex)
        skin.setFill()
        UIBezierPath(ovalIn: CGRect(x: g.headCenter.x - g.headRX, y: g.headCenter.y - g.headRY, width: g.headRX * 2, height: g.headRY * 2)).fill()
        // щёки
        UIColor(hex: "#F4A6C1").withAlphaComponent(0.35).setFill()
        for s in [-1.0, 1.0] as [CGFloat] { UIBezierPath(ovalIn: CGRect(x: g.cx + s * 34 - 11, y: 180, width: 22, height: 12)).fill() }
        // глаза
        for s in [-1.0, 1.0] as [CGFloat] {
            let ex = g.cx + s * 24, ey: CGFloat = 160
            UIColor.white.setFill()
            UIBezierPath(ovalIn: CGRect(x: ex - 12, y: ey - 15, width: 24, height: 30)).fill()
            UIColor(hex: v.eyeHex).setFill()
            UIBezierPath(ovalIn: CGRect(x: ex - 9, y: ey - 12, width: 18, height: 26)).fill()
            UIColor(hex: "#2B2038").setFill()
            UIBezierPath(ovalIn: CGRect(x: ex - 4.5, y: ey - 5, width: 9, height: 14)).fill()
            UIColor.white.setFill()
            UIBezierPath(ovalIn: CGRect(x: ex + 1, y: ey - 10, width: 6, height: 6)).fill()
            let lash = UIBezierPath()
            lash.move(to: CGPoint(x: ex - 14, y: ey - 6))
            lash.addQuadCurve(to: CGPoint(x: ex + 14, y: ey - 6), controlPoint: CGPoint(x: ex, y: ey - 24))
            lash.lineWidth = 3.2; lash.lineCapStyle = .round
            UIColor(hex: "#2B2038").setStroke(); lash.stroke()
        }
        // нос и рот
        let nose = UIBezierPath(); nose.move(to: CGPoint(x: g.cx - 2, y: 184)); nose.addLine(to: CGPoint(x: g.cx + 1, y: 188))
        nose.lineWidth = 2; nose.lineCapStyle = .round; UIColor(hex: "#C9937F").setStroke(); nose.stroke()
        let mouth = UIBezierPath(); mouth.move(to: CGPoint(x: g.cx - 9, y: 200))
        mouth.addQuadCurve(to: CGPoint(x: g.cx + 9, y: 200), controlPoint: CGPoint(x: g.cx, y: 208))
        mouth.lineWidth = 2.6; mouth.lineCapStyle = .round; UIColor(hex: "#C9667F").setStroke(); mouth.stroke()
        // чёлка и боковые пряди
        let hair = UIColor(hex: v.hairHex)
        hair.setFill()
        let bangs = UIBezierPath()
        bangs.move(to: CGPoint(x: g.cx - 62, y: 162))
        bangs.addCurve(to: CGPoint(x: g.cx, y: 78), controlPoint1: CGPoint(x: g.cx - 70, y: 100), controlPoint2: CGPoint(x: g.cx - 40, y: 80))
        bangs.addCurve(to: CGPoint(x: g.cx + 62, y: 162), controlPoint1: CGPoint(x: g.cx + 40, y: 80), controlPoint2: CGPoint(x: g.cx + 70, y: 100))
        bangs.addQuadCurve(to: CGPoint(x: g.cx + 30, y: 130), controlPoint: CGPoint(x: g.cx + 54, y: 124))
        bangs.addQuadCurve(to: CGPoint(x: g.cx - 8, y: 124), controlPoint: CGPoint(x: g.cx + 12, y: 108))
        bangs.addQuadCurve(to: CGPoint(x: g.cx - 62, y: 162), controlPoint: CGPoint(x: g.cx - 38, y: 118))
        bangs.fill()
        UIColor.white.withAlphaComponent(0.18).setStroke()
        let shine = UIBezierPath(); shine.move(to: CGPoint(x: g.cx - 36, y: 100))
        shine.addQuadCurve(to: CGPoint(x: g.cx + 6, y: 94), controlPoint: CGPoint(x: g.cx - 14, y: 86))
        shine.lineWidth = 6; shine.lineCapStyle = .round; shine.stroke()
    }
}

/// Одежда, уже размещённая на холсте аватара.
struct PlacedGarment {
    var image: UIImage
    var rect: CGRect
    var rotation: Double
    var z: Int
}

enum TryOnCompositor {
    /// Рендерит композицию «аватар + наложенные PNG». Это НЕ генеративная ИИ-примерка.
    static func render(visual: AvatarVisual, garments: [PlacedGarment], width: CGFloat = 900, background: Bool = true) -> UIImage {
        let canvas = AvatarGeometry.canvas
        let k = width / canvas.width
        let size = CGSize(width: width, height: (canvas.height * k).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = background
        let g = AvatarGeometry(visual: visual)
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            if background {
                let colors = [UIColor(hex: "#F5F0FC").cgColor, UIColor(hex: "#F4E5F0").cgColor] as CFArray
                if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                    cg.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
                }
            }
            cg.scaleBy(x: k, y: k)
            AvatarRenderer.drawBackLayer(g, visual, cg)
            AvatarRenderer.drawBody(g, visual, cg)
            AvatarRenderer.drawHead(g, visual, cg)
            for p in garments.sorted(by: { $0.z < $1.z }) {
                cg.saveGState()
                cg.translateBy(x: p.rect.midX, y: p.rect.midY)
                cg.rotate(by: CGFloat(p.rotation))
                p.image.draw(in: CGRect(x: -p.rect.width / 2, y: -p.rect.height / 2, width: p.rect.width, height: p.rect.height))
                cg.restoreGState()
            }
        }
    }
}
