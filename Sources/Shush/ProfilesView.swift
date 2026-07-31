import SwiftUI

struct ProfilesView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingAdd = false
    @State private var profileToRemove: ShushProfile?
    @State private var requestToReview: ProfileRequest?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Profiles")
                        .font(.title2.bold())
                    Text("Keep personal and work secrets in separate local vaults.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(model.profiles.count)/\(ProfileStore.maximumProfiles)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            List {
                if !model.pendingProfileRequests.isEmpty {
                    Section("Requested by agents") {
                        ForEach(model.pendingProfileRequests) { request in
                            HStack {
                                Image(systemName: "terminal.fill")
                                    .foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(request.label)
                                        .font(.body.weight(.semibold))
                                    Text(request.email)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Review") {
                                    requestToReview = request
                                }
                                .buttonStyle(.borderedProminent)
                                Button("Dismiss") {
                                    model.dismissProfileRequest(request.id)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                ForEach(model.profiles) { profile in
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 9)
                                .fill(Color.indigo.opacity(0.1))
                            Image(
                                systemName: profile.id == model.activeProfileID
                                    ? "person.crop.circle.fill.badge.checkmark"
                                    : "person.crop.circle"
                            )
                            .foregroundStyle(.indigo)
                        }
                        .frame(width: 40, height: 40)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(profile.label)
                                    .font(.body.weight(.semibold))
                                if profile.id == model.activeProfileID {
                                    Text("ACTIVE")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.green)
                                }
                            }
                            Text(profile.email)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(profile.vaultName)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        if profile.id != model.activeProfileID {
                            Button("Switch") {
                                Task { await model.switchProfile(to: profile.id) }
                            }
                            .buttonStyle(.bordered)
                        }
                        Button(role: .destructive) {
                            profileToRemove = profile
                        } label: {
                            Image(systemName: "trash")
                        }
                        .disabled(model.profiles.count == 1)
                        .help("Remove this profile from Shush")
                    }
                    .padding(.vertical, 5)
                }
            }
            .listStyle(.inset)

            Text("Removing a profile deletes its saved session from this Mac. It does not delete the encrypted vault or provider credentials.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Close") { dismiss() }
                Spacer()
                Button {
                    showingAdd = true
                } label: {
                    Label("Add Profile", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.profiles.count >= ProfileStore.maximumProfiles)
            }
        }
        .padding(26)
        .frame(width: 680, height: 590)
        .sheet(isPresented: $showingAdd) {
            AddProfileView()
                .environmentObject(model)
        }
        .sheet(item: $requestToReview) { request in
            AddProfileView(request: request)
                .environmentObject(model)
        }
        .onAppear { model.refreshProfileRequests() }
        .alert(
            "Remove \(profileToRemove?.label ?? "profile")?",
            isPresented: Binding(
                get: { profileToRemove != nil },
                set: { if !$0 { profileToRemove = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { profileToRemove = nil }
            Button("Remove Profile", role: .destructive) {
                if let profile = profileToRemove {
                    Task { await model.removeProfile(profile.id) }
                }
                profileToRemove = nil
            }
        } message: {
            Text("The local session will be removed. The encrypted vault itself will not be deleted.")
        }
    }
}

private struct AddProfileView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var email = ""
    @State private var password = ""
    let request: ProfileRequest?

    init(request: ProfileRequest? = nil) {
        self.request = request
        _label = State(initialValue: request?.label ?? "")
        _email = State(initialValue: request?.email ?? "")
    }

    private var canSubmit: Bool {
        !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        email.contains("@") &&
        password.count >= 8 &&
        !model.isWorking
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add a profile")
                    .font(.title2.bold())
                Text(
                    request == nil
                        ? "Sign in with another user of this local Agent Vault."
                        : "An agent requested this profile. Verify it, then authenticate yourself."
                )
                    .foregroundStyle(.secondary)
            }

            TextField("Profile name, e.g. Work", text: $label)
                .textFieldStyle(.roundedBorder)
            TextField("Account email", text: $email)
                .textFieldStyle(.roundedBorder)
            SecureField("Account password", text: $password)
                .textFieldStyle(.roundedBorder)

            Label(
                "A new encrypted vault will be created for this profile. Secrets are never copied between profiles.",
                systemImage: "lock.shield"
            )
            .font(.callout)
            .foregroundStyle(.secondary)

            Spacer()
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    Task {
                        if await model.addProfile(
                            label: label,
                            email: email,
                            password: password,
                            requestID: request?.id
                        ) {
                            dismiss()
                        }
                    }
                } label: {
                    if model.isWorking {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Authenticate & Add")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit)
            }
        }
        .padding(26)
        .frame(width: 520, height: 420)
    }
}
