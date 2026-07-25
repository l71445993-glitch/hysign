import SwiftUI

/// 「项目」Tab —— 对齐 LCSign：空态引导 + 导入 + 列表操作。
struct ProjectsView: View {
    @EnvironmentObject private var app: AppState
    @State private var showImport = false
    @State private var showJob = false
    @State private var editing: SignProject?

    var body: some View {
        NavigationView {
            Group {
                if app.projects.projects.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(app.projects.projects) { project in
                            ProjectRow(project: project)
                                .contentShape(Rectangle())
                                .onTapGesture { editing = project }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        app.projects.remove(project)
                                    } label: { Label("删除", systemImage: "trash") }
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        Task {
                                            showJob = true
                                            await app.signing.signAndInstall(
                                                project,
                                                inject: app.settings.autoInject || !project.injectDylibs.isEmpty
                                            )
                                        }
                                    } label: { Label("签名并安装", systemImage: "signature") }
                                    .tint(Theme.accent)
                                }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("项目")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Button("选择") {}
                        Button("调整顺序") {}
                        Button("清空所有项目", role: .destructive) { app.projects.clearAll() }
                    } label: { Image(systemName: "list.bullet") }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showImport = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showImport) { ImportSheet() }
            .sheet(item: $editing) { ProjectDetailView(project: $0) }
            .sheet(isPresented: $showJob) { SigningProgressSheet() }
        }
        .navigationViewStyle(.stack)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.dashed")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("还没有项目")
                .font(.title3.weight(.semibold))
            Text("导入 IPA / TIPA 创建项目。\n其它文件会自动分流处理。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(.subheadline)
            Button { showImport = true } label: {
                Text("导入文件")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 40)
            .padding(.top, 8)
        }
        .padding()
    }
}

struct ProjectRow: View {
    let project: SignProject

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.accent.opacity(0.15))
                .frame(width: 52, height: 52)
                .overlay(
                    Image(systemName: project.kind == .tipa ? "shippingbox" : "app")
                        .foregroundStyle(Theme.accent)
                )
            VStack(alignment: .leading, spacing: 4) {
                Text(project.name).font(.headline)
                Text("\(project.bundleID) · \(project.kind.rawValue)")
                    .font(.caption).foregroundStyle(.secondary)
                Text("\(project.sizeText) · v\(project.version)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
