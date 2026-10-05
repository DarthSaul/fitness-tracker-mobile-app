import SwiftUI

/// Post-workout share prompt (design-spec 05), shown in the live-workout
/// cover right after the user confirms Complete: a hero, the workout's
/// highlights (sets · time · lbs), then a card offering to share it.
struct PostWorkoutShareView: View {
    @State private var viewModel: PostWorkoutShareViewModel
    private let onDone: () -> Void
    @FocusState private var captionFocused: Bool

    init(viewModel: PostWorkoutShareViewModel, onDone: @escaping () -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.onDone = onDone
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                    .padding(.top, 60)
                highlights
                    .padding(.top, 26)
                shareCard
                    .padding(.top, 12)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemBackground))
        .task { await viewModel.load() }
        .sensoryFeedback(.success, trigger: viewModel.didShare)
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 4) {
            Text("💪")
                .font(.system(size: 56))
                .accessibilityHidden(true)
            Text("Workout complete")
                .font(.system(size: 30, weight: .bold))
                .padding(.top, 4)
            if !viewModel.summary.subtitle.isEmpty {
                Text(viewModel.summary.subtitle)
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Highlights

    private var highlights: some View {
        HStack(spacing: 10) {
            highlight(value: "\(viewModel.summary.sets)", label: viewModel.summary.sets == 1 ? "set" : "sets")
            highlight(value: viewModel.summary.formattedDuration, label: "time")
            highlight(value: viewModel.summary.formattedVolume, label: "lbs")
        }
    }

    private func highlight(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 24, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: Share card

    private var shareCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Share with friends?")
                .font(.system(size: 17, weight: .semibold))
            Text(viewModel.audienceText)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            TextField("Add a caption…", text: $viewModel.caption, axis: .vertical)
                .font(.system(size: 15))
                .lineLimit(1...5)
                .focused($captionFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.top, 14)

            if viewModel.isCaptionTooLong {
                Text("Captions can be up to \(PostWorkoutShareViewModel.captionMax) characters.")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.top, 6)
            }
            if let error = viewModel.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.top, 8)
            }

            buttons
                .padding(.top, 18)
        }
        .padding(20)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var buttons: some View {
        // "Share" gets 1.4× the width of "Not now".
        GeometryReader { proxy in
            let spacing: CGFloat = 10
            let unit = (proxy.size.width - spacing) / 2.4
            HStack(spacing: spacing) {
                Button {
                    onDone()
                } label: {
                    Text("Not now")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: unit, height: 50)
                        .background(Color(.systemGray4), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isSharing)

                Button {
                    captionFocused = false
                    Task { if await viewModel.share() { onDone() } }
                } label: {
                    Group {
                        if viewModel.isSharing {
                            ProgressView().tint(.white)
                        } else {
                            Text("Share")
                                .font(.system(size: 17, weight: .semibold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(width: unit * 1.4, height: 50)
                    .background(Color.blue, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canShare)
                .opacity(viewModel.canShare ? 1 : 0.5)
            }
        }
        .frame(height: 50)
    }
}
