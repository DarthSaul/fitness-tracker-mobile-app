import Foundation

enum AuthState: Equatable {
    case unauthenticated
    case loading
    case authenticated(userId: String)
}
