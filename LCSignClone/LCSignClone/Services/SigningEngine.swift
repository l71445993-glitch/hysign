import Foundation

/// 签名引擎。
///
/// ## 真机接入 zsign 的两种方式
/// 1. **把 zsign 编成静态库**，用 C 桥接：`ZsignBridge.sign(...)`（推荐，iOS 不能随便 exec 二进制）
/// 2. 越狱环境把 zsign 放到 `/usr/local/bin` 再 posix_spawn（需特殊权限，本学习版不默认启用）
///
/// 默认走「逐步模拟流水线」，把 LCSign/zsign 的真实步骤完整跑一遍日志。
@MainActor
final class SigningEngine: ObservableObject {
    @Published var currentJob: SigningJob?
    @Published var isBusy = false

    private let certificates: CertificateStore
    private let projects: ProjectStore
    private let outputs: OutputStore
    private let injector: InjectorService

    /// false = 强制演示流水线；true = 优先尝试 ZsignBridge（若已链接）
    var preferRealZsign = false

    init(certificates: CertificateStore, projects: ProjectStore,
         outputs: OutputStore, injector: InjectorService) {
        self.certificates = certificates
        self.projects = projects
        self.outputs = outputs
        self.injector = injector
    }

    func signAndInstall(_ project: SignProject, inject: Bool = false) async {
        guard let cert = certificates.activeCertificate, cert.isUsable else {
            let placeholder = Certificate(
                id: UUID(), displayName: "无证书", teamID: "-", expirationDate: .distantPast,
                type: .enterprise, p12RelativePath: "", provisionRelativePath: "",
                p12Password: "", lastCheckedAt: nil, revocationStatus: .unknown
            )
            currentJob = SigningJob(
                project: project,
                certificate: certificates.activeCertificate ?? placeholder,
                step: .failed, progress: 0,
                logs: ["错误：没有可用的活动证书。请到 设置 → 签名证书 导入。"],
                injectEnabled: inject
            )
            return
        }

        isBusy = true
        defer { isBusy = false }

        var job = SigningJob(project: project, certificate: cert, step: .prepare,
                             progress: 0, logs: ["证书：\(cert.displayName) (\(cert.teamID))"],
                             injectEnabled: inject)
        currentJob = job

        if preferRealZsign {
            let bridge = ZsignBridge.shared
            if bridge.isAvailable {
                job.logs.append("检测到 ZsignBridge，尝试原生签名…")
                currentJob = job
                let result = bridge.sign(
                    inputRelativePath: project.relativePath,
                    outputRelativePath: "Outputs/\(project.bundleID)-signed.ipa",
                    p12RelativePath: cert.p12RelativePath,
                    provisionRelativePath: cert.provisionRelativePath,
                    password: cert.p12Password,
                    bundleIDOverride: project.overrideBundleID
                )
                job.logs.append(contentsOf: result.logs)
                if result.success {
                    job.step = .done
                    job.progress = 1
                    currentJob = job
                    emitOutput(from: project, cert: cert, injected: inject)
                    return
                }
                job.logs.append("原生签名失败，回退演示流水线…")
                currentJob = job
            } else {
                job.logs.append("未链接 ZsignBridge，使用演示流水线。")
            }
        }

        let steps: [SigningJob.Step] = inject
            ? [.prepare, .unzip, .removeOldSignature, .injectDylibs, .injectProvision,
               .rewriteEntitlements, .signDependencies, .signMain, .repackage, .host, .done]
            : [.prepare, .unzip, .removeOldSignature, .injectProvision,
               .rewriteEntitlements, .signDependencies, .signMain, .repackage, .host, .done]

        for (idx, step) in steps.enumerated() {
            job.step = step
            job.progress = Double(idx) / Double(max(steps.count - 1, 1))
            job.logs.append("→ \(step.title)")
            if step == .injectDylibs {
                job.logs.append(injector.describeInjection(for: project))
                await runInjection(for: project, into: &job)
            }
            if step == .host {
                appInstallerNote(&job)
            }
            currentJob = job
            try? await Task.sleep(nanoseconds: 320_000_000)
        }

        job.step = .done
        job.progress = 1
        job.logs.append("完成：\(project.name) ← \(cert.displayName)")
        currentJob = job
        emitOutput(from: project, cert: cert, injected: inject)
    }

    /// 真正的注入：解包 IPA → 用 MachOPatcher 改主二进制 → 重打包。
    /// 找不到实体文件（如演示数据）时只记录，不阻断流水线。
    private func runInjection(for project: SignProject, into job: inout SigningJob) async {
        guard !project.injectDylibs.isEmpty else { return }

        let ipaURL = Storage.docs.appendingPathComponent(project.relativePath)
        guard FileManager.default.fileExists(atPath: ipaURL.path) else {
            job.logs.append("（演示）未找到实体 IPA \(project.relativePath)，跳过真实注入。")
            return
        }

        let dylibURLs = project.injectDylibs
            .map { Storage.docs.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !dylibURLs.isEmpty else {
            job.logs.append("待注入 dylib 均不存在，跳过。")
            return
        }

        let packager = IPAPackager()
        do {
            let (work, app) = try packager.unzip(ipa: ipaURL)
            defer { packager.cleanup(work) }
            job.logs.append("解包 → \(app.lastPathComponent)")

            let result = try injector.inject(dylibs: dylibURLs, intoAppBundle: app, weak: true)
            job.logs.append(contentsOf: result.logs)

            try packager.zip(workDir: work, to: ipaURL)
            job.logs.append("重打包完成，注入 \(result.injectedNames.count) 个 dylib（待重签）。")
        } catch {
            job.logs.append("注入失败：\(error.localizedDescription)")
        }
        currentJob = job
    }

    private func appInstallerNote(_ job: inout SigningJob) {
        job.logs.append("托管：生成 itms-services manifest（见「应用」详情）。")
    }

    private func emitOutput(from project: SignProject, cert: Certificate, injected: Bool) {
        let out = SignedOutput(
            id: UUID(),
            name: project.name,
            bundleID: project.overrideBundleID ?? project.bundleID,
            version: project.version,
            byteSize: project.byteSize,
            createdAt: Date(),
            certificateID: cert.id,
            certificateName: cert.displayName,
            relativePath: "Outputs/\(project.bundleID)-signed.ipa",
            injected: injected,
            installState: .ready
        )
        outputs.add(out)
    }
}

/// zsign 的 iOS 桥接占位。把 zsign 静态库链进来后，在此调用 C API。
struct ZsignBridge {
    static let shared = ZsignBridge()

    /// 学习版默认 false；接入静态库后改为检测符号是否存在。
    var isAvailable: Bool { false }

    func sign(inputRelativePath: String,
              outputRelativePath: String,
              p12RelativePath: String,
              provisionRelativePath: String,
              password: String,
              bundleIDOverride: String?) -> (success: Bool, logs: [String]) {
        (
            false,
            [
                "ZsignBridge 未实现。",
                "请编译 https://github.com/zhlynn/zsign 为 ios-arm64 静态库，",
                "并在此桥接：zsign::Sign(...) / 导出 C 接口。"
            ]
        )
    }
}
