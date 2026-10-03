import SwiftUI
import Observation
import OSLog

@Observable
@MainActor
final class NotificationPreferencesViewModel {
    private(set) var preferences: NotificationPreferencesDTO?
    private(set) var loadError: APIFailure?
    private(set) var isSaving = false

    private let repository: NotificationsRepository
    private let context: SocialContext

    init(repository: NotificationsRepository, context: SocialContext) {
        self.repository = repository
        self.context = context
    }

    func load() async {
        loadError = nil
        do {
            preferences = try await repository.preferences()
        } catch {
            loadError = await context.failure(from: error)
        }
    }

    func isOn(_ type: NotificationType) -> Bool {
        preferences?.isPushEnabled(type) ?? true
    }

    func set(_ type: NotificationType, _ isOn: Bool) async {
        await save(UpdateNotificationPreferencesBody(push: [type.rawValue: isOn])) {
            $0.push[type.rawValue] = isOn
        }
    }

    /// "HH:MM" ⇄ a Date today, for the time picker.
    var reminderTime: Date {
        let parts = (preferences?.workoutReminderTime ?? "08:00").split(separator: ":").compactMap { Int($0) }
        let components = DateComponents(hour: parts.first ?? 8, minute: parts.count > 1 ? parts[1] : 0)
        return Calendar.current.date(from: components) ?? .now
    }

    func setReminderTime(_ date: Date) async {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let value = String(format: "%02d:%02d", components.hour ?? 8, components.minute ?? 0)
        guard value != preferences?.workoutReminderTime else { return }
        await save(UpdateNotificationPreferencesBody(workoutReminderTime: value)) { $0.workoutReminderTime = value }
    }

    func setReminderDay(_ day: WorkoutReminderDay) async {
        await save(UpdateNotificationPreferencesBody(workoutReminderDay: day)) { $0.workoutReminderDay = day }
    }

    private func save(_ body: UpdateNotificationPreferencesBody, optimistic change: (inout NotificationPreferencesDTO) -> Void) async {
        guard let original = preferences else { return }
        var updated = original
        change(&updated)
        preferences = updated
        isSaving = true
        defer { isSaving = false }
        do {
            preferences = try await repository.updatePreferences(body)
        } catch {
            preferences = original
            guard let failure = await context.failure(from: error) else { return }
            Logger.app.error("Preferences update failed: \(error.localizedDescription, privacy: .public)")
            context.toasts.show("Couldn't save that setting. \(failure.message)")
        }
    }
}

/// Settings → Notifications (not mocked; standard grouped form).
struct NotificationPreferencesView: View {
    @State private var viewModel: NotificationPreferencesViewModel

    init(repository: NotificationsRepository, context: SocialContext) {
        _viewModel = State(initialValue: NotificationPreferencesViewModel(repository: repository, context: context))
    }

    var body: some View {
        Form {
            if viewModel.preferences != nil {
                Section {
                    toggle("Follow requests", .followRequest)
                    toggle("New followers", .newFollower)
                    toggle("Accepted requests", .followAccepted)
                    toggle("Reactions to your posts", .postReaction)
                } header: {
                    Text("Push notifications")
                } footer: {
                    Text("Turning these off silences the push only. You'll still see them in Activity.")
                }

                Section {
                    toggle("Workout reminders", .workoutReminder)
                    if viewModel.isOn(.workoutReminder) {
                        Picker("Remind me", selection: Binding(
                            get: { viewModel.preferences?.workoutReminderDay ?? .sameDay },
                            set: { day in Task { await viewModel.setReminderDay(day) } }
                        )) {
                            Text("On the day").tag(WorkoutReminderDay.sameDay)
                            Text("The day before").tag(WorkoutReminderDay.dayBefore)
                        }
                        DatePicker(
                            "At",
                            selection: Binding(
                                get: { viewModel.reminderTime },
                                set: { date in Task { await viewModel.setReminderTime(date) } }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                    }
                    toggle("Unfinished workout reminders", .workoutUnfinished)
                } header: {
                    Text("Workout reminders")
                } footer: {
                    Text("Turning a reminder off stops it entirely, in Activity as well as push. Reminders are only sent for your active program: deactivating a program silences reminders for its scheduled workouts.")
                }
            } else if let error = viewModel.loadError {
                Section {
                    RetryCard(message: error.message) { Task { await viewModel.load() } }
                }
                .listRowBackground(Color.clear)
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .tint(.green)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }

    private func toggle(_ title: String, _ type: NotificationType) -> some View {
        Toggle(title, isOn: Binding(
            get: { viewModel.isOn(type) },
            set: { isOn in Task { await viewModel.set(type, isOn) } }
        ))
    }
}
