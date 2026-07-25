import SwiftUI

/// 对齐 LCSign：项目 / 应用 / 发现 / 文件 / 设置
struct RootTabView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        TabView(selection: $app.settings.selectedTab) {
            ProjectsView()
                .tabItem { Label("项目", systemImage: "square.stack") }
                .tag(AppTab.projects)

            AppsView()
                .tabItem { Label("应用", systemImage: "app.badge") }
                .tag(AppTab.apps)

            DiscoverView()
                .tabItem { Label("发现", systemImage: "safari") }
                .tag(AppTab.discover)

            FilesView()
                .tabItem { Label("文件", systemImage: "folder") }
                .tag(AppTab.files)

            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
    }
}

enum AppTab: Hashable {
    case projects, apps, discover, files, settings
}
