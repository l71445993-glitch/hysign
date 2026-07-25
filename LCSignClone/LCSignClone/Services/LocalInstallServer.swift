import Foundation

/// 本地 IPA 托管（学习版骨架）。
///
/// LCSign 用 GCDWebServer + OTAClient.signAndHost。
/// iOS OTA 安装需要：
/// 1. HTTPS（可用自签 + 信任，或 nip.io/sslip 反代）
/// 2. manifest.plist（itms-services://?action=download-manifest&url=...）
/// 3. IPA 的直接下载 URL
///
/// 本类生成 manifest 文本并模拟「托管中」状态；真机可换成 GCDWebServer/Swifter。
@MainActor
final class LocalInstallServer: ObservableObject {
    @Published var isRunning = false
    @Published var baseURL: URL?
    @Published var lastManifest: String = ""

    let preferredPort: UInt16 = 13141

    func start() {
        // 学习版：不真正绑端口（沙盒 + ATS + 证书链较复杂），只标记状态。
        isRunning = true
        baseURL = URL(string: "http://127.0.0.1:\(preferredPort)")
    }

    func stop() {
        isRunning = false
        baseURL = nil
    }

    func makeManifest(for output: SignedOutput, ipaURL: URL) -> String {
        let bundleID = output.bundleID
        let version = output.version
        let title = output.name
        let ipa = ipaURL.absoluteString
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>items</key>
          <array>
            <dict>
              <key>assets</key>
              <array>
                <dict>
                  <key>kind</key>
                  <string>software-package</string>
                  <key>url</key>
                  <string>\(ipa)</string>
                </dict>
              </array>
              <key>metadata</key>
              <dict>
                <key>bundle-identifier</key>
                <string>\(bundleID)</string>
                <key>bundle-version</key>
                <string>\(version)</string>
                <key>kind</key>
                <string>software</string>
                <key>title</key>
                <string>\(title)</string>
              </dict>
            </dict>
          </array>
        </dict>
        </plist>
        """
        lastManifest = xml
        return xml
    }

    func installURL(manifestURL: URL) -> URL {
        var c = URLComponents()
        c.scheme = "itms-services"
        c.queryItems = [
            URLQueryItem(name: "action", value: "download-manifest"),
            URLQueryItem(name: "url", value: manifestURL.absoluteString)
        ]
        return c.url!
    }
}
