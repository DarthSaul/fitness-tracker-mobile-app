import OSLog

extension Logger {
    nonisolated private static let subsystem = "me.fitness-app.tracker"

    // MARK: - Categories
    nonisolated static let networking = Logger(subsystem: subsystem, category: "networking")
    nonisolated static let auth = Logger(subsystem: subsystem, category: "auth")
    nonisolated static let data = Logger(subsystem: subsystem, category: "data")
    nonisolated static let healthKit = Logger(subsystem: subsystem, category: "healthkit")
    nonisolated static let notifications = Logger(subsystem: subsystem, category: "notifications")
}
