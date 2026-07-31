import SwiftUI

struct ReplaceSecretView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let item: ShushItem

    @State private var newValue = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Replace & retire")
                    .font(.title2.bold())
                Text(item.name)
                    .foregroundStyle(.secondary)
            }

            Label(
                "The current value stays encrypted in Retired. Shush cannot generically revoke it at the provider.",
                systemImage: "info.circle.fill"
            )
            .font(.callout)
            .foregroundStyle(.orange)
            .padding(12)
            .background(.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))

            TextEditor(text: $newValue)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(Color.secondary.opacity(0.18))
                }
                .frame(minHeight: 210)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    Task {
                        await model.replace(item, with: newValue)
                        if model.presentedError == nil { dismiss() }
                    }
                } label: {
                    if model.isWorking {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Save New & Retire Old")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(newValue.isEmpty || model.isWorking)
            }
        }
        .padding(26)
        .frame(width: 560, height: 470)
    }
}
