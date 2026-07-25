import Foundation

@MainActor
final class OutputStore: ObservableObject {
    @Published private(set) var outputs: [SignedOutput] = []

    private let fileName = "outputs.json"

    init() {
        load()
    }

    func add(_ output: SignedOutput) {
        outputs.insert(output, at: 0)
        save()
    }

    func update(_ output: SignedOutput) {
        guard let i = outputs.firstIndex(where: { $0.id == output.id }) else { return }
        outputs[i] = output
        save()
    }

    func remove(_ output: SignedOutput) {
        outputs.removeAll { $0.id == output.id }
        save()
    }

    func clear() {
        outputs.removeAll()
        save()
    }

    private func load() {
        guard let url = Storage.docsURL(fileName),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([SignedOutput].self, from: data) else { return }
        outputs = list
    }

    private func save() {
        guard let url = Storage.docsURL(fileName),
              let data = try? JSONEncoder().encode(outputs) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
