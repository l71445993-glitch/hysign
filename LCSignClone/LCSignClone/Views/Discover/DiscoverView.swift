import SwiftUI

/// 「发现」Tab —— 软件源订阅。
struct DiscoverView: View {
    @EnvironmentObject private var app: AppState
    @State private var showAdd = false

    var body: some View {
        NavigationView {
            Group {
                if app.sources.sources.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "safari")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                        Text("还没添加软件源").font(.title3.weight(.semibold))
                        Text("右上角的「+」添加一个订阅 URL")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button { showAdd = true } label: {
                            Text("添加软件源")
                                .frame(maxWidth: 280)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(app.sources.sources) { source in
                            Section(source.name) {
                                if source.apps.isEmpty {
                                    Text("暂无应用").foregroundStyle(.secondary)
                                } else {
                                    ForEach(source.apps) { item in
                                        HStack {
                                            Image(systemName: item.iconSystemName)
                                            VStack(alignment: .leading) {
                                                Text(item.name)
                                                Text("\(item.subtitle) · v\(item.version)")
                                                    .font(.caption).foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Button("导入") {
                                                app.projects.importDemo(
                                                    name: item.name,
                                                    bundleID: item.bundleID,
                                                    version: item.version,
                                                    size: 20_000_000,
                                                    kind: .ipa
                                                )
                                                app.settings.selectedTab = .projects
                                            }
                                            .font(.caption)
                                        }
                                    }
                                }
                            }
                            .swipeActions {
                                Button(role: .destructive) { app.sources.remove(source) } label: {
                                    Label("删除", systemImage: "trash")
                                }
                                Button {
                                    Task { await app.sources.refresh(source.id) }
                                } label: { Label("刷新", systemImage: "arrow.clockwise") }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("软件源")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button {
                            Task { await app.sources.refreshAll() }
                        } label: { Image(systemName: "arrow.clockwise") }
                        Button { showAdd = true } label: { Image(systemName: "plus") }
                    }
                }
            }
            .sheet(isPresented: $showAdd) { AddSourceSheet() }
            .overlay {
                if app.sources.isRefreshing {
                    ProgressView("刷新中…")
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

struct AddSourceSheet: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var name = "我的源"
    @State private var urlText = "https://example.com/source.json"

    var body: some View {
        NavigationView {
            Form {
                TextField("名称", text: $name)
                TextField("订阅 URL", text: $urlText)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                Section {
                    Text("JSON 格式示例：{\"name\":\"源名\",\"apps\":[{\"name\":\"A\",\"bundleID\":\"com.a\",\"version\":\"1\",\"downloadURL\":\"https://...\"}]}")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("添加软件源")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        if let url = URL(string: urlText) {
                            app.sources.add(name: name, url: url)
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}
