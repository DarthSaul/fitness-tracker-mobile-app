import SwiftUI

/// One chip per emoji with a count above zero (the fixed five first, in
/// order), then a smiley-plus button that opens the picker. Tapping a chip
/// toggles my reaction; long-pressing one opens the who-reacted sheet.
struct ReactionBar: View {
    let reactions: [ReactionSummaryDTO]
    let onToggle: (String) -> Void
    let onShowReactors: (String) -> Void
    let onOpenPicker: () -> Void

    /// Bumped on my own taps only, so the haptic doesn't fire when counts
    /// change from a refresh.
    @State private var toggleCount = 0

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(Reactions.ordered(reactions)) { reaction in
                ReactionChip(reaction: reaction)
                    .onTapGesture {
                        toggleCount += 1
                        onToggle(reaction.emoji)
                    }
                    .onLongPressGesture(minimumDuration: 0.4) { onShowReactors(reaction.emoji) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(reaction.emoji), \(reaction.count)")
                    .accessibilityValue(reaction.mine ? "Reacted" : "")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction(named: "See who reacted") { onShowReactors(reaction.emoji) }
            }
            Button(action: onOpenPicker) {
                Image(systemName: "face.smiling")
                    .font(.system(size: 16))
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "plus")
                            .font(.system(size: 8, weight: .bold))
                            .offset(x: 4, y: 2)
                    }
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 30)
                    .background(SocialStyle.embed, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add reaction")
        }
        .sensoryFeedback(.impact(weight: .light), trigger: toggleCount)
    }
}

struct ReactionChip: View {
    let reaction: ReactionSummaryDTO

    var body: some View {
        HStack(spacing: 5) {
            Text(reaction.emoji).font(.system(size: 15))
            Text("\(reaction.count)")
                .font(.system(size: 14, weight: .semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .foregroundStyle(reaction.mine ? Color.blue : Color.secondary)
        .background(reaction.mine ? SocialStyle.mineFill : SocialStyle.embed, in: Capsule())
        .overlay {
            if reaction.mine {
                Capsule().strokeBorder(SocialStyle.mineStroke, lineWidth: 1)
            }
        }
        .contentShape(Capsule())
    }
}
