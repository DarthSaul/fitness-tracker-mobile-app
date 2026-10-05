import SwiftUI
import Observation

/// What a post card can ask its screen to present. One instance per screen
/// that lists posts, provided through the environment by
/// `.postInteractionHost(...)`.
@Observable
@MainActor
final class PostInteractions {
    /// The post lifted onto "center stage" (dimmed backdrop), and where it
    /// sits on screen. `mode` decides what floats with it.
    struct PickerTarget: Identifiable {
        enum Mode {
            /// The emoji tray (long-press, or the add-reaction button).
            case react
            /// The post menu: Report / Block, or Delete on my own post
            /// (the ⋯ button).
            case menu
        }

        let post: PostDTO
        let frame: CGRect
        var mode: Mode = .react
        var id: String { post.id }
    }

    /// The who-reacted sheet, opened on a given emoji.
    struct ReactorsTarget: Identifiable {
        let post: PostDTO
        let emoji: String
        var id: String { "\(post.id)|\(emoji)" }
    }

    var picker: PickerTarget?
    var reactors: ReactorsTarget?
    var report: ReportTarget?
    var blockCandidate: PublicUserDTO?
    var deleteCandidate: PostDTO?

    let context: SocialContext

    init(context: SocialContext) {
        self.context = context
    }

    func toggle(_ emoji: String, on post: PostDTO) {
        Task { await context.postActions.toggleReaction(emoji, on: post) }
    }

    /// Shows or hides the picker cover without the system slide-up, so the
    /// picker's own fade and lift are the only animation.
    func setPicker(_ target: PickerTarget?) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { picker = target }
    }
}

/// Presents everything a post card can trigger: the reaction picker, the
/// who-reacted sheet, the report sheet and the block/delete confirmations.
struct PostInteractionHost: ViewModifier {
    @State private var interactions: PostInteractions
    @Environment(SocialContext.self) private var context

    init(context: SocialContext) {
        _interactions = State(initialValue: PostInteractions(context: context))
    }

    func body(content: Content) -> some View {
        @Bindable var interactions = interactions
        content
            .environment(interactions)
            // A clear full-screen cover so the dimmed backdrop also covers
            // the tab bar; the picker animates its own appearance.
            .fullScreenCover(item: $interactions.picker) { target in
                ReactionPickerOverlay(target: target, interactions: interactions)
                    .presentationBackground(.clear)
            }
            .sheet(item: $interactions.reactors) { target in
                ReactorsSheet(post: target.post, initialEmoji: target.emoji, context: context)
                    .presentationDetents([.height(390), .large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(SocialStyle.cardRadius)
            }
            .sheet(item: $interactions.report) { target in
                ReportSheet(target: target, context: context)
            }
            .confirmationAlert(
                "Block \(interactions.blockCandidate?.displayName ?? "")?",
                isPresented: Binding(
                    get: { interactions.blockCandidate != nil },
                    set: { if !$0 { interactions.blockCandidate = nil } }
                ),
                message: SafetyCopy.blockMessage,
                confirmLabel: "Block",
                confirmRole: .destructive
            ) {
                if let user = interactions.blockCandidate {
                    Task { await SafetyActions(context: context).block(user) }
                }
            }
            .confirmationAlert(
                "Delete post?",
                isPresented: Binding(
                    get: { interactions.deleteCandidate != nil },
                    set: { if !$0 { interactions.deleteCandidate = nil } }
                ),
                message: "This removes the post and its photos for everyone. It can't be undone.",
                confirmLabel: "Delete",
                confirmRole: .destructive
            ) {
                if let post = interactions.deleteCandidate {
                    Task { await context.postActions.delete(post) }
                }
            }
    }
}

extension View {
    /// Hosts the picker, sheets and confirmations for the post cards inside.
    func postInteractionHost(context: SocialContext) -> some View {
        modifier(PostInteractionHost(context: context))
    }
}
