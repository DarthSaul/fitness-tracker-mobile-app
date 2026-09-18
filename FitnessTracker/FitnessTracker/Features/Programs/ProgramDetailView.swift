import SwiftUI

struct ProgramDetailView: View {
    let program: ProgramModel
    let listViewModel: ProgramListViewModel
    private let repository: ProgramRepository

    @State private var detail: ProgramDetailDTO?
    @State private var isLoading = false
    @State private var loadError: Error?
    @State private var selectedDay: SelectedDay?

    init(program: ProgramModel, listViewModel: ProgramListViewModel, repository: ProgramRepository) {
        self.program = program
        self.listViewModel = listViewModel
        self.repository = repository
    }

    var body: some View {
        List {
            Section { header }

            if let detail {
                ForEach(detail.weeks, id: \.id) { week in
                    Section("Week \(week.weekNumber)") {
                        ForEach(Array(week.days.enumerated()), id: \.element) { index, dayId in
                            Button {
                                selectedDay = SelectedDay(id: dayId, dayNumber: index + 1)
                            } label: {
                                HStack {
                                    Text("Day \(index + 1)")
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }
            } else if isLoading {
                Section { ProgressView("Loading…") }
            }
        }
        .navigationTitle(program.name)
        .navigationBarTitleDisplayMode(.large)
        .task { await loadDetail() }
        .refreshable { await loadDetail() }
        .sheet(item: $selectedDay) { selection in
            ProgramDayDetailView(
                dayId: selection.id,
                dayNumber: selection.dayNumber,
                repository: repository
            )
        }
        .alert("Couldn't load program", isPresented: errorBinding) {
            Button("Retry") { Task { await loadDetail() } }
            Button("Dismiss", role: .cancel) { loadError = nil }
        } message: {
            Text(loadError?.localizedDescription ?? "")
        }
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let description = program.programDescription, !description.isEmpty {
                Text(description)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            if let weekCount = detail?.weeks.count {
                Label("\(weekCount) week\(weekCount == 1 ? "" : "s")", systemImage: "calendar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if listViewModel.isCompleted(programId: program.id) {
                let count = listViewModel.completedRunCount(programId: program.id)
                Label(count > 1 ? "Completed \(count) times" : "Completed", systemImage: "checkmark.seal.fill")
                    .font(.subheadline)
                    .foregroundStyle(.purple)
            }
            HStack(spacing: 8) {
                saveButton
                activateButton
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 4)
    }

    private var saveButton: some View {
        Button {
            Task { await listViewModel.toggleSave(programId: program.id) }
        } label: {
            HStack(spacing: 6) {
                if listViewModel.isSaving(programId: program.id) {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: listViewModel.isSaved(programId: program.id) ? "bookmark.fill" : "bookmark")
                }
                Text(listViewModel.isSaved(programId: program.id) ? "Saved" : "Save")
            }
        }
        .buttonStyle(.bordered)
        .disabled(listViewModel.isSaving(programId: program.id))
    }

    @ViewBuilder
    private var activateButton: some View {
        if listViewModel.isSaved(programId: program.id) {
            let isActive = listViewModel.isActive(programId: program.id)
            let isActivating = listViewModel.isActivating(programId: program.id)
            // A finished run is never resumed — activating it starts a fresh
            // run at week 1 day 1, so the action reads "Start again".
            let isCompleted = !isActive && listViewModel.isCompleted(programId: program.id)
            Button {
                Task { await listViewModel.toggleActive(programId: program.id) }
            } label: {
                HStack(spacing: 6) {
                    if isActivating {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: isActive ? "stop.circle.fill" : (isCompleted ? "arrow.clockwise.circle.fill" : "play.circle.fill"))
                    }
                    Text(isActive ? "Deactivate" : (isCompleted ? "Start again" : "Activate"))
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(isActive ? .red : .green)
            .disabled(isActivating)
        }
    }

    private func loadDetail() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            detail = try await repository.fetchProgramDetail(id: program.id)
        } catch {
            loadError = error
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { loadError != nil }, set: { if !$0 { loadError = nil } })
    }

    private struct SelectedDay: Identifiable, Hashable {
        let id: String
        let dayNumber: Int
    }
}
