import SwiftUI

enum Theme {
    /// LCSign 偏系统蓝；学习版用可配置强调色，默认 #0A84FF
    static var accent: Color { Color(hex: SettingsStore.sharedAccentHex) }
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
