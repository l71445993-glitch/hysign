import SwiftUI
import UniformTypeIdentifiers

struct ImportSheet: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var name = "新导入应用"
    @State private var bundleID = "com.example.app"
    @State private var version = "1.0.0"
    @State private var isTIPA = false

    var body: some View {
        NavigationView {
            Form {
                Section("学习版说明") {
                    Text("真机请用系统文件选择器导入真实 IPA。此处用表单模拟导入，方便无文件时跑通流程。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("元数据") {
                    TextField("名称", text: $name)
                    TextField("Bundle ID", text: $bundleID)
                    TextField("版本", text: $version)
                    Toggle("TIPA（TrollStore 包）", isOn: $isTIPA)
                }
                Section {
                    Button("加入项目") {
                        app.projects.importDemo(
                            name: name,
                            bundleID: bundleID,
                            version: version,
                            size: Int64.random(in: 5_000_000...80_000_000),
                            kind: isTIPA ? .tipa : .ipa
                        )
                        dismiss()
                    }
                }
            }
            .navigationTitle("导入文件")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

struct ProjectDetailView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    let project: SignProject
    @State private var overrideBID: String = ""
    @State private var showJob = false
    @State private var dylibs: [String] = []
    @State private var showDylibPicker = false
    @State private var injectError: String?

    var body: some View {
        NavigationView {
            Form {
                Section("信息") {
                    LabeledContent("名称", value: project.name)
                    LabeledContent("Bundle ID", value: project.bundleID)
                    LabeledContent("版本", value: project.version)
                    LabeledContent("类型", value: project.kind.rawValue)
                    LabeledContent("大小", value: project.sizeText)
                }
                Section("签名选项") {
                    TextField("覆盖 Bundle ID（可选）", text: $overrideBID)
                    if let cert = app.certificates.activeCertificate {
                        LabeledContent("当前证书", value: cert.displayName)
                    } else {
                        Text("未选择证书").foregroundStyle(Theme.danger)
                    }
                }
                Section {
                    if dylibs.isEmpty {
                        Text("暂无待注入 dylib。点下方按钮从文件选择 .dylib。")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        ForEach(dylibs, id: \.self) { rel in
                            HStack {
                                Image(systemName: "puzzlepiece.extension.fill")
                                    .foregroundStyle(Theme.accent)
                                Text((rel as NSString).lastPathComponent)
                                    .font(.system(.body, design: .monospaced))
                            }
                        }
                        .onDelete { idx in
                            dylibs.remove(atOffsets: idx)
                            persistDylibs()
                        }
                    }
                    Button {
                        showDylibPicker = true
                    } label: {
                        Label("添加 dylib（往 IPA 塞）", systemImage: "plus.circle")
                    }
                    Text("引擎：\(app.injector.engineVersion)")
                        .font(.caption2).foregroundStyle(.secondary)
                } header: {
                    Text("注入（开源方案）")
                } footer: {
                    Text("拷进 App.app/Frameworks/，给主二进制追加 LC_LOAD_DYLIB @rpath/…，随后整体重签。")
                }
                Section {
                    Button {
                        var p = project
                        p.overrideBundleID = overrideBID.isEmpty ? nil : overrideBID
                        p.injectDylibs = dylibs
                        app.projects.update(p)
                        Task {
                            showJob = true
                            await app.signing.signAndInstall(
                                p,
                                inject: app.settings.autoInject || !p.injectDylibs.isEmpty
                            )
                        }
                    } label: {
                        Label("签名并安装", systemImage: "signature")
                    }
                    .disabled(app.signing.isBusy || app.certificates.activeCertificate == nil)
                }
            }
            .onAppear {
                overrideBID = project.overrideBundleID ?? ""
                dylibs = project.injectDylibs
            }
            .alert("注入导入失败", isPresented: .constant(injectError != nil)) {
                Button("好") { injectError = nil }
            } message: { Text(injectError ?? "") }
            .fileImporter(isPresented: $showDylibPicker,
                          allowedContentTypes: dylibContentTypes,
                          allowsMultipleSelection: true) { result in
                handlePicked(result)
            }
            .navigationTitle(project.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .sheet(isPresented: $showJob) { SigningProgressSheet() }
        }
    }

    private var dylibContentTypes: [UTType] {
        var types: [UTType] = [.data]
        if let dylib = UTType(filenameExtension: "dylib") { types.insert(dylib, at: 0) }
        return types
    }

    /// 把选中的 .dylib 拷进 Documents/Tweaks/，记录相对路径。
    private func handlePicked(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            let fm = FileManager.default
            let tweaks = Storage.docs.appendingPathComponent("Tweaks", isDirectory: true)
            try fm.createDirectory(at: tweaks, withIntermediateDirectories: true)

            for src in urls {
                let needStop = src.startAccessingSecurityScopedResource()
                defer { if needStop { src.stopAccessingSecurityScopedResource() } }

                let dest = tweaks.appendingPathComponent(src.lastPathComponent)
                if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
                try fm.copyItem(at: src, to: dest)

                let rel = "Tweaks/\(src.lastPathComponent)"
                if !dylibs.contains(rel) { dylibs.append(rel) }
            }
            persistDylibs()
        } catch {
            injectError = error.localizedDescription
        }
    }

    private func persistDylibs() {
        var p = project
        p.injectDylibs = dylibs
        p.overrideBundleID = overrideBID.isEmpty ? nil : overrideBID
        app.projects.update(p)
    }
}

struct SigningProgressSheet: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                if let job = app.signing.currentJob {
                    ProgressView(value: job.progress)
                    Text(job.step.title).font(.headline)
                    Text("\(job.project.name) → \(job.certificate.displayName)")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Divider()
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(job.logs.enumerated()), id: \.offset) { _, line in
                                Text(line).font(.system(.caption, design: .monospaced))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    Text("等待任务…")
                }
                Spacer()
            }
            .padding()
            .navigationTitle("处理队列")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .disabled(app.signing.isBusy)
                }
            }
        }
    }
}
