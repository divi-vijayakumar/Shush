import SwiftUI

enum SetupMode {
    case create
    case unlock
    case login
}

struct SetupView: View {
    @EnvironmentObject private var model: AppModel
    let mode: SetupMode

    @State private var email = ""
    @State private var password = ""
    @State private var confirmation = ""

    private var title: String {
        switch mode {
        case .create: "Create your private vault"
        case .unlock: "Welcome back"
        case .login: "Sign in to Shush"
        }
    }

    private var subtitle: String {
        switch mode {
        case .create:
            "Shush will start Agent Vault on this Mac and encrypt everything locally."
        case .unlock:
            "Unlock the Agent Vault backend after a restart."
        case .login:
            "The backend is unlocked. Sign in to the selected local profile."
        }
    }

    private var canSubmit: Bool {
        switch mode {
        case .create:
            email.contains("@") && password.count >= 8 && password == confirmation
        case .unlock:
            password.count >= 8
        case .login:
            email.contains("@") && password.count >= 8
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            brandPanel
                .frame(width: 390)

            VStack(alignment: .leading, spacing: 24) {
                Spacer()

                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 14) {
                    if mode != .unlock {
                        LabeledContent("Local account") {
                            TextField("you@local", text: $email)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 280)
                        }
                    }

                    LabeledContent(
                        mode == .unlock
                            ? "Vault passphrase"
                            : (mode == .login ? "Account password" : "Passphrase")
                    ) {
                        SecureField("At least 8 characters", text: $password)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 280)
                    }

                    if mode == .create {
                        LabeledContent("Confirm") {
                            SecureField("Repeat passphrase", text: $confirmation)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 280)
                        }
                    }
                }

                if mode == .create {
                    Label(
                        "Your passphrase is never saved by Shush. You’ll need it after restarting your Mac.",
                        systemImage: "lock.shield"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Button {
                    Task {
                        switch mode {
                        case .create:
                            await model.createLocalVault(email: email, password: password)
                        case .unlock:
                            await model.unlockBackend(passphrase: password)
                        case .login:
                            await model.login(email: email, password: password)
                        }
                    }
                } label: {
                    HStack {
                        if model.isWorking {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(buttonTitle)
                            .frame(maxWidth: .infinity)
                    }
                    .frame(height: 28)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canSubmit || model.isWorking)

                if model.isWorking {
                    Text(model.activity)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .frame(maxWidth: 470)
            .padding(54)
        }
        .onAppear {
            if mode == .login, let profile = model.activeProfile {
                email = profile.email
            }
        }
    }

    private var buttonTitle: String {
        switch mode {
        case .create: "Create Shush Vault"
        case .unlock: "Unlock on This Mac"
        case .login: "Sign In Locally"
        }
    }

    private var brandPanel: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.07, blue: 0.14),
                    Color(red: 0.12, green: 0.09, blue: 0.22)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 22) {
                ShushMark(size: 82)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Shush")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Secrets live here.\nNot in your notes.")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.68))
                }

                Spacer()

                VStack(alignment: .leading, spacing: 12) {
                    privacyLine("Local Agent Vault backend", icon: "internaldrive.fill")
                    privacyLine("AES-256-GCM at rest", icon: "lock.fill")
                    privacyLine("No Shush cloud account", icon: "icloud.slash.fill")
                }
            }
            .padding(48)
        }
        .ignoresSafeArea()
    }

    private func privacyLine(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white.opacity(0.76))
    }
}
