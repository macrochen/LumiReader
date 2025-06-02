import Foundation

struct ChatMessage: Identifiable, Codable, Hashable, Equatable {
    let id: UUID
    let sender: Sender
    let content: String

    enum Sender: String, Codable, Hashable {
        case user
        case gemini = "model"
    }
} 