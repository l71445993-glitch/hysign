import Foundation

/// 一次「签名并安装」任务的步骤 —— 对齐 zsign / LCSign 真实流水线。
struct SigningJob: Identifiable {
    let id = UUID()
    let project: SignProject
    let certificate: Certificate
    var step: Step
    var progress: Double
    var logs: [String]
    var injectEnabled: Bool

    enum Step: Int, CaseIterable {
        case prepare
        case unzip
        case removeOldSignature
        case injectDylibs
        case injectProvision
        case rewriteEntitlements
        case signDependencies
        case signMain
        case repackage
        case host
        case done
        case failed

        var title: String {
            switch self {
            case .prepare: return "准备"
            case .unzip: return "解压 IPA"
            case .removeOldSignature: return "移除旧签名"
            case .injectDylibs: return "注入动态库"
            case .injectProvision: return "写入描述文件"
            case .rewriteEntitlements: return "写入 Entitlements"
            case .signDependencies: return "签名 Frameworks"
            case .signMain: return "签名主程序"
            case .repackage: return "重新打包"
            case .host: return "启动本地托管"
            case .done: return "完成"
            case .failed: return "失败"
            }
        }
    }
}
