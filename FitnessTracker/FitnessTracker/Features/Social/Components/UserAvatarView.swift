import SwiftUI

/// A user's avatar: their image when they have one, otherwise initials on a
/// tinted circle (the same treatment as the Settings profile header).
struct UserAvatarView: View {
    let user: PublicUserDTO
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let url = user.avatarUrl.flatMap(URL.init(string:)) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        initialsCircle
                    }
                }
            } else {
                initialsCircle
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var initialsCircle: some View {
        ZStack {
            Circle().fill(Color.purple.opacity(0.15))
            Text(initials)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(.purple)
        }
    }

    private var initials: String {
        let source = user.name?.trimmingCharacters(in: .whitespaces).isEmpty == false ? user.name! : user.username
        let parts = source.split(separator: " ", maxSplits: 1)
        if parts.count == 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(source.prefix(1)).uppercased()
    }
}
