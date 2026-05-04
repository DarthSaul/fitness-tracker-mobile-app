import SwiftUI

struct ProgramListView: View {
    @State private var viewModel: ProgramListViewModel

    init(viewModel: ProgramListViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.programs.isEmpty {
                    ProgressView("Loading programs…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.programs.isEmpty {
                    ContentUnavailableView(
                        "No Programs",
                        systemImage: "dumbbell",
                        description: Text("Programs will appear here once loaded.")
                    )
                } else {
                    List(viewModel.programs, id: \.id) { program in
                        ProgramRow(program: program)
                    }
                    .listStyle(.insetGrouped)
                    .refreshable { await viewModel.loadPrograms() }
                }
            }
            .navigationTitle("Programs")
            .task { await viewModel.loadPrograms() }
            .alert("Error", isPresented: Binding(
                get: { viewModel.error != nil },
                set: { if !$0 { viewModel.error = nil } }
            )) {
                Button("Retry") { Task { await viewModel.loadPrograms() } }
                Button("Dismiss", role: .cancel) { viewModel.error = nil }
            } message: {
                Text(viewModel.error?.localizedDescription ?? "")
            }
        }
    }
}

// MARK: - Row
private struct ProgramRow: View {
    let program: ProgramModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(program.name)
                .font(.headline)
            if !program.programDescription.isEmpty {
                Text(program.programDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}
