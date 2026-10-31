import SwiftUI
import UIKit

extension UIColor {
    convenience init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased()
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        var a: CGFloat = 1
        var r: CGFloat, g: CGFloat, b: CGFloat
        if s.count == 8 {
            a = CGFloat((v >> 24) & 0xFF) / 255
            r = CGFloat((v >> 16) & 0xFF) / 255
            g = CGFloat((v >> 8) & 0xFF) / 255
            b = CGFloat(v & 0xFF) / 255
        } else {
            r = CGFloat((v >> 16) & 0xFF) / 255
            g = CGFloat((v >> 8) & 0xFF) / 255
            b = CGFloat(v & 0xFF) / 255
        }
        self.init(red: r, green: g, blue: b, alpha: a)
    }

    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    var hsb: (h: CGFloat, s: CGFloat, b: CGFloat) {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return (h, s, b)
    }

    static func dynamic(light: String, dark: String) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) }
    }
}

extension Color {
    init(hex: String) { self.init(uiColor: UIColor(hex: hex)) }
    var hexString: String { UIColor(self).hexString }
    static func dynamic(light: String, dark: String) -> Color { Color(uiColor: UIColor.dynamic(light: light, dark: dark)) }
}

/// Дизайн-система AmyWardrobe: Lavender Aesthetic + современный минимализм.
/// Токены адаптивны (светлая/тёмная тема). Значения скорректированы по контрастности (WCAG, расчётно):
/// белый текст на Primary Dark ≈ 5.7:1; Text Secondary затемнён до #6D6378 (≈ 5:1 на лавандовом фоне).
enum AW {
    static let primary = Color.dynamic(light: "#9B7AD8", dark: "#B79BEA")
    static let primaryDark = Color.dynamic(light: "#7553B8", dark: "#8E6BD6")
    static let background = Color.dynamic(light: "#F5F0FC", dark: "#17131E")
    static let card = Color.dynamic(light: "#FFFFFF", dark: "#241E2E")
    static let pink = Color.dynamic(light: "#F4E5F0", dark: "#3A2A39")
    static let textPrimary = Color.dynamic(light: "#30283A", dark: "#F3EEF9")
    static let textSecondary = Color.dynamic(light: "#6D6378", dark: "#B5ABC2")
    static let divider = Color.dynamic(light: "#E8E0F0", dark: "#3A3247")
    static let danger = Color.dynamic(light: "#B3384A", dark: "#F08A98")

    static let corner: CGFloat = 20
    static let spacing: CGFloat = 16

    static let title = Font.system(.largeTitle, design: .rounded).weight(.bold)
    static let heading = Font.system(.title3, design: .rounded).weight(.semibold)
    static let body = Font.system(.body, design: .rounded)
    static let caption = Font.system(.caption, design: .rounded)
}

struct CardModifier: ViewModifier {
    var padding: CGFloat = 0
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(AW.card, in: RoundedRectangle(cornerRadius: AW.corner, style: .continuous))
            .shadow(color: AW.primaryDark.opacity(0.08), radius: 10, x: 0, y: 4)
    }
}

extension View {
    func awCard(padding: CGFloat = 0) -> some View { modifier(CardModifier(padding: padding)) }
    func awScreen() -> some View { self.background(AW.background.ignoresSafeArea()) }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded).weight(.semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 14).padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .background(AW.primaryDark.opacity(enabled ? 1 : 0.4), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded).weight(.semibold))
            .foregroundStyle(AW.primaryDark)
            .padding(.vertical, 12).padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(AW.pink, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct AWChip: View {
    let title: String
    var icon: String? = nil
    var selected = false
    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.caption) }
            Text(title).font(.system(.subheadline, design: .rounded).weight(.medium))
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .foregroundStyle(selected ? Color.white : AW.textPrimary)
        .background(selected ? AW.primaryDark : AW.card, in: Capsule())
        .overlay(Capsule().stroke(selected ? Color.clear : AW.divider, lineWidth: 1))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct SectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        HStack {
            Text(title).font(AW.heading).foregroundStyle(AW.textPrimary)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(AW.primaryDark)
            }
        }
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(AW.pink).frame(width: 96, height: 96)
                Image(systemName: icon).font(.system(size: 38)).foregroundStyle(AW.primaryDark)
            }
            Text(title).font(AW.heading).foregroundStyle(AW.textPrimary).multilineTextAlignment(.center)
            Text(message).font(AW.body).foregroundStyle(AW.textSecondary).multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(PrimaryButtonStyle()).padding(.top, 4).frame(maxWidth: 260)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}

struct FavoriteBadge: View {
    let isFavorite: Bool
    var body: some View {
        Image(systemName: isFavorite ? "heart.fill" : "heart")
            .font(.footnote)
            .foregroundStyle(isFavorite ? AW.primaryDark : AW.textSecondary)
            .padding(7)
            .background(.ultraThinMaterial, in: Circle())
            .accessibilityLabel(isFavorite ? "В избранном" : "Не в избранном")
    }
}

/// Простая «флюидная» раскладка чипов.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, totalW: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > maxW, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
            totalW = max(totalW, x - spacing)
        }
        return CGSize(width: totalW, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.width, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), proposal: .unspecified)
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}

/// Редактор тегов: ввод + удаляемые чипы.
struct TagEditor: View {
    @Binding var tags: [String]
    var suggestions: [String] = []
    @State private var input = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Новый тег", text: $input).textInputAutocapitalization(.never).onSubmit(add)
                Button("Добавить", action: add).disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if !tags.isEmpty {
                FlowLayout {
                    ForEach(tags, id: \.self) { t in
                        Button { tags.removeAll { $0 == t } } label: {
                            HStack(spacing: 4) { Text("#\(t)"); Image(systemName: "xmark.circle.fill").font(.caption) }
                                .font(.system(.subheadline, design: .rounded))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(AW.pink, in: Capsule()).foregroundStyle(AW.primaryDark)
                        }
                        .accessibilityLabel("Удалить тег \(t)")
                    }
                }
            }
            let rest = suggestions.filter { !tags.contains($0) }.prefix(8)
            if !rest.isEmpty {
                FlowLayout {
                    ForEach(Array(rest), id: \.self) { s in
                        Button { tags.append(s) } label: { AWChip(title: "+ \(s)") }
                    }
                }
            }
        }
    }

    private func add() {
        let t = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "#", with: "")
        input = ""
        guard !t.isEmpty, !tags.contains(t) else { return }
        tags.append(t)
    }
}
