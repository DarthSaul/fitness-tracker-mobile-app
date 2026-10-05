import Foundation
import Observation
import OSLog

/// What the post-workout share prompt shows about the workout just finished.
/// These are the user's own stats, shown only to them; the post they share
/// carries just the program's name (ADR 001).
nonisolated struct WorkoutCompletionSummary: Equatable, Sendable {
    /// The id field the post needs (program vs standalone session).
    let share: CreatePostBody.SharedWorkout
    /// Program or standalone workout name, when known up front.
    var title: String?
    /// "Week 2 · Day 4" for a program workout.
    var position: String?
    let sets: Int
    let duration: TimeInterval
    let volumeLbs: Double

    /// "Arm Farm 2 · Week 2 · Day 4".
    var subtitle: String {
        [title, position].compactMap { $0 }.joined(separator: " · ")
    }

    var formattedDuration: String {
        let minutes = max(Int((duration / 60).rounded()), 0)
        guard minutes >= 60 else { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    var formattedVolume: String {
        volumeLbs >= 1000 ? String(format: "%.1fk", volumeLbs / 1000) : String(format: "%.0f", volumeLbs)
    }

    static func program(_ session: ActiveWorkoutResponseDTO.ActiveWorkoutSession, now: Date = .now) -> WorkoutCompletionSummary {
        WorkoutCompletionSummary(
            share: .program(sessionId: session.id),
            title: nil,
            position: "Week \(session.weekNumber) · Day \(session.dayNumber)",
            sets: session.completedSets.count,
            duration: now.timeIntervalSince(session.startedAt),
            volumeLbs: volume(session.completedSets.map { ($0.reps, $0.weight) })
        )
    }

    static func standalone(
        _ session: StandaloneSessionDetailResponseDTO.SessionWithSets,
        workoutName: String,
        now: Date = .now
    ) -> WorkoutCompletionSummary {
        WorkoutCompletionSummary(
            share: .standalone(sessionId: session.id),
            title: workoutName,
            position: nil,
            sets: session.completedSets.count,
            duration: now.timeIntervalSince(session.startedAt),
            volumeLbs: volume(session.completedSets.map { ($0.reps, $0.weight) })
        )
    }

    /// Σ reps × weight over sets that have both.
    static func volume(_ sets: [(reps: Int?, weight: Double?)]) -> Double {
        sets.reduce(0) { total, set in
            guard let reps = set.reps, let weight = set.weight else { return total }
            return total + Double(reps) * weight
        }
    }
}

/// The post-workout share prompt (design-spec 05): shown right after a
/// workout is completed, offering to post it to followers with a caption.
@Observable
@MainActor
final class PostWorkoutShareViewModel {
    static let captionMax = ComposeViewModel.captionMax

    private(set) var summary: WorkoutCompletionSummary
    var caption = ""
    /// My follower count, for "48 followers will see it"; nil until loaded.
    private(set) var followerCount: Int?
    private(set) var isSharing = false
    private(set) var errorMessage: String?
    /// Flips on a successful share, for the success haptic.
    private(set) var didShare = false

    private let context: SocialContext
    private let historyRepository: HistoryRepository
    /// The App Store Guideline 1.2 terms-of-use seam, as in the composer.
    private let canPost: @MainActor () -> Bool

    init(
        summary: WorkoutCompletionSummary,
        context: SocialContext,
        historyRepository: HistoryRepository,
        canPost: @escaping @MainActor () -> Bool = { true }
    ) {
        self.summary = summary
        self.context = context
        self.historyRepository = historyRepository
        self.canPost = canPost
    }

    // MARK: - Loading

    /// Follower count, plus the program's name for a program workout (the
    /// live session doesn't carry it; the newest history row does, even
    /// when this workout finished the program).
    func load() async {
        async let count = loadFollowerCount()
        async let name = loadProgramName()
        let (followers, programName) = await (count, name)
        followerCount = followers
        if summary.title == nil, let programName { summary.title = programName }
    }

    private func loadFollowerCount() async -> Int? {
        guard let userId = context.currentUserId else { return nil }
        return try? await context.repository.fetchProfile(userId: userId).followerCount
    }

    private func loadProgramName() async -> String? {
        guard case .program(let sessionId) = summary.share else { return nil }
        let recent = try? await historyRepository.fetchHistory(limit: 5)
        for entry in recent ?? [] {
            if case .program(let session) = entry, session.id == sessionId { return session.programName }
        }
        return nil
    }

    // MARK: - Copy

    /// "48 followers will see it on their timeline."
    var audienceText: String {
        switch followerCount {
        case .some(0):
            return "No one follows you yet. It'll show on your profile."
        case .some(1):
            return "1 follower will see it on their timeline."
        case .some(let count):
            return "\(count) followers will see it on their timeline."
        case nil:
            return "Your followers will see it on their timeline."
        }
    }

    var isCaptionTooLong: Bool { SocialRules.postBodyLength(caption) > Self.captionMax }

    var canShare: Bool { !isSharing && !isCaptionTooLong }

    // MARK: - Share

    /// Posts the workout with the caption. Returns whether the prompt can
    /// close (shared, or already shared before).
    func share() async -> Bool {
        guard canShare, canPost() else { return false }
        isSharing = true
        errorMessage = nil
        defer { isSharing = false }
        do {
            let post = try await context.repository.createPost(CreatePostBody(body: caption, sharing: summary.share))
            context.events.send(.postCreated(post))
            didShare = true
            return true
        } catch {
            guard let failure = await context.failure(from: error) else { return false }
            Logger.data.error("Share workout failed: \(error)")
            if case .conflict(let message) = failure, message == "Workout already shared" {
                // A retried tap after a post that did go through: it's shared.
                return true
            }
            errorMessage = failure.message
            return false
        }
    }
}
