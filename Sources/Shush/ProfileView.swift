import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmation = ""
    @State private var changed = false

    private var canSubmit: Bool {
        !currentPassword.isEmpty &&
        newPassword.count >= 8 &&
        newPassword == confirmation &&
        !model.isWorking
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.indigo.opacity(0.11))
                    Image(systemName: "person.crop.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.indigo)
                }
                .frame(width: 50, height: 50)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Shush profile")
                        .font(.title2.bold())
                    Text("Your local Agent Vault account")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("EMAIL")
                    .font(.caption2.bold())
                    .foregroundStyle(.tertiary)
                Text(model.accountProfile?.email ?? "Unavailable")
                    .font(.body.weight(.medium))
                    .textSelection(.enabled)
                if model.accountProfile?.isOwner == true {
                    Text("OWNER")
                        .font(.caption2.bold())
                        .foregroundStyle(.indigo)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.indigo.opacity(0.1), in: Capsule())
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                Text("Change account password")
                    .font(.headline)
                Text("Your existing password cannot be viewed or recovered. Enter it to authorize a change. This does not change the separate vault-unlock passphrase used when the backend starts.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                SecureField("Current password", text: $currentPassword)
                    .textFieldStyle(.roundedBorder)
                SecureField("New password — at least 8 characters", text: $newPassword)
                    .textFieldStyle(.roundedBorder)
                SecureField("Confirm new password", text: $confirmation)
                    .textFieldStyle(.roundedBorder)

                if !confirmation.isEmpty && newPassword != confirmation {
                    Text("The new passwords do not match.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if changed {
                    Label("Account password updated", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            Spacer()

            HStack {
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    Task {
                        if await model.updatePassword(current: currentPassword, new: newPassword) {
                            currentPassword = ""
                            newPassword = ""
                            confirmation = ""
                            changed = true
                        }
                    }
                } label: {
                    if model.isWorking {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Update Account Password")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit)
            }
        }
        .padding(28)
        .frame(width: 560, height: 590)
    }
}
