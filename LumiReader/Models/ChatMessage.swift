import Foundation

struct ChatMessage: Identifiable, Codable, Hashable, Equatable {
    let id: UUID
    let sender: Sender
    let content: String

    enum Sender: Codable, Hashable {
        case user
        case gemini
    }
} 