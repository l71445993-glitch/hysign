import Foundation
import SwiftUI
import UIKit

@MainActor
final class SettingsStore: ObservableObject {
    @Published var selectedTab: AppTab = .projects
    @Published var accentHex: UInt = 0x0A84FF
    @Published var demoMode = true
    @Published var autoInject = false
    @Published var keepAwakeWhileSigning = true

    var udidText: String {
        // 真机 + 私有权限可读 MobileGestalt；学习版用标识符占位。
        UIDevice.current.identifierForVendor?.uuidString ?? "unknown-udid"
    }

    var engineLabel: String { "华阳签 Inject 1.0" }
}
