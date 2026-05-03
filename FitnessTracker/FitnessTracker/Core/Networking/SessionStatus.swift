import Foundation

nonisolated enum SessionStatus: String, Codable, Sendable {
    case inProgress = "IN_PROGRESS"
    case editing = "EDITING"
    case completed = "COMPLETED"
}
