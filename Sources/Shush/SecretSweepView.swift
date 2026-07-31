import AppKit
import SwiftUI

struct SecretSweepView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var findingToTrash: SecretFinding?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if model.isScanning {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Scanning Desktop and Downloads locally…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.scanFindings.isEmpty {
                emptyState
            } else {
                findingsList
            }

            Divider()
            HStack {
                Label("File contents never leave this Mac", systemImage: "lock.shield.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 760, height: 570)
        .task {
            if model.scanFindings.isEmpty {
                await model.scanDesktopAndDownloads()
            }
        }
        .alert(
            "Move source file to Trash?",
            isPresented: Binding(
                get: { findingToTrash != nil },
                set: { if !$0 { findingToTrash = nil } }
            ),
            presenting: findingToTrash
        ) { finding in
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash", role: .destructive) {
                model.moveFindingSourceToTrash(finding)
                findingToTrash = nil
            }
        } message: { finding in
            Text("\(finding.fileURL.lastPathComponent) will be moved to the Mac Trash, where it can still be recovered.")
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.indigo.opacity(0.11))
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.title2)
                    .foregroundStyle(.indigo)
            }
            .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 3) {
                Text("Secret Sweep")
                    .font(.title2.bold())
                Text("Find likely credentials left in Desktop and Downloads.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await model.scanDesktopAndDownloads() }
            } label: {
                Label("Scan Again", systemImage: "arrow.clockwise")
            }
            .disabled(model.isScanning)
        }
        .padding(20)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 44))
                .foregroundStyle(.mint)
            Text("No new secrets found")
                .font(.title3.bold())
            Text(emptyMessage)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Scan Again") {
                Task { await model.scanDesktopAndDownloads() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyMessage: String {
        if model.scanSuppressedCount > 0 {
            return "Shush hid \(model.scanSuppressedCount) match\(model.scanSuppressedCount == 1 ? "" : "es") already imported or ignored.\nYou can scan again whenever you download new credentials."
        }
        return "Shush checked readable text files up to 2 MB.\nYou can scan again whenever you download new credentials."
    }

    private var findingsList: some View {
        List {
            Section {
                ForEach(model.scanFindings) { finding in
                    let imported = model.isFindingAlreadyImported(finding)
                    HStack(spacing: 12) {
                        Image(systemName: "key.fill")
                            .foregroundStyle(.orange)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(finding.kind)
                                .font(.body.weight(.semibold))
                            Text(finding.maskedValue)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text("\(finding.fileURL.lastPathComponent) · line \(finding.line)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([finding.fileURL])
                        } label: {
                            Image(systemName: "folder")
                        }
                        .help("Show in Finder")
                        if imported {
                            Label("Imported", systemImage: "checkmark.circle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.green)
                            Button("Keep File") {
                                model.dismissFinding(finding)
                            }
                            .buttonStyle(.bordered)
                            Button(role: .destructive) {
                                findingToTrash = finding
                            } label: {
                                Image(systemName: "trash")
                            }
                            .help("Move source file to Trash")
                        } else {
                            Button("Ignore") {
                                model.ignoreFinding(finding)
                            }
                            .buttonStyle(.borderless)
                            Button("Import") {
                                Task { await model.importFinding(finding) }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.isWorking)
                        }
                    }
                    .padding(.vertical, 5)
                }
            } header: {
                Text("\(model.scanFindings.count) possible secret\(model.scanFindings.count == 1 ? "" : "s")")
            } footer: {
                Text("Imported and ignored matches stay hidden on future scans. Source files move to Trash only after confirmation.")
            }
        }
        .listStyle(.inset)
    }
}
