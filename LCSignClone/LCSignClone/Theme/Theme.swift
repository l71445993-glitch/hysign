import SwiftUI

enum Theme {
    /// 默认强调色；运行时可在设置里改 accentHex，主界面用 `.tint(Color(hex:))`
    static let accent = Color(hex: 0x0A84FF)
    static let success = Color(hex: 0x34C759)
    static let warning = Color(hex: 0xFF9500)
    static let danger = Color(hex: 0xFF3B30)
    static let card = Color(.secondarySystemBackground)
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
