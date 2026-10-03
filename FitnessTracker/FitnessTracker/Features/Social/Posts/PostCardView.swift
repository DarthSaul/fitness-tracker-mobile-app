import SwiftUI

/// One post (design-spec 01): header, caption, an optional attachment, and
/// the reaction bar. Shared by the feed, profiles and the single-post screen.
/// Needs a `PostInteractions` in the environment (`.postInteractionHost`)
/// for the menu, the picker and the sheets.
struct PostCardView: View {
    let post: PostDTO
    /// Off while this card is the lifted copy inside the picker overlay.
    var isInteractive = true

    @Environment(PostInteractions.self) private var interactions
    @State private var frame: CGRect = .zero

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if !post.body.isEmpty {
                Text(post.body)
                    .font(.system(size: 16))
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let workout = post.workout {
                WorkoutShareEmbed(workout: workout, authorName: post.author.displayName)
            }
            if !post.photos.isEmpty {
                PostPhotos(photos: post.photos)
            }
            ReactionBar(
                reactions: post.reactions,
                onToggle: { interactions.toggle($0, on: post) },
                onShowReactors: { interactions.reactors = .init(post: post, emoji: $0) },
                onOpenPicker: { openPicker() }
            )
            .allowsHitTesting(isInteractive)
        }
        .padding(16)
        .background(SocialStyle.card, in: RoundedRectangle(cornerRadius: SocialStyle.cardRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: SocialStyle.cardRadius, style: .continuous))
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
        .onLongPressGesture(minimumDuration: 0.4) {
            if isInteractive { openPicker() }
        }
        // Medium haptic as the picker opens on this post (not when it closes).
        .sensoryFeedback(.impact(weight: .medium), trigger: interactions.picker?.id == post.id) { _, isOpen in isOpen }
        .accessibilityAction(named: "React") { openPicker() }
    }

    private func openPicker() {
        guard isInteractive else { return }
        interactions.setPicker(.init(post: post, frame: frame))
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            NavigationLink(value: FriendsRoute.profile(userId: post.author.id)) {
                HStack(spacing: 10) {
                    UserAvatarView(user: post.author, size: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(post.author.displayName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(metaLine)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!isInteractive)

            Spacer(minLength: 0)

            if isInteractive {
                PostMenu(post: post)
            }
        }
    }

    /// "Finished a workout · 2h"; other posts show just the time, plus
    /// "Edited" when the text changed after posting.
    private var metaLine: String {
        var parts: [String] = []
        if post.workout != nil { parts.append("Finished a workout") }
        parts.append(RelativeTime.short(post.createdAt.date))
        if post.editedAt != nil { parts.append("Edited") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Menu

/// The ellipsis menu. My posts: Delete. Others': Report and Block
/// (App Store Guideline 1.2). Reporting comes first so the post is still
/// visible to report; the report sheet then offers to block.
struct PostMenu: View {
    let post: PostDTO
    @Environment(PostInteractions.self) private var interactions

    var body: some View {
        Menu {
            PostMenuItems(post: post)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(SocialStyle.tertiaryText)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More")
    }
}

struct PostMenuItems: View {
    let post: PostDTO
    var onSelect: () -> Void = {}
    @Environment(PostInteractions.self) private var interactions

    var body: some View {
        if post.isMine {
            Button(role: .destructive) {
                onSelect()
                interactions.deleteCandidate = post
            } label: {
                Label("Delete post", systemImage: "trash")
            }
        } else {
            Button {
                onSelect()
                interactions.report = .post(post)
            } label: {
                Label("Report post…", systemImage: "exclamationmark.bubble")
            }
            Button(role: .destructive) {
                onSelect()
                interactions.blockCandidate = post.author
            } label: {
                Label("Block \(post.author.firstName)", systemImage: "hand.raised")
            }
        }
    }
}

// MARK: - Attachments

/// A shared workout, as text only (ADR 001): the program's name and the
/// fact of finishing, in the spec's embed styling (gradient accent bar).
/// No sets, weights, time or week/day ever reach another user.
struct WorkoutShareEmbed: View {
    let workout: SharedWorkoutDTO
    let authorName: String

    var body: some View {
        HStack(spacing: 0) {
            SocialStyle.brandGradient.frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.programName == nil ? "Completed a workout" : "Completed a workout from")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Text(workout.programName ?? "Strength on the Go")
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(2)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            Spacer(minLength: 0)
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 20))
                .foregroundStyle(SocialStyle.brandPink)
                .padding(.trailing, 14)
        }
        .background(SocialStyle.embed)
        .clipShape(RoundedRectangle(cornerRadius: SocialStyle.embedRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(workout.line(authorName: authorName))
    }
}

/// 1–4 photos in display order, 220pt tall. Each is identified by its photo
/// id (`.id`), not its signed URL, which changes on every fetch.
struct PostPhotos: View {
    let photos: [PostPhotoDTO]

    var body: some View {
        Group {
            switch photos.count {
            case 1:
                PostPhotoView(photo: photos[0])
            case 2:
                HStack(spacing: 4) {
                    ForEach(photos) { PostPhotoView(photo: $0) }
                }
            default:
                HStack(spacing: 4) {
                    PostPhotoView(photo: photos[0])
                    VStack(spacing: 4) {
                        ForEach(photos.dropFirst().prefix(3)) { PostPhotoView(photo: $0) }
                    }
                }
            }
        }
        .frame(height: 220)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: SocialStyle.embedRadius, style: .continuous))
    }
}

private struct PostPhotoView: View {
    let photo: PostPhotoDTO

    var body: some View {
        Color.clear
            .overlay {
                AsyncImage(url: URL(string: photo.url)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        SocialStyle.embed.overlay {
                            Image(systemName: "photo").foregroundStyle(.secondary)
                        }
                    default:
                        SocialStyle.embed
                    }
                }
            }
            .clipped()
            .id(photo.id)
            .accessibilityLabel("Photo")
    }
}

extension PublicUserDTO {
    /// The first word of the name, or the handle without a name.
    var firstName: String {
        if let name, let first = name.split(separator: " ").first, !first.isEmpty { return String(first) }
        return handle
    }
}
