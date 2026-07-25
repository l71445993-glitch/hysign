import Foundation

@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [SignProject] = []

    private let fileName = "projects.json"

    init() {
        load()
        if projects.isEmpty {
            projects = DemoData.projects
            save()
        }
    }

    func add(_ project: SignProject) {
        projects.insert(project, at: 0)
        save()
    }

    func remove(_ project: SignProject) {
        projects.removeAll { $0.id == project.id }
        save()
    }

    func clearAll() {
        projects.removeAll()
        save()
    }

    func update(_ project: SignProject) {
        guard let i = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[i] = project
        save()
    }

    /// 学习版：从「虚拟导入」创建项目。真机可接 DocumentPicker 拷贝到 Documents/Projects。
    func importDemo(name: String, bundleID: String, version: String, size: Int64, kind: SignProject.PackageKind) {
        let p = SignProject(
            id: UUID(),
            name: name,
            bundleID: bundleID,
            version: version,
            byteSize: size,
            importedAt: Date(),
            relativePath: "Projects/\(bundleID).\(kind == .tipa ? "tipa" : "ipa")",
            kind: kind,
            injectDylibs: [],
            overrideBundleID: nil
        )
        add(p)
    }

    private func load() {
        guard let url = Storage.docsURL(fileName),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([SignProject].self, from: data) else { return }
        projects = list
    }

    private func save() {
        guard let url = Storage.docsURL(fileName),
              let data = try? JSONEncoder().encode(projects) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
