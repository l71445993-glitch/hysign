import Foundation

/// 进程内 Mach-O load command 编辑器。
///
/// 等价于 open-source `insert_dylib` 的核心逻辑，但用纯 Swift 在 iOS 进程内完成，
/// 因为 iOS 上不能 `exec` 外部命令行工具。
///
/// 能力：
/// - 解析 thin / fat（FAT / FAT_64）二进制，逐 slice 处理 arm64 / arm64e。
/// - 在 header 之后的 load command 区尾部追加一条 `LC_LOAD_DYLIB`（或 weak）。
/// - 追加 `LC_RPATH`（当路径用 `@rpath/` 且缺失 rpath 时）。
/// - 复用 header 与首个 section 数据之间的零填充空隙（与 insert_dylib 一致）。
///
/// 局限：只处理小端 64 位（现代 iOS arm64 全覆盖）；遇到 32 位或字节序反转会明确报错，
/// 不会写坏文件。
enum MachOPatcher {

    // MARK: Mach-O 常量

    private static let FAT_MAGIC: UInt32    = 0xcafe_babe   // 大端存储
    private static let FAT_MAGIC_64: UInt32 = 0xcafe_babf
    private static let MH_MAGIC_64: UInt32  = 0xfeed_facf   // 小端 64 位
    private static let MH_CIGAM_64: UInt32  = 0xcffa_edfe   // 字节序反转
    private static let MH_MAGIC_32: UInt32  = 0xfeed_face

    private static let LC_LOAD_DYLIB: UInt32      = 0x0000_000c
    private static let LC_LOAD_WEAK_DYLIB: UInt32 = 0x8000_0018
    private static let LC_RPATH: UInt32           = 0x8000_001c
    private static let LC_SEGMENT_64: UInt32      = 0x0000_0019

    private static let headerSize64 = 32          // mach_header_64
    private static let dylibNameOffset: UInt32 = 24
    private static let rpathPathOffset: UInt32 = 12

    enum PatchError: LocalizedError {
        case notMachO
        case unsupported32Bit
        case swappedByteOrder
        case notEnoughSpace(slice: String, need: Int, have: Int)
        case truncated

        var errorDescription: String? {
            switch self {
            case .notMachO:            return "不是有效的 Mach-O 文件（magic 不匹配）。"
            case .unsupported32Bit:    return "暂不支持 32 位 Mach-O。"
            case .swappedByteOrder:    return "暂不支持字节序反转的 Mach-O。"
            case .notEnoughSpace(let s, let need, let have):
                return "slice \(s) header 空隙不足：需 \(need)B，仅 \(have)B。可考虑先 strip codesign 或用带填充的构建。"
            case .truncated:           return "文件被截断，load command 解析越界。"
            }
        }
    }

    struct SliceReport {
        var arch: String
        var addedCommands: [String]
    }

    // MARK: 对外入口

    /// 给二进制追加一条 dylib 加载命令。
    /// - Parameters:
    ///   - dylibPath: 写入 load command 的路径，例如 `@rpath/Foo.dylib` 或 `@executable_path/Frameworks/Foo.dylib`。
    ///   - weak: 是否用 `LC_LOAD_WEAK_DYLIB`（缺失时不崩，注入更稳）。
    ///   - ensureRPath: 当 `dylibPath` 以 `@rpath/` 开头时，确保存在指向 `@executable_path/Frameworks` 的 rpath。
    /// - Returns: 每个 slice 的处理报告。
    @discardableResult
    static func addLoadDylib(to fileURL: URL,
                             dylibPath: String,
                             weak: Bool = true,
                             ensureRPath: Bool = true) throws -> [SliceReport] {
        var data = try Data(contentsOf: fileURL)
        let reports = try patchAllSlices(&data) { slice in
            var added: [String] = []
            if ensureRPath, dylibPath.hasPrefix("@rpath/") {
                if try slice.ensureRPath("@executable_path/Frameworks") {
                    added.append("LC_RPATH @executable_path/Frameworks")
                }
            }
            try slice.appendDylib(path: dylibPath, weak: weak)
            added.append("\(weak ? "LC_LOAD_WEAK_DYLIB" : "LC_LOAD_DYLIB") \(dylibPath)")
            return added
        }
        try data.write(to: fileURL)
        return reports
    }

    /// 只读：列出所有已存在的 LC_LOAD_DYLIB / LC_RPATH，便于校验注入结果。
    static func listDylibs(in fileURL: URL) throws -> [String] {
        var data = try Data(contentsOf: fileURL)
        var result: [String] = []
        _ = try patchAllSlices(&data) { slice in
            result.append(contentsOf: slice.listLoadedLibraries().map { "[\(slice.archName)] \($0)" })
            return []
        }
        return result
    }

    // MARK: fat / thin 分发

    private static func patchAllSlices(_ data: inout Data,
                                       _ body: (inout SliceEditor) throws -> [String]) throws -> [SliceReport] {
        let magic = try data.readUInt32BE(at: 0)
        if magic == FAT_MAGIC || magic == FAT_MAGIC_64 {
            return try patchFat(&data, is64: magic == FAT_MAGIC_64, body)
        }
        // thin
        if let report = try patchThinSlice(&data, sliceStart: 0, sliceLimit: data.count, body: body) {
            return [report]
        }
        return []
    }

    private static func patchFat(_ data: inout Data, is64: Bool,
                                 _ body: (inout SliceEditor) throws -> [String]) throws -> [SliceReport] {
        // fat_header: magic(BE) + nfat_arch(BE)
        let nfat = try data.readUInt32BE(at: 4)
        var reports: [SliceReport] = []
        // 逐 slice 处理。fat_arch 里记录了各 slice 的 offset/size。
        // 追加 load command 只在 header 空隙里做，不改变 slice 大小，所以 offset/size 不用更新。
        let archStride = is64 ? 32 : 20
        for i in 0..<Int(nfat) {
            let base = 8 + i * archStride
            let offset: Int
            let size: Int
            if is64 {
                offset = Int(try data.readUInt64BE(at: base + 8))
                size   = Int(try data.readUInt64BE(at: base + 16))
            } else {
                offset = Int(try data.readUInt32BE(at: base + 8))
                size   = Int(try data.readUInt32BE(at: base + 12))
            }
            if let r = try patchThinSlice(&data, sliceStart: offset, sliceLimit: offset + size, body: body) {
                reports.append(r)
            }
        }
        return reports
    }

    private static func patchThinSlice(_ data: inout Data, sliceStart: Int, sliceLimit: Int,
                                       body: (inout SliceEditor) throws -> [String]) throws -> SliceReport? {
        let magic = try data.readUInt32(at: sliceStart)   // 小端
        switch magic {
        case MH_MAGIC_64:
            var editor = SliceEditor(data: data, sliceStart: sliceStart, sliceLimit: sliceLimit)
            let added = try body(&editor)
            data = editor.data
            return SliceReport(arch: editor.archName, addedCommands: added)
        case MH_MAGIC_32:
            throw PatchError.unsupported32Bit
        case MH_CIGAM_64:
            throw PatchError.swappedByteOrder
        default:
            throw PatchError.notMachO
        }
    }
}

// MARK: - 单 slice 编辑器（小端 64 位）

private struct SliceEditor {
    var data: Data
    let sliceStart: Int
    let sliceLimit: Int

    var cpuType: Int32 = 0
    var cpuSubtype: Int32 = 0

    init(data: Data, sliceStart: Int, sliceLimit: Int) {
        self.data = data
        self.sliceStart = sliceStart
        self.sliceLimit = sliceLimit
        self.cpuType    = (try? Int32(bitPattern: data.readUInt32(at: sliceStart + 4))) ?? 0
        self.cpuSubtype = (try? Int32(bitPattern: data.readUInt32(at: sliceStart + 8))) ?? 0
    }

    var archName: String {
        // CPU_TYPE_ARM64 = 0x0100000c，subtype 2 = arm64e
        switch (cpuType, cpuSubtype & 0x00ff_ffff) {
        case (0x0100_000c, 2): return "arm64e"
        case (0x0100_000c, _): return "arm64"
        case (0x0000_000c, _): return "arm"
        case (0x0100_0007, _): return "x86_64"
        default:               return String(format: "cpu:0x%x", cpuType)
        }
    }

    private var ncmdsOffset: Int    { sliceStart + 16 }
    private var sizeofcmdsOffset: Int { sliceStart + 20 }
    private var loadCommandsStart: Int { sliceStart + MachOPatcher_headerSize64 }

    private var ncmds: UInt32 { (try? data.readUInt32(at: ncmdsOffset)) ?? 0 }
    private var sizeofcmds: UInt32 { (try? data.readUInt32(at: sizeofcmdsOffset)) ?? 0 }

    /// header 之后到「首个有数据的 section 文件偏移」之间的空隙终点（slice 相对量转文件绝对量）。
    /// 用来判断能否原地追加 load command。
    private func firstSectionFileOffset() throws -> Int {
        var minOffset = sliceLimit - sliceStart      // 默认取 slice 末尾
        var cursor = MachOPatcher_headerSize64
        for _ in 0..<ncmds {
            let cmd = try data.readUInt32(at: sliceStart + cursor)
            let cmdsize = Int(try data.readUInt32(at: sliceStart + cursor + 4))
            if cmd == MachOPatcher_LC_SEGMENT_64 {
                let nsects = Int(try data.readUInt32(at: sliceStart + cursor + 64))
                var sectCursor = cursor + 72          // segment_command_64 头部之后的第一个 section
                for _ in 0..<nsects {
                    // section_64: size@40(u64), offset@48(u32)
                    let size   = Int(try data.readUInt64(at: sliceStart + sectCursor + 40))
                    let offset = Int(try data.readUInt32(at: sliceStart + sectCursor + 48))
                    if offset > 0 && size > 0 { minOffset = min(minOffset, offset) }
                    sectCursor += 80                   // sizeof(section_64)
                }
            }
            cursor += cmdsize
            guard cmdsize > 0 else { throw MachOPatcher_truncated }
        }
        return minOffset
    }

    /// 追加一条 dylib 命令。
    mutating func appendDylib(path: String, weak: Bool) throws {
        let cmd = weak ? MachOPatcher_LC_LOAD_WEAK_DYLIB : MachOPatcher_LC_LOAD_DYLIB
        var payload = Data()
        payload.appendUInt32(cmd)
        // cmdsize 稍后填
        let namePad = alignedStringData(path, headerLen: Int(MachOPatcher_dylibNameOffset))
        let cmdsize = UInt32(MachOPatcher_dylibNameOffset) + UInt32(namePad.count - Int(MachOPatcher_dylibNameOffset))
        payload.appendUInt32(cmdsize)
        payload.appendUInt32(MachOPatcher_dylibNameOffset)  // name.offset
        payload.appendUInt32(2)                             // timestamp
        payload.appendUInt32(0x0001_0000)                   // current_version 1.0.0
        payload.appendUInt32(0x0001_0000)                   // compatibility_version 1.0.0
        payload.append(namePad[Int(MachOPatcher_dylibNameOffset)...])
        try insertCommand(payload)
    }

    /// 确保存在指向 `path` 的 LC_RPATH；已存在则返回 false。
    mutating func ensureRPath(_ path: String) throws -> Bool {
        if try listRPaths().contains(path) { return false }
        var payload = Data()
        payload.appendUInt32(MachOPatcher_LC_RPATH)
        let pathPad = alignedStringData(path, headerLen: Int(MachOPatcher_rpathPathOffset))
        payload.appendUInt32(UInt32(pathPad.count))
        payload.appendUInt32(MachOPatcher_rpathPathOffset)  // path.offset
        payload.append(pathPad[Int(MachOPatcher_rpathPathOffset)...])
        try insertCommand(payload)
        return true
    }

    /// 把一条完整 load command 写进 header 空隙，并更新 ncmds/sizeofcmds。
    private mutating func insertCommand(_ command: Data) throws {
        let insertAt = loadCommandsStart + Int(sizeofcmds)
        let firstSection = sliceStart + (try firstSectionFileOffset())
        let free = firstSection - insertAt
        guard free >= command.count else {
            throw MachOPatcher.PatchError.notEnoughSpace(slice: archName, need: command.count, have: max(free, 0))
        }
        // 空隙必须是零，避免覆盖有意义数据
        for i in insertAt..<(insertAt + command.count) {
            if data[i] != 0 { throw MachOPatcher.PatchError.notEnoughSpace(slice: archName, need: command.count, have: 0) }
        }
        data.replaceSubrange(insertAt..<(insertAt + command.count), with: command)
        data.writeUInt32(ncmds + 1, at: ncmdsOffset)
        data.writeUInt32(sizeofcmds + UInt32(command.count), at: sizeofcmdsOffset)
    }

    // MARK: 只读枚举

    func listLoadedLibraries() -> [String] {
        var out: [String] = []
        var cursor = MachOPatcher_headerSize64
        for _ in 0..<ncmds {
            guard let cmd = try? data.readUInt32(at: sliceStart + cursor),
                  let cmdsize = try? data.readUInt32(at: sliceStart + cursor + 4),
                  cmdsize > 0 else { break }
            if cmd == MachOPatcher_LC_LOAD_DYLIB || cmd == MachOPatcher_LC_LOAD_WEAK_DYLIB {
                if let s = readCStringInCommand(cursor: cursor, strOffsetField: 8) {
                    out.append(s)
                }
            } else if cmd == MachOPatcher_LC_RPATH {
                if let s = readCStringInCommand(cursor: cursor, strOffsetField: 8) {
                    out.append("@rpath -> \(s)")
                }
            }
            cursor += Int(cmdsize)
        }
        return out
    }

    private func listRPaths() throws -> [String] {
        var out: [String] = []
        var cursor = MachOPatcher_headerSize64
        for _ in 0..<ncmds {
            let cmd = try data.readUInt32(at: sliceStart + cursor)
            let cmdsize = try data.readUInt32(at: sliceStart + cursor + 4)
            guard cmdsize > 0 else { throw MachOPatcher_truncated }
            if cmd == MachOPatcher_LC_RPATH, let s = readCStringInCommand(cursor: cursor, strOffsetField: 8) {
                out.append(s)
            }
            cursor += Int(cmdsize)
        }
        return out
    }

    private func readCStringInCommand(cursor: Int, strOffsetField: Int) -> String? {
        guard let strOff = try? data.readUInt32(at: sliceStart + cursor + strOffsetField),
              let cmdsize = try? data.readUInt32(at: sliceStart + cursor + 4) else { return nil }
        let start = sliceStart + cursor + Int(strOff)
        let end = sliceStart + cursor + Int(cmdsize)
        guard start < end, end <= data.count else { return nil }
        let bytes = data[start..<end]
        let trimmed = bytes.prefix { $0 != 0 }
        return String(bytes: trimmed, encoding: .utf8)
    }
}

// MARK: - 字符串对齐（load command 需按 8 字节对齐）

private func alignedStringData(_ string: String, headerLen: Int) -> Data {
    var d = Data(count: headerLen)                 // 头部占位，后面 body 会覆盖
    let str = Array(string.utf8) + [0]             // null-terminated
    d.append(contentsOf: str)
    while d.count % 8 != 0 { d.append(0) }
    return d
}

// MARK: - Data 读写辅助（小端 / 大端）

private extension Data {
    func readUInt32(at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { throw MachOPatcher_truncated }
        return UInt32(self[offset]) | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16) | (UInt32(self[offset + 3]) << 24)
    }
    func readUInt64(at offset: Int) throws -> UInt64 {
        let lo = UInt64(try readUInt32(at: offset))
        let hi = UInt64(try readUInt32(at: offset + 4))
        return lo | (hi << 32)
    }
    func readUInt32BE(at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { throw MachOPatcher_truncated }
        return (UInt32(self[offset]) << 24) | (UInt32(self[offset + 1]) << 16)
            | (UInt32(self[offset + 2]) << 8) | UInt32(self[offset + 3])
    }
    func readUInt64BE(at offset: Int) throws -> UInt64 {
        let hi = UInt64(try readUInt32BE(at: offset))
        let lo = UInt64(try readUInt32BE(at: offset + 4))
        return (hi << 32) | lo
    }
    mutating func writeUInt32(_ value: UInt32, at offset: Int) {
        self[offset]     = UInt8(value & 0xff)
        self[offset + 1] = UInt8((value >> 8) & 0xff)
        self[offset + 2] = UInt8((value >> 16) & 0xff)
        self[offset + 3] = UInt8((value >> 24) & 0xff)
    }
    mutating func appendUInt32(_ value: UInt32) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
    }
}

// MARK: - 供 private struct 使用的常量别名（避免类型内 private 常量的可见性问题）

private let MachOPatcher_headerSize64 = 32
private let MachOPatcher_dylibNameOffset: UInt32 = 24
private let MachOPatcher_rpathPathOffset: UInt32 = 12
private let MachOPatcher_LC_LOAD_DYLIB: UInt32 = 0x0000_000c
private let MachOPatcher_LC_LOAD_WEAK_DYLIB: UInt32 = 0x8000_0018
private let MachOPatcher_LC_RPATH: UInt32 = 0x8000_001c
private let MachOPatcher_LC_SEGMENT_64: UInt32 = 0x0000_0019
private let MachOPatcher_truncated = MachOPatcher.PatchError.truncated
