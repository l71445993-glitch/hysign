import SwiftUI

/// 「应用」Tab —— 签名输出收件箱。
struct AppsView: View {
    @EnvironmentObject private var app: AppState
    @State private var selected: SignedOutput?

    var body: some View {
        NavigationView {
            Group {
                if app.outputs.outputs.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "tray")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                        Text("还没有输出").font(.title3.weight(.semibold))
                        Text("在某个项目里点「签名并安装」，\n生成的 IPA 会出现在这里。")
                            .multilineTextAlignment(.center)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                } else {
                    List {
                        ForEach(app.outputs.outputs) { out in
                            Button { selected = out } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: out.injected ? "wrench.and.screwdriver" : "app.badge.fill")
                                        .frame(width: 40, height: 40)
                                        .background(Theme.card)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(out.name).foregroundStyle(.primary).font(.headline)
                                        Text("\(out.bundleID) · \(out.sizeText)")
                                            .font(.caption).foregroundStyle(.secondary)
                                        Text("\(out.certificateName) · \(out.installState.rawValue)")
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                            .swipeActions {
                                Button(role: .destructive) { app.outputs.remove(out) } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("应用")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if app.signing.isBusy {
                        ProgressView()
                    } else {
                        Image(systemName: "list.bullet.rectangle")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("清空输出", role: .destructive) { app.outputs.clear() }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .sheet(item: $selected) { OutputDetailView(output: $0) }
        }
        .navigationViewStyle(.stack)
    }
}

struct OutputDetailView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    let output: SignedOutput

    var body: some View {
        NavigationView {
            Form {
                Section("产物") {
                    LabeledContent("名称", value: output.name)
                    LabeledContent("Bundle ID", value: output.bundleID)
                    LabeledContent("证书", value: output.certificateName)
                    LabeledContent("注入", value: output.injected ? "是" : "否")
                    LabeledContent("状态", value: output.installState.rawValue)
                }
                Section("OTA 安装（学习）") {
                    Button("生成 manifest.plist") {
                        app.installer.start()
                        let ipa = Storage.docs.appendingPathComponent(output.relativePath)
                        _ = app.installer.makeManifest(for: output, ipaURL: ipa)
                        var o = output
                        o.installState = .hosting
                        app.outputs.update(o)
                    }
                    if !app.installer.lastManifest.isEmpty {
                        Text(app.installer.lastManifest)
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("输出详情")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
