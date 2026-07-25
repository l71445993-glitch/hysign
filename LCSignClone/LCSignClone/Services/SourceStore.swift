import Foundation

@MainActor
final class SourceStore: ObservableObject {
    @Published private(set) var sources: [SoftwareSource] = []
    @Published var isRefreshing = false

    private let fileName = "sources.json"

    init() {
        load()
    }

    func add(name: String, url: URL) {
        let source = SoftwareSource(id: UUID(), name: name, url: url, apps: [], lastRefreshedAt: nil)
        sources.append(source)
        save()
        Task { await refresh(source.id) }
    }

    func remove(_ source: SoftwareSource) {
        sources.removeAll { $0.id == source.id }
        save()
    }

    /// 学习版：解析失败时填演示 App；真机应对 JSON 源做 HTTP GET。
    func refresh(_ id: UUID) async {
        guard let i = sources.firstIndex(where: { $0.id == id }) else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        try? await Task.sleep(nanoseconds: 500_000_000)

        var s = sources[i]
        // 尝试真实拉取；失败则用演示数据
        if let (name, apps) = await fetchSource(url: s.url) {
            s.name = name.isEmpty ? s.name : name
            s.apps = apps
        } else if s.apps.isEmpty {
            s.apps = DemoData.sourceApps
        }
        s.lastRefreshedAt = Date()
        sources[i] = s
        save()
    }

    func refreshAll() async {
        for s in sources { await refresh(s.id) }
    }

    private func fetchSource(url: URL) async -> (String, [SourceApp])? {
        // 约定 JSON：{ "name": "...", "apps": [ { name, bundleID, version, downloadURL } ] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            struct Payload: Decodable {
                var name: String?
                var apps: [Item]?
                struct Item: Decodable {
                    var name: String
                    var bundleID: String
                    var version: String
                    var downloadURL: URL
                    var subtitle: String?
                }
            }
            let p = try JSONDecoder().decode(Payload.self, from: data)
            let apps = (p.apps ?? []).map {
                SourceApp(id: UUID(), name: $0.name, bundleID: $0.bundleID, version: $0.version,
                          downloadURL: $0.downloadURL, iconSystemName: "app",
                          subtitle: $0.subtitle ?? $0.bundleID)
            }
            return (p.name ?? "", apps)
        } catch {
            return nil
        }
    }

    private func load() {
        guard let url = Storage.docsURL(fileName),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([SoftwareSource].self, from: data) else { return }
        sources = list
    }

    private func save() {
        guard let url = Storage.docsURL(fileName),
              let data = try? JSONEncoder().encode(sources) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
