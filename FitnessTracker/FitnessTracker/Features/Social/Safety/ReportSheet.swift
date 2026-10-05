import SwiftUI
import Observation

@Observable
@MainActor
final class ReportViewModel {
    enum Phase: Equatable {
        case composing
        case submitting
        /// Report accepted (`200` or `201`); offer to block next.
        case submitted
        case blocked
    }

    let target: ReportTarget
    var reason: ReportReason?
    var details = ""
    private(set) var phase: Phase = .composing
    private(set) var errorMessage: String?

    private let context: SocialContext

    init(target: ReportTarget, context: SocialContext) {
        self.target = target
        self.context = context
    }

    var isDetailsTooLong: Bool { details.count > SocialRules.reportDetailsMax }

    var canSubmit: Bool { reason != nil && !isDetailsTooLong && phase == .composing }

    /// Report first: blocking first would hide the post and make it
    /// unreportable.
    func submit() async {
        guard canSubmit, let reason else { return }
        phase = .submitting
        errorMessage = nil
        do {
            try await context.repository.report(target.body(reason: reason, details: details))
            phase = .submitted
        } catch {
            phase = .composing
            guard let failure = await context.failure(from: error) else { return }
            switch failure {
            case .notFound:
                errorMessage = "This is no longer available to report."
            default:
                errorMessage = failure.message
            }
        }
    }

    func block() async {
        if await SafetyActions(context: context).block(target.user) {
            phase = .blocked
        }
    }
}

/// Report a post or person: pick a reason (contract order), optionally add
/// details, submit, then offer to block.
struct ReportSheet: View {
    @State private var viewModel: ReportViewModel
    @State private var confirmBlock = false
    @Environment(\.dismiss) private var dismiss

    init(target: ReportTarget, context: SocialContext) {
        _viewModel = State(initialValue: ReportViewModel(target: target, context: context))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.phase {
                case .composing, .submitting:
                    form
                case .submitted, .blocked:
                    thanks
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(viewModel.phase == .composing || viewModel.phase == .submitting ? "Cancel" : "Done") { dismiss() }
                }
                if viewModel.phase == .composing || viewModel.phase == .submitting {
                    ToolbarItem(placement: .confirmationAction) {
                        if viewModel.phase == .submitting {
                            ProgressView()
                        } else {
                            Button("Submit") { Task { await viewModel.submit() } }
                                .disabled(!viewModel.canSubmit)
                        }
                    }
                }
            }
        }
        .confirmationAlert(
            "Block \(viewModel.target.user.displayName)?",
            isPresented: $confirmBlock,
            message: SafetyCopy.blockMessage,
            confirmLabel: "Block",
            confirmRole: .destructive
        ) {
            Task { await viewModel.block() }
        }
    }

    private var title: String {
        switch viewModel.target {
        case .post: "Report Post"
        case .user: "Report Account"
        }
    }

    private var form: some View {
        Form {
            Section {
                ForEach(ReportReason.allCases) { reason in
                    Button {
                        viewModel.reason = reason
                    } label: {
                        HStack {
                            Text(reason.title).foregroundStyle(.primary)
                            Spacer()
                            if viewModel.reason == reason {
                                Image(systemName: "checkmark").foregroundStyle(.blue)
                            }
                        }
                    }
                    .accessibilityAddTraits(viewModel.reason == reason ? .isSelected : [])
                }
            } header: {
                Text("Why are you reporting this?")
            }

            Section {
                TextField("Add details (optional)", text: $viewModel.details, axis: .vertical)
                    .lineLimit(3...6)
            } footer: {
                if viewModel.isDetailsTooLong {
                    Text("Details can be up to \(SocialRules.reportDetailsMax) characters.")
                        .foregroundStyle(.red)
                } else {
                    Text("Reports are private. \(viewModel.target.user.displayName) won't know who reported them.")
                }
            }

            if let error = viewModel.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                }
            }
        }
        .disabled(viewModel.phase == .submitting)
    }

    private var thanks: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text(SafetyCopy.reportThanks)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            if viewModel.phase == .blocked {
                Text("You've blocked \(viewModel.target.user.displayName).")
                    .foregroundStyle(.secondary)
            } else {
                Text("You can also block \(viewModel.target.user.displayName) so you no longer see each other.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Block \(viewModel.target.user.displayName)", role: .destructive) {
                    confirmBlock = true
                }
                .buttonStyle(.pill(.destructive, height: 44))
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
