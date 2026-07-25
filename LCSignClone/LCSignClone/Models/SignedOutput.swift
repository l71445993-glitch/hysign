import Foundation

/// 「应用」Tab 收件箱：签名产物。
struct SignedOutput: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var bundleID: String
    var version: String
    var byteSize: Int64
    var createdAt: Date
    var certificateID: UUID
    var certificateName: String
    var relativePath: String
    var injected: Bool
    var installState: InstallState

    enum InstallState: String, Codable {
        case ready = "可安装"
        case hosting = "托管中"
        case installed = "已安装"
        case failed = "失败"
    }

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file)
    }
}
