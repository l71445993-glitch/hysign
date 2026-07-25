import Foundation
import ZIPFoundation

/// IPA 解包 / 重打包。
///
/// iOS 上 Foundation 没有公开的 zip API，用开源 ZIPFoundation 完成。
/// 与注入配合：`unzip → 定位 .app → 注入 → zip`，再交给签名。
struct IPAPackager {

    let fm = FileManager.default

    enum PackError: LocalizedError {
        case appBundleNotFound
        var errorDescription: String? {
            switch self {
            case .appBundleNotFound: return "IPA 内找不到 Payload/*.app。"
            }
        }
    }

    /// 解压到一个临时工作目录，返回工作目录与其中的 `.app`。
    func unzip(ipa: URL) throws -> (workDir: URL, appBundle: URL) {
        let work = fm.temporaryDirectory
            .appendingPathComponent("hy-inject-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        try fm.unzipItem(at: ipa, to: work)

        let payload = work.appendingPathComponent("Payload", isDirectory: true)
        let apps = (try? fm.contentsOfDirectory(at: payload, includingPropertiesForKeys: nil)) ?? []
        guard let app = apps.first(where: { $0.pathExtension == "app" }) else {
            throw PackError.appBundleNotFound
        }
        return (work, app)
    }

    /// 把工作目录（含 Payload/）重新打成 IPA。
    func zip(workDir: URL, to outputIPA: URL) throws {
        if fm.fileExists(atPath: outputIPA.path) { try fm.removeItem(at: outputIPA) }
        let payload = workDir.appendingPathComponent("Payload", isDirectory: true)
        // 只打包 Payload 目录，保持标准 IPA 结构
        try fm.zipItem(at: payload, to: outputIPA,
                       shouldKeepParent: true, compressionMethod: .deflate)
    }

    func cleanup(_ workDir: URL) {
        try? fm.removeItem(at: workDir)
    }
}
