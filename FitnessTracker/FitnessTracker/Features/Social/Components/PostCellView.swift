import SwiftUI

/// One post, shared by the feed (and, later, a profile's posts and the
/// single-post screen). Read-only for now: reactions show their counts, and
/// the overflow menu (edit/delete, report/block) arrives with those features.
struct PostCellView: View {
    let post: PostDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            authorRow

            if !post.body.isEmpty {
                Text(post.body)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }

            if let workout = post.workout {
                Label(workout.line(authorName: post.author.displayName), systemImage: "figure.strengthtraining.traditional")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !post.photos.isEmpty {
                PostPhotoGrid(photos: post.photos)
            }

            if !post.reactions.isEmpty {
                reactionBar
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var authorRow: some View {
        HStack(spacing: 10) {
            UserAvatarView(user: post.author, size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(post.author.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(post.author.handle)
                    Text("·")
                    Text(post.createdAt.date, format: .relative(presentation: .named))
                    if post.editedAt != nil {
                        Text("· Edited")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var reactionBar: some View {
        HStack(spacing: 6) {
            ForEach(post.reactions) { reaction in
                HStack(spacing: 4) {
                    Text(reaction.emoji)
                    Text("\(reaction.count)")
                        .font(.caption.monospacedDigit())
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(reaction.mine ? Color.accentColor.opacity(0.18) : Color(.tertiarySystemFill))
                )
                .accessibilityLabel("\(reaction.emoji) \(reaction.count)\(reaction.mine ? ", including you" : "")")
            }
            Spacer(minLength: 0)
        }
    }
}

/// 1–4 photos in display order. A single photo keeps its aspect ratio (from
/// the payload's width/height, so the layout is right before it loads);
/// several share a square-cell grid.
private struct PostPhotoGrid: View {
    let photos: [PostPhotoDTO]

    var body: some View {
        if photos.count == 1, let photo = photos.first {
            PostPhotoView(photo: photo)
                .aspectRatio(min(max(photo.aspectRatio, 0.6), 2), contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            let columns = [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)]
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(photos) { photo in
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                        .overlay { PostPhotoView(photo: photo) }
                        .clipped()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

/// A signed photo URL. Identity is the photo id (`.id(photo.id)`), not the
/// URL, which changes on every fetch.
private struct PostPhotoView: View {
    let photo: PostPhotoDTO

    var body: some View {
        AsyncImage(url: URL(string: photo.url)) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .failure:
                Rectangle().fill(Color(.tertiarySystemFill))
                    .overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
            default:
                Rectangle().fill(Color(.tertiarySystemFill))
            }
        }
        .id(photo.id)
        .accessibilityLabel("Photo")
    }
}
