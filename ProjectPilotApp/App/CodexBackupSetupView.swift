import SwiftUI

struct CodexBackupSetupView: View {
    @ObservedObject var vm: ProjectPilotViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirmation = ""
    @State private var recoverySaved = false
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Protect your Codex setup").font(.title2.bold())
            Text("This backs up instructions, skills, memories and unpublished worktree source, not full chat history. Choose a recovery password of at least 16 characters. Save it in a password manager you can access on a replacement Mac.")
                .fixedSize(horizontal: false, vertical: true)
            SecureField("Backup password", text: $password)
                .textContentType(.newPassword)
                .accessibilityIdentifier("codexBackupPassword")
            SecureField("Confirm backup password", text: $confirmation)
                .textContentType(.newPassword)
                .accessibilityIdentifier("codexBackupPasswordConfirmation")
            Toggle("I saved this password somewhere I can access after losing this Mac.", isOn: $recoverySaved)
                .fixedSize(horizontal: false, vertical: true)
            Text("ProjectPilot stores a local Keychain copy for automatic backups. It cannot recover a forgotten password. The password is never included in the archives.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let error { Text(error).foregroundStyle(.red).accessibilityLabel("Setup error: \(error)") }
            HStack {
                Button("Cancel") { clearAndDismiss() }.disabled(saving)
                Spacer()
                if saving { ProgressView().controlSize(.small) }
                Button("Enable encrypted backup") {
                    saving = true
                    Task {
                        do {
                            try await vm.configureCodexBackup(password: password, confirmation: confirmation, recoverySaved: recoverySaved)
                            clearAndDismiss()
                        } catch {
                            self.error = error.localizedDescription
                            saving = false
                        }
                    }
                }
                .disabled(saving || !recoverySaved || password.count < 16 || password != confirmation)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 470)
        .interactiveDismissDisabled(saving)
        .onDisappear { password = ""; confirmation = "" }
    }

    private func clearAndDismiss() {
        password = ""
        confirmation = ""
        dismiss()
    }
}
