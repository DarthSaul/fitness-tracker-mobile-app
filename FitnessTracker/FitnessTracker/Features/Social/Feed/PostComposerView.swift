import SwiftUI

/// Create-a-post card at the top of the Friends feed. Text only for now;
/// photos and workout shares come in a later pass.
struct PostComposerView: View {
    @Bindable var viewModel: FeedViewModel
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Share an update…", text: $viewModel.draft, axis: .vertical)
                .lineLimit(1...8)
                .focused($isFocused)
                .disabled(viewModel.isPosting)

            if let error = viewModel.postError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            HStack {
                // Show the counter only as the limit gets close.
                if viewModel.draftLength > SocialRules.postBodyMax - 200 {
                    Text("\(viewModel.draftLength)/\(SocialRules.postBodyMax)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(viewModel.isDraftTooLong ? .red : .secondary)
                }
                Spacer()
                Button {
                    Task {
                        await viewModel.submit()
                        if viewModel.postError == nil { isFocused = false }
                    }
                } label: {
                    if viewModel.isPosting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Post")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canSubmit)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        .onChange(of: viewModel.draft) {
            if viewModel.postError != nil { viewModel.clearPostError() }
        }
    }
}
