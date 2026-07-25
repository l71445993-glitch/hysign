import SwiftUI

/// 「设置」Tab —— 对齐 LCSign 设置分组。
struct SettingsView: View {
    @EnvironmentObject private var app: AppState
    @State private var showCerts = false

    var body: some View {
        NavigationView {
            List {
                Section {
                    SettingsCard(
                        title: "当前设备 UDID",
                        subtitle: app.settings.udidText,
                        systemImage: "iphone"
                    )
                    Button { showCerts = true } label: {
                        SettingsCard(
                            title: "签名证书",
                            subtitle: "已导入 \(app.certificates.certificates.count) 张",
                            systemImage: "checkmark.seal"
                        )
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 12) {
                        Image(systemName: "bolt.fill")
                            .foregroundStyle(Theme.warning)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("注入引擎")
                            Text(app.settings.engineLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.success)
                    }
                    .padding(.vertical, 8)
                }

                Section {
                    SettingsCard(title: "软件主题", subtitle: "强调色与图标", systemImage: "paintbrush")
                    ColorAccentPicker(hex: $app.settings.accentHex)
                    Toggle("签名时默认注入", isOn: $app.settings.autoInject)
                    Toggle("演示模式（无 zsign 逐步模拟）", isOn: $app.settings.demoMode)
                        .onChange(of: app.settings.demoMode) { demo in
                            app.signing.preferRealZsign = !demo
                        }
                }

                Section {
                    SettingsCard(title: "应用配置", subtitle: "签名、安装与分享导入默认行为", systemImage: "slider.horizontal.3")
                    SettingsCard(title: "存储空间", subtitle: documentsSizeText(), systemImage: "internaldrive")
                    SettingsCard(title: "工单反馈", subtitle: "学习版无远端工单", systemImage: "bubble.left.and.bubble.right")
                }

                Section {
                    SettingsCard(title: "软件设置", subtitle: "语言、日志、协议、开源许可", systemImage: "gear")
                    Link(destination: URL(string: "https://github.com/zhlynn/zsign")!) {
                        Label("zsign 开源签名器", systemImage: "link")
                    }
                }

                Section {
                    Text("华阳签 \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("设置")
            .sheet(isPresented: $showCerts) { CertificatesView() }
        }
        .navigationViewStyle(.stack)
    }

    private func documentsSizeText() -> String {
        let url = Storage.docs
        let size = (try? FileManager.default.allocatedSizeOfDirectory(at: url)) ?? 0
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

struct SettingsCard: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .frame(width: 28)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
    }
}

struct ColorAccentPicker: View {
    @Binding var hex: UInt
    private let presets: [UInt] = [0x0A84FF, 0xFF6B35, 0x34C759, 0xAF52DE, 0xFF2D55]

    var body: some View {
        HStack {
            Text("强调色")
            Spacer()
            ForEach(presets, id: \.self) { c in
                Circle()
                    .fill(Color(hex: c))
                    .frame(width: 24, height: 24)
                    .overlay(Circle().stroke(Color.primary.opacity(hex == c ? 0.8 : 0), lineWidth: 2))
                    .onTapGesture { hex = c }
            }
        }
    }
}

struct CertificatesView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                ForEach(app.certificates.certificates) { cert in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: app.certificates.activeCertificateID == cert.id
                              ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(cert.isUsable ? Theme.success : Theme.danger)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(cert.displayName).font(.subheadline.weight(.semibold))
                            Text(cert.subtitle).font(.caption).foregroundStyle(.secondary)
                            Text(cert.revocationStatus.rawValue)
                                .font(.caption2)
                                .foregroundStyle(cert.isUsable ? Theme.success : Theme.danger)
                        }
                        Spacer()
                        Menu {
                            Button("设为当前") { app.certificates.select(cert) }
                            Button("检测吊销") {
                                Task { await app.certificates.checkRevocation(for: cert.id) }
                            }
                            Button("删除", role: .destructive) { app.certificates.remove(cert) }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { app.certificates.select(cert) }
                }
            }
            .navigationTitle("签名证书")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("设置") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        // 学习版：再塞一张演示证书
                        var c = DemoData.certificates[0]
                        c = Certificate(
                            id: UUID(),
                            displayName: "iPhone Distribution: Imported \(Int.random(in: 100...999))",
                            teamID: "IMP\(Int.random(in: 10000...99999))",
                            expirationDate: Calendar.current.date(byAdding: .day, value: 200, to: Date())!,
                            type: .enterprise,
                            p12RelativePath: "Certs/imported.p12",
                            provisionRelativePath: "Certs/imported.mobileprovision",
                            p12Password: "1",
                            lastCheckedAt: Date(),
                            revocationStatus: .valid
                        )
                        app.certificates.add(c)
                    } label: { Image(systemName: "plus") }
                }
            }
        }
    }
}

private extension FileManager {
    func allocatedSizeOfDirectory(at url: URL) throws -> Int64 {
        var total: Int64 = 0
        let enumerator = self.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [])
        while let file = enumerator?.nextObject() as? URL {
            let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            total += Int64(size)
        }
        return total
    }
}
