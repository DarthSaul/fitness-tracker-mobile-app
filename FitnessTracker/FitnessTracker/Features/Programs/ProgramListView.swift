import SwiftUI

// The enclosing tab (ProgramsTab) provides the NavigationStack — this view is
// content-only and assumes a navigation context already exists.
struct ProgramListView: View {
    @State private var viewModel: ProgramListViewModel
    private let programRepository: ProgramRepository

    init(viewModel: ProgramListViewModel, programRepository: ProgramRepository) {
        _viewModel = State(initialValue: viewModel)
        self.programRepository = programRepository
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.programs.isEmpty {
                ProgressView("Loading programs…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            ScreenTitleHeader(title: "Programs", emoji: "🏋️")
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .alert("Error", isPresented: errorBinding) {
            Button("Retry") { Task { await viewModel.load() } }
            Button("Dismiss", role: .cancel) { viewModel.error = nil }
        } message: {
            Text(viewModel.error?.localizedDescription ?? "")
        }
        .alert("Couldn't update", isPresented: actionErrorBinding) {
            Button("OK", role: .cancel) { viewModel.actionError = nil }
        } message: {
            Text(viewModel.actionError ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            Picker("Filter", selection: $viewModel.filter) {
                ForEach(ProgramFilter.allCases) { f in
                    Text(f.label).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            // Match the Home tab's title → first-element gap (12pt).
            .padding(.top, 12)
            .padding(.bottom, 8)
            // Opaque full-width backing so the list scrolls *behind* a solid
            // bar instead of showing through the transparent picker — keeps
            // the toggle visually fixed in place.
            .frame(maxWidth: .infinity)
            .background(Color(.systemGroupedBackground))
            .zIndex(1)

            if viewModel.filteredPrograms.isEmpty {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: emptyIcon,
                    description: Text(emptyMessage)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                programList
            }
        }
    }

    private var programList: some View {
        List {
            ForEach(viewModel.filteredPrograms, id: \.id) { program in
                NavigationLink {
                    ProgramDetailView(
                        program: program,
                        listViewModel: viewModel,
                        repository: programRepository
                    )
                } label: {
                    ProgramRow(program: program, viewModel: viewModel)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button {
                        Task { await viewModel.toggleSave(programId: program.id) }
                    } label: {
                        if viewModel.isSaved(programId: program.id) {
                            Label("Unsave", systemImage: "bookmark.slash.fill")
                        } else {
                            Label("Save", systemImage: "bookmark.fill")
                        }
                    }
                    .tint(viewModel.isSaved(programId: program.id) ? .gray : .accentColor)
                }
            }
        }
        .listStyle(.insetGrouped)
        // Pull the list up close to the filter bar — the default grouped-list
        // top inset leaves them too far apart.
        .contentMargins(.top, 8, for: .scrollContent)
    }

    // MARK: - Empty state copy
    private var emptyTitle: String {
        switch viewModel.filter {
        case .all: return "No Programs"
        case .saved: return "No Saved Programs"
        case .active: return "No Active Program"
        }
    }

    private var emptyMessage: String {
        switch viewModel.filter {
        case .all: return "Programs will appear here once loaded."
        case .saved: return "Swipe a program in the All tab to save it."
        case .active: return "Open a saved program and tap Activate to start training."
        }
    }

    private var emptyIcon: String {
        switch viewModel.filter {
        case .all: return "dumbbell"
        case .saved: return "bookmark"
        case .active: return "play.circle"
        }
    }

    // MARK: - Bindings
    private var errorBinding: Binding<Bool> {
        Binding(get: { viewModel.error != nil }, set: { if !$0 { viewModel.error = nil } })
    }

    private var actionErrorBinding: Binding<Bool> {
        Binding(get: { viewModel.actionError != nil }, set: { if !$0 { viewModel.actionError = nil } })
    }
}

// MARK: - Row
private struct ProgramRow: View {
    let program: ProgramModel
    let viewModel: ProgramListViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(program.name)
                    .font(.headline)
                    .lineLimit(2)
                Spacer(minLength: 8)
                if viewModel.isActive(programId: program.id) {
                    Text("Active")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.green.opacity(0.2), in: Capsule())
                        .foregroundStyle(.green)
                } else if viewModel.isSaved(programId: program.id) {
                    Image(systemName: "bookmark.fill")
                        .font(.caption)
                        .foregroundStyle(.tint)
                }
            }
            if let description = program.programDescription, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}
