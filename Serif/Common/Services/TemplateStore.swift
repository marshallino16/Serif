import Foundation

@MainActor
final class TemplateStore: ObservableObject {
    static let shared = TemplateStore()

    @Published var templates: [EmailTemplate] = []

    private var accountID = ""

    private init() {}

    // MARK: - Account

    func load(accountID: String) {
        self.accountID = accountID
        templates = read(accountID: accountID)
    }

    // MARK: - CRUD

    func save(_ template: EmailTemplate, accountID: String? = nil) {
        let aid = accountID ?? self.accountID
        var list = read(accountID: aid)
        if let index = list.firstIndex(where: { $0.id == template.id }) {
            var updated = template
            updated.updatedAt = Date()
            list[index] = updated
        } else {
            list.append(template)
        }
        write(list, accountID: aid)
        if aid == self.accountID { templates = list }
    }

    func delete(id: UUID, accountID: String? = nil) {
        let aid = accountID ?? self.accountID
        var list = read(accountID: aid)
        list.removeAll { $0.id == id }
        write(list, accountID: aid)
        if aid == self.accountID { templates = list }
    }

    func deleteAccount(_ accountID: String) {
        UserDefaults.standard.removeObject(forKey: key(for: accountID))
    }

    // MARK: - Persistence

    private func key(for accountID: String) -> String {
        "com.serif.templates.\(accountID)"
    }

    private func read(accountID: String) -> [EmailTemplate] {
        guard let data = UserDefaults.standard.data(forKey: key(for: accountID)),
              let decoded = try? JSONDecoder().decode([EmailTemplate].self, from: data) else {
            return []
        }
        return decoded
    }

    private func write(_ templates: [EmailTemplate], accountID: String) {
        let data = try? JSONEncoder().encode(templates)
        UserDefaults.standard.set(data, forKey: key(for: accountID))
    }
}
