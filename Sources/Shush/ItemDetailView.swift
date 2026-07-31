import AppKit
import SwiftUI

struct ItemDetailView: View {
    @EnvironmentObject private var model: AppModel
    let item: ShushItem

    @State private var revealedData: Data?
    @State private var isRevealing = false
    @State private var confirmingChatCopy = false
    @State private var showingReplacement = false

    private var textValue: String? {
        guard let revealedData else { return nil }
        return String(data: revealedData, encoding: .utf8)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                if item.isRetired {
                    Label(
                        "Retired locally. Confirm revocation with the credential provider.",
                        systemImage: "exclamationmark.arrow.triangle.2.circlepath"
                    )
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.orange)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                }
                metadata
                credentialStatus
                Divider()
                secretPanel
            }
            .padding(30)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.24))
        .sheet(isPresented: $showingReplacement) {
            ReplaceSecretView(item: item)
                .environmentObject(model)
        }
        .alert("Copy plaintext for chat?", isPresented: $confirmingChatCopy) {
            Button("Cancel", role: .cancel) {}
            Button("Copy Plaintext") {
                if let textValue { model.copyForChat(textValue, item: item) }
            }
        } message: {
            Text("Pasting this into an online chat sends the secret to that chat provider. Only continue if that is intentional.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(Color.indigo.opacity(0.11))
                Image(systemName: item.kind.symbol)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.indigo)
            }
            .frame(width: 62, height: 62)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(item.name)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    if item.isRetired {
                        Text("RETIRED")
                            .font(.caption2.bold())
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.orange.opacity(0.12), in: Capsule())
                    }
                }
                Text(item.originalFilename ?? item.kind.label)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var metadata: some View {
        HStack(spacing: 28) {
            metadataCell("SAVED", value: item.savedAt.formatted(date: .abbreviated, time: .shortened))
            metadataCell("SIZE", value: ByteCountFormatter.string(fromByteCount: Int64(item.byteCount), countStyle: .file))
            metadataCell("PARTS", value: "\(item.partKeys.count)")
            metadataCell("BACKEND", value: "Agent Vault")
        }
    }

    private func metadataCell(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption.weight(.medium))
        }
    }

    private var credentialStatus: some View {
        let duplicates = model.duplicateCount(for: item)
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Image(systemName: duplicates > 0 ? "square.on.square.badge.person.crop" : "checkmark.circle")
                    .foregroundStyle(duplicates > 0 ? .orange : .secondary)
                Text(
                    duplicates > 0
                        ? "\(duplicates) possible local duplicate\(duplicates == 1 ? "" : "s")"
                        : (item.valueFingerprint == nil ? "No duplicate name detected" : "No local duplicate detected")
                )
                .font(.callout.weight(.medium))
            }
            HStack(spacing: 10) {
                Image(systemName: "questionmark.shield")
                    .foregroundStyle(.secondary)
                Text("Provider validity not checked")
                    .font(.callout.weight(.medium))
                Text("Shush cannot infer revocation or expiration from the saved value.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    private var secretPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Secret value")
                        .font(.headline)
                    Text(revealedData == nil ? "Hidden until you ask" : "Visible in memory only")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                if revealedData == nil {
                    Button {
                        reveal()
                    } label: {
                        if isRevealing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Reveal", systemImage: "eye")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRevealing)
                } else {
                    Button {
                        withAnimation { revealedData = nil }
                    } label: {
                        Label("Hide", systemImage: "eye.slash")
                    }
                }
            }

            Group {
                if let textValue {
                    ScrollView([.horizontal, .vertical]) {
                        Text(textValue)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(14)
                    }
                } else if revealedData != nil {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.zipper")
                            .font(.title)
                        Text("Binary file")
                            .font(.headline)
                        Text("Export it to restore the original bytes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.indigo.opacity(0.72))
                        Text("••••••••••••••••••••••••")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 180)
                }
            }
            .frame(minHeight: 180, maxHeight: 360)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.14))
            }

            if let textValue {
                HStack {
                    Button {
                        model.copyToClipboard(textValue)
                    } label: {
                        Label("Copy Value", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        confirmingChatCopy = true
                    } label: {
                        Label("Copy for Chat", systemImage: "text.bubble")
                    }
                    .buttonStyle(.bordered)

                    if !item.isRetired {
                        Button {
                            showingReplacement = true
                        } label: {
                            Label("Replace & Retire", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.bordered)
                    }

                    Spacer()
                    Label("Clipboard clears after 60 seconds", systemImage: "timer")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } else if revealedData != nil {
                Button("Export Original…", action: exportOriginal)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func reveal() {
        isRevealing = true
        Task {
            defer { isRevealing = false }
            do {
                revealedData = try await model.reveal(item)
            } catch {
                model.presentedError = error.localizedDescription
            }
        }
    }

    private func exportOriginal() {
        guard let revealedData else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = item.originalFilename ?? item.name
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try revealedData.write(to: url, options: .atomic)
            } catch {
                model.presentedError = error.localizedDescription
            }
        }
    }
}
