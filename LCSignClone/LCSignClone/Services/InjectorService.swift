import Foundation

/// 开源 dylib 注入服务。
///
/// 流程（等价 LCSign/insert_dylib 的开源做法，纯 Swift 进程内完成）：
/// 1. 定位 `Payload/App.app` 与主可执行文件（读 Info.plist 的 CFBundleExecutable）。
/// 2. 把待注入 dylib 拷进 `App.app/Frameworks/`。
/// 3. 用 `MachOPatcher` 给主二进制追加 `LC_LOAD_DYLIB @rpath/xxx.dylib`（并补 `LC_RPATH`）。
/// 4. 交回签名引擎整体重签（Frameworks 内每个 dylib 也要单独签）。
///
/// 注意：注入本身不签名。必须在注入后再走 zsign / codesign，否则装不上。
@MainActor
final class InjectorService: ObservableObject {
    @Published var engineVersion = "华阳签 OpenInject 1.0（insert_dylib 等价 / 自研 Mach-O 补丁）"
    @Published var isInstalled = true

    private let fm = FileManager.default

    // MARK: 计划描述（UI 用）

    func describeInjection(for project: SignProject) -> String {
        if project.injectDylibs.isEmpty {
            return "注入：无额外 dylib（跳过）。引擎 \(engineVersion)"
        }
        let list = project.injectDylibs.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
        return "注入计划：拷贝 [\(list)] → App.app/Frameworks/，并给主二进制追加 LC_LOAD_DYLIB。引擎 \(engineVersion)"
    }

    // MARK: 真正执行

    struct InjectResult {
        var logs: [String] = []
        var injectedNames: [String] = []
    }

    /// 对已解包的 `.app` 目录执行注入。
    /// - Parameters:
    ///   - dylibs: 磁盘上的 dylib 文件 URL 列表。
    ///   - appURL: `Payload/App.app` 目录。
    ///   - weak: 是否用 weak 加载（更稳，缺失不崩）。
    @discardableResult
    func inject(dylibs: [URL], intoAppBundle appURL: URL, weak: Bool = true) throws -> InjectResult {
        var result = InjectResult()
        guard !dylibs.isEmpty else {
            result.logs.append("无 dylib，跳过注入。")
            return result
        }

        let mainBinary = try mainExecutableURL(in: appURL)
        result.logs.append("主二进制：\(mainBinary.lastPathComponent)")

        let frameworks = appURL.appendingPathComponent("Frameworks", isDirectory: true)
        if !fm.fileExists(atPath: frameworks.path) {
            try fm.createDirectory(at: frameworks, withIntermediateDirectories: true)
            result.logs.append("创建 Frameworks/ 目录。")
        }

        for dylib in dylibs {
            let name = dylib.lastPathComponent
            let dest = frameworks.appendingPathComponent(name)

            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: dylib, to: dest)
            result.logs.append("拷贝 → Frameworks/\(name)")

            let loadPath = "@rpath/\(name)"
            let reports = try MachOPatcher.addLoadDylib(to: mainBinary,
                                                        dylibPath: loadPath,
                                                        weak: weak,
                                                        ensureRPath: true)
            for r in reports {
                for cmd in r.addedCommands {
                    result.logs.append("[\(r.arch)] + \(cmd)")
                }
            }
            result.injectedNames.append(name)
        }

        // 校验：把注入后主二进制的加载表列出来
        let libs = (try? MachOPatcher.listDylibs(in: mainBinary)) ?? []
        let injectedRefs = libs.filter { line in
            result.injectedNames.contains { line.contains($0) }
        }
        result.logs.append("校验：主二进制现引用 \(injectedRefs.count) 个注入库。")
        return result
    }

    /// 从 Info.plist 读 CFBundleExecutable，得到主可执行文件路径。
    private func mainExecutableURL(in appURL: URL) throws -> URL {
        let infoPlist = appURL.appendingPathComponent("Info.plist")
        if let data = try? Data(contentsOf: infoPlist),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let exec = plist["CFBundleExecutable"] as? String {
            return appURL.appendingPathComponent(exec)
        }
        // 兜底：用 .app 同名文件
        let fallback = appURL.deletingPathExtension().lastPathComponent
        let url = appURL.appendingPathComponent(fallback)
        if fm.fileExists(atPath: url.path) { return url }
        throw InjectorError.mainExecutableNotFound
    }

    enum InjectorError: LocalizedError {
        case mainExecutableNotFound
        var errorDescription: String? {
            switch self {
            case .mainExecutableNotFound:
                return "找不到主可执行文件（Info.plist 缺 CFBundleExecutable）。"
            }
        }
    }
}
