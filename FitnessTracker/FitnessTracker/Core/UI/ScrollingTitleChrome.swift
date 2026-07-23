import BlurSwiftUI
import BlurUIKit
import SwiftUI

/// Chrome for tab roots whose `ScreenTitleHeader` sits in the scroll flow
/// (not pinned): a progressive blur over the status-bar area so outgoing
/// content dissolves at the top edge, plus a small floating title chip that
/// appears once the user has scrolled down a bit.
///
/// Apply to the screen's scroll container (ScrollView / List), with the
/// `ScreenTitleHeader` placed as the first element of the scroll content.
struct ScrollingTitleChrome: ViewModifier {
    let title: String
    /// How far (points) the user must scroll before the chip appears.
    var chipThreshold: CGFloat = 24

    @State private var showTitleChip = false

    func body(content: Content) -> some View {
        content
            .onScrolledDownChange(threshold: chipThreshold) { showTitleChip = $0 }
            .overlay(alignment: .top) {
                // Progressive blur over the status-bar area, fading down into
                // the content — BlurUIKit's recreation of the system variable
                // blur. The frame height is the visible runoff below the
                // status bar; ignoresSafeArea extends it to the screen edge.
                VariableBlur(direction: .down)
                    .passesTouchesThrough(true)
                    .ignoresSafeArea(edges: .top)
                    .frame(height: 20)
            }
            .overlay(alignment: .top) {
                if showTitleChip {
                    Text(title)
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                        .padding(.top, 4)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.2), value: showTitleChip)
    }
}

extension View {
    /// See `ScrollingTitleChrome`.
    func scrollingTitleChrome(title: String) -> some View {
        modifier(ScrollingTitleChrome(title: title))
    }

    /// Reports whether the scroll view has been scrolled down past
    /// `threshold`. Uses `onScrollGeometryChange` (iOS 18+); earlier versions
    /// never report scrolled, so the title chip simply doesn't appear there.
    @ViewBuilder
    func onScrolledDownChange(
        threshold: CGFloat = 1,
        _ update: @escaping (Bool) -> Void
    ) -> some View {
        if #available(iOS 18.0, *) {
            onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > threshold
            } action: { _, scrolled in
                update(scrolled)
            }
        } else {
            self
        }
    }
}
