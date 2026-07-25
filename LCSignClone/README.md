# 华阳签

基于 LCSign 工作流的 iOS 签名工具（SwiftUI）。

- 显示名：**华阳签**
- Bundle ID：`com.huayang.sign`
- Tab：项目 / 应用 / 发现 / 文件 / 设置

## 开源注入层（往 IPA 塞 dylib）

不依赖闭源引擎，全部用开源技术在设备进程内完成：

| 步骤 | 实现 |
| --- | --- |
| 解包 IPA | `IPAPackager`（[ZIPFoundation](https://github.com/weichsel/ZIPFoundation)） |
| 拷 dylib | 复制到 `Payload/App.app/Frameworks/` |
| 改 Mach-O | `MachOPatcher`：进程内追加 `LC_LOAD_DYLIB @rpath/xxx.dylib` + `LC_RPATH`（等价 `insert_dylib` 的核心逻辑，纯 Swift，支持 thin/fat、arm64/arm64e） |
| 重打包 | `IPAPackager.zip` 还原标准 IPA 结构 |
| 重签 | 交 `SigningEngine`（zsign / codesign），Frameworks 内每个 dylib 单独签 |

用法：项目详情 → 「添加 dylib（往 IPA 塞）」选 `.dylib` → 签名并安装。

> `MachOPatcher` 只复用 header 与首个 section 之间的零填充空隙，空间不足会明确报错，不会写坏二进制。注入后必须重签，否则装不上。

## Mac 编译 IPA

```bash
cd LCSignClone
chmod +x scripts/build-ipa.sh
./scripts/build-ipa.sh
# 产出 HuaYangSign.ipa
```

## 安装到手机（ios-mcp）

```powershell
curl -H "X-Filename: HuaYangSign.ipa" --data-binary "@HuaYangSign.ipa" http://192.168.2.175:8090/upload_file
# 再用返回的 path 调用 install_app
```

Windows 本机无法编译；需要 macOS + Xcode。
