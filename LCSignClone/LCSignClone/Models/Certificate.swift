import Foundation

struct Certificate: Identifiable, Codable, Hashable {
    let id: UUID
    var displayName: String
    var teamID: String
    var expirationDate: Date
    var type: CertType
    /// .p12 相对路径
    var p12RelativePath: String
    /// .mobileprovision 相对路径
    var provisionRelativePath: String
    var p12Password: String
    var lastCheckedAt: Date?
    var revocationStatus: RevocationStatus

    enum CertType: String, Codable {
        case enterprise = "企业"
        case development = "开发"
        case adhoc = "AdHoc"
    }

    enum RevocationStatus: String, Codable {
        case valid = "正常"
        case revoked = "已吊销"
        case expired = "已过期"
        case unknown = "未检测"
    }

    var isUsable: Bool {
        revocationStatus != .revoked && expirationDate > Date()
    }

    var daysUntilExpiration: Int {
        Calendar.current.dateComponents([.day], from: Date(), to: expirationDate).day ?? 0
    }

    var subtitle: String {
        "\(teamID) · 还差 \(max(0, daysUntilExpiration)) 天到期"
    }
}
