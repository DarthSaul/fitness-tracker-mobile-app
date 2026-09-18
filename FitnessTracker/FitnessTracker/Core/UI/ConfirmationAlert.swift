import SwiftUI

/// The app's standard call-to-action confirmation: a centered system alert
/// with a title, a message, and Cancel + confirm side by side. Use this
/// instead of `.confirmationDialog`, which anchors itself to the trigger (or
/// the top of the page) rather than centering.
struct ConfirmationAlertModifier: ViewModifier {
    let title: String
    @Binding var isPresented: Bool
    let message: String
    let confirmLabel: String
    let confirmRole: ButtonRole?
    let onConfirm: () -> Void

    func body(content: Content) -> some View {
        content.alert(title, isPresented: $isPresented) {
            Button(confirmLabel, role: confirmRole, action: onConfirm)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(message)
        }
    }
}

extension View {
    func confirmationAlert(
        _ title: String,
        isPresented: Binding<Bool>,
        message: String,
        confirmLabel: String,
        confirmRole: ButtonRole? = nil,
        onConfirm: @escaping () -> Void
    ) -> some View {
        modifier(ConfirmationAlertModifier(
            title: title,
            isPresented: isPresented,
            message: message,
            confirmLabel: confirmLabel,
            confirmRole: confirmRole,
            onConfirm: onConfirm
        ))
    }
}
