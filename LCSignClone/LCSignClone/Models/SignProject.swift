import Foundation

/// 对齐 LCSign「项目」：一个导入的 IPA/TIPA 工程。
struct SignProject: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var bundleID: String
    var version: String
    var byteSize: Int64
    var importedAt: Date
    /// 相对 Documents 路径
    var relativePath: String
    var kind: PackageKind
    /// 可选：待注入的 dylib 列表（相对路径）
    var injectDylibs: [String]
    /// 签名时是否改 Bundle ID
    var overrideBundleID: String?

    enum PackageKind: String, Codable {
        case ipa = "IPA"
        case tipa = "TIPA"
    }

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file)
    }
}
