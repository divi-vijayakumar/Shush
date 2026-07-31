import SwiftUI

struct AddSecretView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var value = ""
    @State private var kind: SecretKind = .secret

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Add a secret")
                        .font(.title2.bold())
                    Text("Encrypted locally as soon as you save.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                ShushMark(size: 42)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("e.g. Stripe production key", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Format")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("Format", selection: $kind) {
                    ForEach([
                        SecretKind.secret,
                        .json,
                        .tfvars,
                        .environment,
                        .yaml,
                        .certificate,
                        .text
                    ]) { format in
                        Label(format.label, systemImage: format.symbol)
                            .tag(format)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Value")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(value.utf8.count) bytes")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                TextEditor(text: $value)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(Color.secondary.opacity(0.18))
                    }
                    .frame(minHeight: 190)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    Task {
                        await model.saveQuickSecret(name: name, value: value, kind: kind)
                        if model.presentedError == nil { dismiss() }
                    }
                } label: {
                    if model.isWorking {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Encrypt & Save")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(
                    name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    value.isEmpty ||
                    model.isWorking
                )
            }
        }
        .padding(28)
        .frame(width: 560, height: 590)
    }
}
