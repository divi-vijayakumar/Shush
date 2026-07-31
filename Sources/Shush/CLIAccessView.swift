import AppKit
import SwiftUI

struct CLIAccessView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var installed = false
    @State private var message: String?

    private let command = """
    shush profile list
    shush profile use personal
    shush profile bind work
    shush profile request work --email you@company.com
    shush auth login
    shush list --json
    shush get "Secret name"
    printf '%s' "$VALUE" | shush put "Secret name" --replace
    """

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.indigo.opacity(0.11))
                    Image(systemName: "terminal.fill")
                        .font(.title2)
                        .foregroundStyle(.indigo)
                }
                .frame(width: 50, height: 50)
                VStack(alignment: .leading, spacing: 3) {
                    Text("CLI access")
                        .font(.title2.bold())
                    Text("Let Claude, Codex, and your terminal use this local vault.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                Label(
                    installed ? "Installed at ~/.local/bin/shush" : "Install for this Mac user",
                    systemImage: installed ? "checkmark.circle.fill" : "arrow.down.circle"
                )
                .font(.headline)
                .foregroundStyle(installed ? .green : .primary)

                Text("No administrator access is required. Make sure ~/.local/bin is included in your PATH.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Button(installed ? "CLI Installed" : "Install CLI") {
                    install()
                }
                .buttonStyle(.borderedProminent)
                .disabled(installed)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.indigo.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("Authenticate and use")
                        .font(.headline)
                    Spacer()
                    Button("Copy Commands") {
                        model.copyToClipboard(command, label: "CLI commands copied")
                    }
                }
                Text(command)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            }

            Text("The CLI authenticates each profile separately and saves its session in macOS Keychain. A .shush-profile binding makes Codex and Claude select the correct vault for that project.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let message {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 620, height: 560)
        .onAppear { installed = isInstalled() }
    }

    private func install() {
        guard let bundled = Bundle.main.url(forResource: "shush", withExtension: nil) else {
            message = "The CLI is included in packaged builds. It is unavailable in this development build."
            return
        }
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin", isDirectory: true)
        let destination = directory.appendingPathComponent("shush")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                guard isInstalled() else {
                    throw CocoaError(
                        .fileWriteFileExists,
                        userInfo: [NSLocalizedDescriptionKey: "\(destination.path) already exists. Shush left it unchanged."]
                    )
                }
            } else {
                try FileManager.default.createSymbolicLink(
                    at: destination,
                    withDestinationURL: bundled
                )
            }
            installed = true
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    private func isInstalled() -> Bool {
        guard let bundled = Bundle.main.url(forResource: "shush", withExtension: nil) else {
            return false
        }
        let destination = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin/shush")
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: destination.path) else {
            return false
        }
        return URL(fileURLWithPath: target).standardizedFileURL == bundled.standardizedFileURL
    }
}
