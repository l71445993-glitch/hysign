import SwiftUI

/// 「文件」Tab —— 简易沙盒文件浏览器。
struct FilesView: View {
    @EnvironmentObject private var app: AppState
    @State private var entries: [FileEntry] = []
    @State private var path: URL = Storage.docs

    var body: some View {
        NavigationView {
            List {
                Section {
                    Text(path.path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                ForEach(entries) { entry in
                    HStack {
                        Image(systemName: entry.isDirectory ? "folder.fill" : "doc")
                            .foregroundStyle(entry.isDirectory ? Theme.accent : .secondary)
                        VStack(alignment: .leading) {
                            Text(entry.name)
                            if !entry.isDirectory {
                                Text(entry.sizeText).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if entry.isDirectory {
                            path = entry.url
                            reload()
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("文件")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("上级") {
                        let parent = path.deletingLastPathComponent()
                        if parent.path.hasPrefix(Storage.docs.path) || parent.path == Storage.docs.path {
                            path = parent.path.count < Storage.docs.path.count ? Storage.docs : parent
                            reload()
                        }
                    }
                    .disabled(path.path == Storage.docs.path)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { ensureScaffold(); reload() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .onAppear {
                ensureScaffold()
                reload()
            }
        }
        .navigationViewStyle(.stack)
    }

    private func ensureScaffold() {
        let fm = FileManager.default
        for name in ["Projects", "Outputs", "Certs", "Tools", "Tweaks"] {
            let u = Storage.docs.appendingPathComponent(name)
            try? fm.createDirectory(at: u, withIntermediateDirectories: true)
        }
        let readme = Storage.docs.appendingPathComponent("README.txt")
        if !fm.fileExists(atPath: readme.path) {
            try? """
            华阳签 沙盒目录
            - Projects/  导入的 IPA
            - Outputs/   签名产物
            - Certs/     p12 + mobileprovision
            - Tools/     放入可执行 zsign 即可启用真签名
            - Tweaks/    待注入 dylib
            """.write(to: readme, atomically: true, encoding: .utf8)
        }
    }

    private func reload() {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: path,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            entries = []
            return
        }
        entries = urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            return FileEntry(
                id: url.path,
                name: url.lastPathComponent,
                url: url,
                isDirectory: values?.isDirectory ?? false,
                byteSize: Int64(values?.fileSize ?? 0)
            )
        }
        .sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory && !b.isDirectory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
}

struct FileEntry: Identifiable {
    let id: String
    let name: String
    let url: URL
    let isDirectory: Bool
    let byteSize: Int64

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file)
    }
}
