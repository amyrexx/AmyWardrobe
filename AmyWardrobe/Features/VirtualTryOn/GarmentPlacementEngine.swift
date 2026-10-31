import Foundation
import UIKit

struct PlacementAdjustment: Equatable {
    var dx: Double = 0
    var dy: Double = 0
    var scale: Double = 1
    var rotation: Double = 0
}

/// Правила размещения вещей по зонам аватара. Для каждой категории — своя зона и слой (z).
enum GarmentPlacementEngine {
    struct Placement { let box: CGRect; let z: Int }

    static func zone(categoryID: String, subcategory: String, geometry g: AvatarGeometry) -> Placement {
        let sub = subcategory.lowercased()
        switch categoryID {
        case "outerwear":
            let bottom = (sub.contains("пальто") || sub.contains("плащ") || sub.contains("шуба")) ? g.kneeY - 20 : g.hipY + 70
            let half = g.shoulderHalf + 34
            return Placement(box: CGRect(x: g.cx - half, y: g.shoulderY - 14, width: half * 2, height: bottom - g.shoulderY + 14), z: 40)
        case "tops":
            let bottom = (sub.contains("топ") || sub.contains("боди")) ? g.waistY + 20 : g.waistY + 85
            let half = g.shoulderHalf + 22
            return Placement(box: CGRect(x: g.cx - half, y: g.shoulderY - 10, width: half * 2, height: bottom - g.shoulderY + 10), z: 30)
        case "bottoms":
            let half = g.hipHalf + 34
            let bottom: CGFloat
            if sub.contains("юбк") { bottom = g.kneeY + 20 } else if sub.contains("шорт") { bottom = g.crotchY + 90 } else { bottom = g.ankleY + 10 }
            return Placement(box: CGRect(x: g.cx - half, y: g.waistY - 14, width: half * 2, height: bottom - g.waistY + 14), z: 20)
        case "dresses":
            let half = g.hipHalf + 36
            let bottom = sub.contains("макси") ? g.ankleY : (sub.contains("мини") ? g.crotchY + 120 : g.kneeY + 40)
            return Placement(box: CGRect(x: g.cx - half, y: g.shoulderY - 10, width: half * 2, height: bottom - g.shoulderY + 10), z: 25)
        case "shoes":
            let half = g.hipHalf * 0.46 + 46
            return Placement(box: CGRect(x: g.cx - half, y: g.ankleY - 22, width: half * 2, height: g.footY - g.ankleY + 50), z: 10)
        case "bags":
            return Placement(box: CGRect(x: g.cx + g.hipHalf + 4, y: g.hipY - 10, width: 150, height: 150), z: 50)
        case "hats":
            return Placement(box: CGRect(x: g.cx - 100, y: 8, width: 200, height: 120), z: 60)
        case "scarves":
            return Placement(box: CGRect(x: g.cx - 76, y: g.chinY - 6, width: 152, height: 110), z: 45)
        case "jewelry":
            return Placement(box: CGRect(x: g.cx - 48, y: g.chinY + 18, width: 96, height: 96), z: 48)
        case "accessories":
            return Placement(box: CGRect(x: g.cx - 50, y: g.waistY - 20, width: 100, height: 70), z: 52)
        default:
            return Placement(box: CGRect(x: g.cx - 60, y: g.bustY - 20, width: 120, height: 120), z: 35)
        }
    }

    /// Вписывает изображение в зону с сохранением пропорций и применяет ручную коррекцию.
    static func place(imageSize: CGSize, categoryID: String, subcategory: String, geometry: AvatarGeometry,
                      adjustment: PlacementAdjustment) -> (rect: CGRect, rotation: Double, z: Int) {
        let p = zone(categoryID: categoryID, subcategory: subcategory, geometry: geometry)
        let iw = max(1, imageSize.width), ih = max(1, imageSize.height)
        let fit = min(p.box.width / iw, p.box.height / ih) * CGFloat(adjustment.scale)
        let w = iw * fit, h = ih * fit
        let cx = p.box.midX + CGFloat(adjustment.dx)
        let cy = p.box.midY + CGFloat(adjustment.dy)
        return (CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h), adjustment.rotation, p.z)
    }
}
