import SwiftUI

@main
struct HuaYangSignApp: App {
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(app)
                .tint(Color(hex: app.settings.accentHex))
        }
    }
}

/// 全局状态：对齐 LCSign 的 Store 聚合方式。
@MainActor
final class AppState: ObservableObject {
    let projects: ProjectStore
    let certificates: CertificateStore
    let outputs: OutputStore
    let sources: SourceStore
    let signing: SigningEngine
    let injector: InjectorService
    let installer: LocalInstallServer
    /// 需为 var，SwiftUI 才能通过 `$app.settings.xxx` 生成 Binding
    var settings: SettingsStore

    init() {
        let certs = CertificateStore()
        let projects = ProjectStore()
        let outputs = OutputStore()
        let injector = InjectorService()
        let settings = SettingsStore()

        self.certificates = certs
        self.projects = projects
        self.outputs = outputs
        self.sources = SourceStore()
        self.injector = injector
        self.settings = settings
        self.installer = LocalInstallServer()
        let engine = SigningEngine(
            certificates: certs,
            projects: projects,
            outputs: outputs,
            injector: injector
        )
        engine.preferRealZsign = !settings.demoMode
        self.signing = engine
    }
}
