import Foundation

struct EmailTemplate: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var subject: String
    var bodyHTML: String
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), name: String = "", subject: String = "", bodyHTML: String = "") {
        self.id = id
        self.name = name
        self.subject = subject
        self.bodyHTML = bodyHTML
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
