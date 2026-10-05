import SwiftUI

/// A user's avatar: their image when they have one, otherwise initials on a
/// hue-tinted circle. The hue is derived from the user id, so a person keeps
/// the same color everywhere.
struct UserAvatarView: View {
    let user: PublicUserDTO
    var size: CGFloat = 40

    var body: some View {
        InitialsAvatar(
            seed: user.id,
            name: user.name,
            fallback: user.username,
            imageURL: user.avatarUrl.flatMap(URL.init(string:)),
            size: size
        )
    }
}

/// The avatar drawing, usable for the signed-in user (whose profile isn't a
/// `PublicUserDTO`) as well.
struct InitialsAvatar: View {
    let seed: String
    let name: String?
    let fallback: String
    var imageURL: URL?
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let imageURL {
                AsyncImage(url: imageURL) { phase in
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
        let hue = Self.hue(for: seed)
        return ZStack {
            Circle().fill(Color(hue: hue, saturation: 0.55, brightness: 0.38))
            Text(initials)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(Color(hue: hue, saturation: 0.45, brightness: 0.95))
        }
    }

    private var initials: String {
        let trimmed = name?.trimmingCharacters(in: .whitespaces) ?? ""
        let source = trimmed.isEmpty ? fallback : trimmed
        let words = source.split(separator: " ").prefix(2)
        let letters = words.compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "·" : letters.uppercased()
    }

    /// A stable hue in 0..<1 from the seed (FNV-1a, so it doesn't change
    /// between launches the way `hashValue` does).
    static func hue(for seed: String) -> Double {
        var hash: UInt32 = 2_166_136_261
        for byte in seed.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return Double(hash % 360) / 360
    }
}
