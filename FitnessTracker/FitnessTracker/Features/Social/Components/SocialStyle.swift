import SwiftUI

/// Design tokens for the Friends screens (design-spec §6), expressed as
/// semantic system colors so light mode still works.
enum SocialStyle {
    // MARK: Spacing & radii
    static let screenInset: CGFloat = 20
    static let cardRadius: CGFloat = 22
    static let smallCardRadius: CGFloat = 18
    static let embedRadius: CGFloat = 16
    static let fieldRadius: CGFloat = 12

    // MARK: Colors
    static let background = Color(.systemBackground)
    static let card = Color(.secondarySystemBackground)
    static let embed = Color(.tertiarySystemBackground)
    static let fill = Color(.systemGray4)
    static let selectedSegment = Color(.systemGray3)
    static let tertiaryText = Color(.tertiaryLabel)

    static let brandPink = Color(red: 214 / 255, green: 58 / 255, blue: 249 / 255)
    static let brandRose = Color(red: 255 / 255, green: 55 / 255, blue: 95 / 255)
    /// `#D63AF9 → #FF375F`, top to bottom.
    static let brandGradient = LinearGradient(colors: [brandPink, brandRose], startPoint: .top, endPoint: .bottom)

    /// Fill and stroke for a reaction that's mine.
    static let mineFill = Color.blue.opacity(0.22)
    static let mineStroke = Color.blue.opacity(0.6)
}

// MARK: - Accent bar

extension View {
    /// A 4pt brand-gradient bar down the leading edge, exactly as tall as
    /// the content. Drawn as an overlay rather than an HStack sibling: a bare
    /// gradient takes whatever height it's offered, so outside a scroll view
    /// (the reaction-picker stage) it stretched the whole card.
    func leadingAccentBar(width: CGFloat = 4) -> some View {
        padding(.leading, width)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(SocialStyle.brandGradient)
                    .frame(width: width)
            }
    }
}

// MARK: - Circle icon button

/// 40×40 circular header button with an optional red count badge.
struct CircleIconLabel: View {
    let systemImage: String
    var badge: Int = 0

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(.primary)
            .frame(width: 40, height: 40)
            .background(SocialStyle.card, in: Circle())
            .overlay(alignment: .topTrailing) {
                if badge > 0 {
                    Text(badge > 99 ? "99+" : "\(badge)")
                        .font(.system(size: 11, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Color.red, in: Capsule())
                        .overlay(Capsule().stroke(SocialStyle.background, lineWidth: 2))
                        .offset(x: 3, y: -3)
                }
            }
    }
}

// MARK: - Avatar stack

/// Up to three overlapping 30pt avatars, ringed in the card color.
struct AvatarStack: View {
    let users: [PublicUserDTO]
    var size: CGFloat = 30

    var body: some View {
        HStack(spacing: -12) {
            ForEach(users.prefix(3)) { user in
                UserAvatarView(user: user, size: size)
                    .overlay(Circle().stroke(SocialStyle.card, lineWidth: 2))
            }
        }
    }
}

// MARK: - Pills

/// Capsule button styles from the spec: blue filled, blue tinted, gray.
struct PillButtonStyle: ButtonStyle {
    enum Tone {
        case blue, tinted, gray, destructive
    }

    var tone: Tone = .blue
    var height: CGFloat = 34
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: height)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }

    private var foreground: Color {
        switch tone {
        case .blue: .white
        case .tinted: .blue
        case .gray: .primary
        case .destructive: .red
        }
    }

    private var background: Color {
        switch tone {
        case .blue: .blue
        case .tinted: Color.blue.opacity(0.2)
        case .gray: SocialStyle.fill
        case .destructive: Color.red.opacity(0.16)
        }
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static func pill(_ tone: PillButtonStyle.Tone = .blue, height: CGFloat = 34, fullWidth: Bool = false) -> PillButtonStyle {
        PillButtonStyle(tone: tone, height: height, fullWidth: fullWidth)
    }
}

// MARK: - Segmented control

/// The spec's capsule segmented control: card-colored track, 3pt inset,
/// 36pt segments, selected segment gray.
struct SocialSegmentedControl<Value: Hashable>: View {
    let segments: [(value: Value, title: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<segments.count, id: \.self) { index in
                let segment = segments[index]
                let isSelected = segment.value == selection
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selection = segment.value }
                } label: {
                    Text(segment.title)
                        .font(.system(size: 15, weight: isSelected ? .semibold : .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background {
                            if isSelected {
                                Capsule().fill(SocialStyle.selectedSegment)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(SocialStyle.card, in: Capsule())
    }
}

// MARK: - Grouped card

/// A titled group: optional uppercase header, then rows on one rounded card
/// with inset separators between them.
struct SocialGroup<Content: View>: View {
    var header: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let header {
                SectionHeaderText(header)
                    .padding(.leading, 2)
            }
            VStack(spacing: 0) {
                content
            }
            .background(SocialStyle.card, in: RoundedRectangle(cornerRadius: SocialStyle.cardRadius, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: SocialStyle.cardRadius, style: .continuous))
        }
    }
}

/// "TODAY", "SUGGESTED" etc.: 13pt semibold, uppercase, secondary. Pass
/// `uppercased: false` to keep the text's own casing ("Following").
struct SectionHeaderText: View {
    let text: String
    var uppercased = true

    init(_ text: String, uppercased: Bool = true) {
        self.text = text
        self.uppercased = uppercased
    }

    var body: some View {
        Text(uppercased ? text.uppercased() : text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .tracking(0.3)
    }
}

/// A row inside `SocialGroup`, with a separator inset from the leading edge.
struct SocialRow<Content: View>: View {
    var separatorInset: CGFloat = 16
    var showsSeparator = true
    var verticalPadding: CGFloat = 12
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 12) {
            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if showsSeparator {
                Rectangle()
                    .fill(Color(.separator))
                    .frame(height: 0.5)
                    .padding(.leading, separatorInset)
            }
        }
    }
}

/// Footnote under a group: 13pt secondary.
struct GroupFootnote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineSpacing(2)
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Inline error card with a retry button, used in list areas.
struct RetryCard: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again", action: retry)
                .buttonStyle(.pill(.gray))
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(SocialStyle.card, in: RoundedRectangle(cornerRadius: SocialStyle.cardRadius, style: .continuous))
    }
}
