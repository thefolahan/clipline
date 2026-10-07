import Foundation

struct Shot: Identifiable, Codable, Equatable {
    var url: URL
    var added: Date
    var pinned: Bool
    var text: String?

    var id: URL { url }
}
