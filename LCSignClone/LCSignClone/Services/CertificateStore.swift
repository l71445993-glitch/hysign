import Foundation

@MainActor
final class CertificateStore: ObservableObject {
    @Published private(set) var certificates: [Certificate] = []
    @Published var activeCertificateID: UUID?

    private let fileName = "certificates.json"
    private let activeKey = "LC.activeCertificateID"

    init() {
        load()
        if certificates.isEmpty {
            certificates = DemoData.certificates
            activeCertificateID = certificates.first(where: { $0.isUsable })?.id
            save()
        } else if activeCertificateID == nil {
            activeCertificateID = certificates.first(where: { $0.isUsable })?.id
        }
    }

    var activeCertificate: Certificate? {
        certificates.first { $0.id == activeCertificateID }
    }

    func select(_ cert: Certificate) {
        activeCertificateID = cert.id
        UserDefaults.standard.set(cert.id.uuidString, forKey: activeKey)
    }

    func add(_ cert: Certificate) {
        certificates.append(cert)
        if activeCertificateID == nil { select(cert) }
        save()
    }

    func remove(_ cert: Certificate) {
        certificates.removeAll { $0.id == cert.id }
        if activeCertificateID == cert.id {
            activeCertificateID = certificates.first?.id
        }
        save()
    }

    func checkRevocation(for id: UUID) async {
        guard let i = certificates.firstIndex(where: { $0.id == id }) else { return }
        try? await Task.sleep(nanoseconds: 600_000_000)
        var c = certificates[i]
        if c.expirationDate <= Date() {
            c.revocationStatus = .expired
        } else {
            // 真实实现：构造 OCSP 请求打 ocsp.apple.com
            c.revocationStatus = .valid
        }
        c.lastCheckedAt = Date()
        certificates[i] = c
        save()
    }

    private func load() {
        if let s = UserDefaults.standard.string(forKey: activeKey), let id = UUID(uuidString: s) {
            activeCertificateID = id
        }
        guard let url = Storage.docsURL(fileName),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([Certificate].self, from: data) else { return }
        certificates = list
    }

    private func save() {
        guard let url = Storage.docsURL(fileName),
              let data = try? JSONEncoder().encode(certificates) else { return }
        try? data.write(to: url, options: .atomic)
        if let id = activeCertificateID {
            UserDefaults.standard.set(id.uuidString, forKey: activeKey)
        }
    }
}
