import Foundation

// MARK: - Type

/// A notification `type`. New types are added server-side without a version
/// bump, so anything unrecognized decodes as `.unknown` and is hidden rather
/// than failing the page.
nonisolated enum NotificationType: Hashable, Sendable, Codable {
    case followRequest
    case newFollower
    case followAccepted
    case postReaction
    case workoutReminder
    case workoutUnfinished
    case unknown(String)

    /// The types the app knows how to render, in the order Settings lists them.
    static let known: [NotificationType] = [
        .followRequest, .newFollower, .followAccepted, .postReaction,
        .workoutReminder, .workoutUnfinished,
    ]

    init(rawValue: String) {
        switch rawValue {
        case "FOLLOW_REQUEST": self = .followRequest
        case "NEW_FOLLOWER": self = .newFollower
        case "FOLLOW_ACCEPTED": self = .followAccepted
        case "POST_REACTION": self = .postReaction
        case "WORKOUT_REMINDER": self = .workoutReminder
        case "WORKOUT_UNFINISHED": self = .workoutUnfinished
        default: self = .unknown(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .followRequest: "FOLLOW_REQUEST"
        case .newFollower: "NEW_FOLLOWER"
        case .followAccepted: "FOLLOW_ACCEPTED"
        case .postReaction: "POST_REACTION"
        case .workoutReminder: "WORKOUT_REMINDER"
        case .workoutUnfinished: "WORKOUT_UNFINISHED"
        case .unknown(let raw): raw
        }
    }

    var isKnown: Bool {
        if case .unknown = self { return false }
        return true
    }

    /// For the two workout types, turning push off stops the notification
    /// being created at all (no push, no inbox row). For social types it
    /// silences only the push.
    var preferenceDisablesEntirely: Bool {
        self == .workoutReminder || self == .workoutUnfinished
    }

    init(from decoder: any Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - Status

nonisolated enum NotificationStatus: String, Codable, Sendable, Hashable {
    case unread
    case read
    case dismissed

    /// An unrecognized status reads as `read` so it never inflates "unread".
    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = NotificationStatus(rawValue: raw) ?? .read
    }
}

// MARK: - Target

/// Deep-link ids only; fetch the resource itself. A `404` means it's gone:
/// show the row without a link.
nonisolated struct NotificationTargetDTO: Codable, Sendable, Hashable {
    var postId: String?
    var followId: String?
    var workoutSessionId: String?
    var standaloneSessionId: String?
    var scheduledWorkoutId: String?

    static let empty = NotificationTargetDTO()
}

// MARK: - Data

/// A JSON scalar in a notification's `data` snapshot. The server writes
/// strings and numbers; booleans are accepted too so a future field can't
/// fail the page.
nonisolated enum NotificationDataValue: Codable, Sendable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        }
    }

    var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var int: Int? {
        switch self {
        case .number(let value): return Int(exactly: value)
        case .string(let value): return Int(value)
        case .bool: return nil
        }
    }
}

/// The render snapshot: `{ emoji }` for a reaction; `{ programName,
/// weekNumber, dayNumber, day }` for a workout reminder. Values that aren't
/// scalars are skipped rather than failing the notification.
nonisolated struct NotificationDataDTO: Codable, Sendable, Hashable {
    var values: [String: NotificationDataValue]

    init(_ values: [String: NotificationDataValue] = [:]) {
        self.values = values
    }

    private struct AnyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        var values: [String: NotificationDataValue] = [:]
        for key in container.allKeys {
            if let value = try? container.decode(NotificationDataValue.self, forKey: key) {
                values[key.stringValue] = value
            }
        }
        self.values = values
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: AnyKey.self)
        for (key, value) in values {
            try container.encode(value, forKey: AnyKey(stringValue: key))
        }
    }

    var emoji: String? { values["emoji"]?.string }
    var programName: String? { values["programName"]?.string }
    var weekNumber: Int? { values["weekNumber"]?.int }
    var dayNumber: Int? { values["dayNumber"]?.int }
    /// `"today"` or `"tomorrow"` on a workout reminder.
    var day: String? { values["day"]?.string }
}

// MARK: - Item

nonisolated struct NotificationItemDTO: Codable, Sendable, Hashable, Identifiable {
    let id: String
    let type: NotificationType
    var status: NotificationStatus
    /// Kept raw: it's the paging cursor and the `read-all` boundary.
    let createdAt: WireTimestamp
    var readAt: Date?
    /// Nil for system notifications (workout reminders).
    let actor: PublicUserDTO?
    let target: NotificationTargetDTO
    let data: NotificationDataDTO

    var cursor: PageCursor {
        PageCursor(before: createdAt.raw, beforeId: id)
    }

    init(
        id: String,
        type: NotificationType,
        status: NotificationStatus,
        createdAt: WireTimestamp,
        readAt: Date? = nil,
        actor: PublicUserDTO?,
        target: NotificationTargetDTO = .empty,
        data: NotificationDataDTO = NotificationDataDTO()
    ) {
        self.id = id
        self.type = type
        self.status = status
        self.createdAt = createdAt
        self.readAt = readAt
        self.actor = actor
        self.target = target
        self.data = data
    }

    private enum CodingKeys: String, CodingKey {
        case id, type, status, createdAt, readAt, actor, target, data
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(NotificationType.self, forKey: .type)
        status = try container.decode(NotificationStatus.self, forKey: .status)
        createdAt = try container.decode(WireTimestamp.self, forKey: .createdAt)
        readAt = try container.decodeIfPresent(Date.self, forKey: .readAt)
        actor = try container.decodeIfPresent(PublicUserDTO.self, forKey: .actor)
        target = try container.decodeIfPresent(NotificationTargetDTO.self, forKey: .target) ?? .empty
        data = try container.decodeIfPresent(NotificationDataDTO.self, forKey: .data) ?? NotificationDataDTO()
    }
}

nonisolated struct NotificationsResponseDTO: Codable, Sendable {
    let notifications: [NotificationItemDTO]
}

nonisolated struct NotificationResponseDTO: Codable, Sendable {
    let notification: NotificationItemDTO
}

/// `{ count }` from unread-count and read-all.
nonisolated struct CountResponseDTO: Codable, Sendable, Hashable {
    let count: Int
}

// MARK: - Preferences

nonisolated enum WorkoutReminderDay: String, Codable, Sendable, Hashable, CaseIterable {
    case sameDay
    case dayBefore

    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = WorkoutReminderDay(rawValue: raw) ?? .sameDay
    }
}

/// `GET /api/notifications/preferences`. `push` is keyed by the raw type
/// string so types the app doesn't know yet survive a round trip.
nonisolated struct NotificationPreferencesDTO: Codable, Sendable, Hashable {
    var push: [String: Bool]
    var timezone: String?
    /// `"HH:MM"`, 24-hour.
    var workoutReminderTime: String
    var workoutReminderDay: WorkoutReminderDay

    /// Push defaults to on for a type the server didn't list.
    func isPushEnabled(_ type: NotificationType) -> Bool {
        push[type.rawValue] ?? true
    }
}
