import SwiftUI

/// The post "center stage" (design-spec 02): the screen dims and blurs and
/// the post lifts in place. In `.react` mode (long-press, add-reaction
/// button) a tray of the five reactions floats above it; in `.menu` mode
/// (⋯ button) the post menu sits below it instead. Presented as a clear
/// full-screen cover so the backdrop also covers the tab bar.
struct ReactionPickerOverlay: View {
    let target: PostInteractions.PickerTarget
    let interactions: PostInteractions

    @State private var isShown = false
    @State private var pickedCount = 0

    private let trayHeight: CGFloat = 56
    private let gap: CGFloat = 10

    var body: some View {
        GeometryReader { proxy in
            let screen = proxy.frame(in: .global)
            let card = target.frame
            ZStack(alignment: .topLeading) {
                backdrop

                PostCardView(post: target.post, isInteractive: false)
                    .environment(interactions)
                    .frame(width: card.width)
                    .scaleEffect(isShown ? 1.02 : 1)
                    .shadow(color: .black.opacity(isShown ? 0.6 : 0), radius: 30, y: 20)
                    .offset(x: card.minX - screen.minX, y: card.minY - screen.minY)
                    .allowsHitTesting(false)

                switch target.mode {
                case .react:
                    tray
                        .scaleEffect(isShown ? 1 : 0.8, anchor: .bottomLeading)
                        .opacity(isShown ? 1 : 0)
                        .offset(x: card.minX - screen.minX + 8, y: trayY(card: card, screen: screen))
                case .menu:
                    menu
                        .frame(width: card.width)
                        .scaleEffect(isShown ? 1 : 0.95, anchor: .top)
                        .opacity(isShown ? 1 : 0)
                        .offset(x: card.minX - screen.minX, y: menuY(card: card, screen: screen))
                }
            }
            .frame(width: screen.width, height: screen.height, alignment: .topLeading)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.spring(duration: 0.28)) { isShown = true }
        }
    }

    // MARK: Pieces

    private var backdrop: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(Color.black.opacity(0.55))
            .opacity(isShown ? 1 : 0)
            .ignoresSafeArea()
            .onTapGesture { dismiss() }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Close")
    }

    private var tray: some View {
        HStack(spacing: 2) {
            ForEach(Reactions.quick, id: \.self) { emoji in
                let isMine = Reactions.isMine(emoji, in: target.post.reactions)
                Button {
                    pickedCount += 1
                    interactions.toggle(emoji, on: target.post)
                    dismiss()
                } label: {
                    Text(emoji)
                        .font(.system(size: isMine ? 32 : 28))
                        .frame(width: 44, height: 44)
                        .background {
                            if isMine { Circle().fill(Color.blue.opacity(0.25)) }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(emoji)
                .accessibilityValue(isMine ? "Reacted" : "")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: trayHeight)
        .background(SocialStyle.embed, in: Capsule())
        .shadow(color: .black.opacity(0.5), radius: 15, y: 10)
        .sensoryFeedback(.impact(weight: .light), trigger: pickedCount)
    }

    private var menu: some View {
        VStack(spacing: 0) {
            PostMenuItems(post: target.post, onSelect: { dismiss() })
                .environment(interactions)
                .buttonStyle(PickerMenuRowStyle())
        }
        .background(SocialStyle.embed.opacity(0.96), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: Layout

    /// Above the card, kept clear of the status bar.
    private func trayY(card: CGRect, screen: CGRect) -> CGFloat {
        max(card.minY - screen.minY - trayHeight - gap, 60)
    }

    /// Below the card, kept on screen.
    private func menuY(card: CGRect, screen: CGRect) -> CGFloat {
        let menuHeight: CGFloat = target.post.isMine ? 50 : 100
        return min(card.maxY - screen.minY + 12, screen.height - menuHeight - 40)
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.15)) { isShown = false }
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            interactions.setPicker(nil)
        }
    }
}

/// A menu row in the picker: label left, glyph right, separators between.
private struct PickerMenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(TrailingIconLabelStyle())
            .font(.system(size: 16))
            .foregroundStyle(configuration.role == .destructive ? Color.red : Color.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(configuration.isPressed ? Color.primary.opacity(0.08) : .clear)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color(.separator)).frame(height: 0.5)
            }
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.title
            Spacer()
            configuration.icon
        }
    }
}
