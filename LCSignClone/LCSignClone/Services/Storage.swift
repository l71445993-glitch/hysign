import Foundation

enum Storage {
    static var docs: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func docsURL(_ name: String) -> URL? {
        docs.appendingPathComponent(name)
    }
}

enum DemoData {
    static var certificates: [Certificate] {
        [
            Certificate(
                id: UUID(),
                displayName: "iPhone Distribution: Demo Learner",
                teamID: "LEARN001",
                expirationDate: Calendar.current.date(byAdding: .day, value: 300, to: Date())!,
                type: .enterprise,
                p12RelativePath: "Certs/demo.p12",
                provisionRelativePath: "Certs/demo.mobileprovision",
                p12Password: "1",
                lastCheckedAt: Date(),
                revocationStatus: .valid
            ),
            Certificate(
                id: UUID(),
                displayName: "iPhone Distribution: Expired Sample",
                teamID: "EXP00001",
                expirationDate: Calendar.current.date(byAdding: .day, value: -20, to: Date())!,
                type: .enterprise,
                p12RelativePath: "Certs/expired.p12",
                provisionRelativePath: "Certs/expired.mobileprovision",
                p12Password: "1",
                lastCheckedAt: Date(),
                revocationStatus: .expired
            )
        ]
    }

    static var projects: [SignProject] {
        [
            SignProject(id: UUID(), name: "示例播放器", bundleID: "com.demo.player",
                        version: "1.0.0", byteSize: 42_000_000, importedAt: Date(),
                        relativePath: "Projects/com.demo.player.ipa", kind: .ipa,
                        injectDylibs: [], overrideBundleID: nil),
            SignProject(id: UUID(), name: "示例工具(TIPA)", bundleID: "com.demo.toolbox",
                        version: "2.1.0", byteSize: 8_500_000, importedAt: Date(),
                        relativePath: "Projects/com.demo.toolbox.tipa", kind: .tipa,
                        injectDylibs: ["Tweaks/demo.dylib"], overrideBundleID: nil)
        ]
    }

    static var sourceApps: [SourceApp] {
        [
            SourceApp(id: UUID(), name: "Demo App A", bundleID: "com.source.a", version: "1.0",
                      downloadURL: URL(string: "https://example.com/a.ipa")!,
                      iconSystemName: "app.fill", subtitle: "演示条目"),
            SourceApp(id: UUID(), name: "Demo App B", bundleID: "com.source.b", version: "3.2",
                      downloadURL: URL(string: "https://example.com/b.ipa")!,
                      iconSystemName: "hammer.fill", subtitle: "演示条目")
        ]
    }
}
