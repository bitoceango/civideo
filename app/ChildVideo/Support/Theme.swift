import SwiftUI

// 深色影院风配色 —— 由网页原型的 oklch tokens 转换为近似 sRGB
enum Theme {
    static let bg       = Color(hex: 0x15171C)
    static let bg2      = Color(hex: 0x1B1E25)
    static let card     = Color(hex: 0x22262E)
    static let cardHi   = Color(hex: 0x2A2F38)
    static let line     = Color(hex: 0x333944)
    static let text     = Color(hex: 0xF2F3F5)
    static let muted    = Color(hex: 0xA6AAB2)
    static let faint    = Color(hex: 0x7E828A)
    static let accent   = Color(hex: 0x36B4C9)
    static let accentHi = Color(hex: 0x53CFE0)
    static let good     = Color(hex: 0x3CCB7F)
    static let warn     = Color(hex: 0xE0A93C)
    static let onAccent = Color(hex: 0x132026)

    static let radius: CGFloat = 20

    // CJK 阅读行距更舒展
    static func cjkBody(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

// 确定性封面渐变（真实封面图加载前的占位 / 兜底）
extension LinearGradient {
    static func poster(seed: String) -> LinearGradient {
        var h: UInt64 = 1469598103934665603
        for b in seed.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        let hue = Double(h % 360) / 360.0
        let hue2 = (hue + 0.1).truncatingRemainder(dividingBy: 1)
        return LinearGradient(
            colors: [
                Color(hue: hue, saturation: 0.55, brightness: 0.52),
                Color(hue: (hue + hue2) / 2, saturation: 0.45, brightness: 0.34),
                Color(hue: hue2, saturation: 0.40, brightness: 0.24),
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
}
