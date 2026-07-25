import Foundation

/// 「发现」软件源，对齐 LCSign 订阅 URL。
struct SoftwareSource: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var url: URL
    var apps: [SourceApp]
    var lastRefreshedAt: Date?
}

struct SourceApp: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var bundleID: String
    var version: String
    var downloadURL: URL
    var iconSystemName: String
    var subtitle: String
}
