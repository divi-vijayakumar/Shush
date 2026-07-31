import AppKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            switch model.phase {
            case .checking:
                LoadingView(message: model.activity)
            case .serverOffline(let existingData):
                SetupView(mode: existingData ? .unlock : .create)
            case .needsFirstSetup:
                SetupView(mode: .create)
            case .needsLogin:
                SetupView(mode: .login)
            case .ready:
                ContentView()
            case .failed(let message):
                ErrorStateView(message: message)
            }
        }
        .background {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color.indigo.opacity(0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .alert(
            "Shush couldn’t complete that",
            isPresented: Binding(
                get: { model.presentedError != nil },
                set: { if !$0 { model.presentedError = nil } }
            )
        ) {
            Button("OK") { model.presentedError = nil }
        } message: {
            Text(model.presentedError ?? "")
        }
    }
}

private struct LoadingView: View {
    let message: String

    var body: some View {
        VStack(spacing: 18) {
            ShushMark(size: 72)
            ProgressView()
                .controlSize(.small)
            Text(message)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ErrorStateView: View {
    @EnvironmentObject private var model: AppModel
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text("Something needs attention")
                .font(.title2.bold())
            Text(message)
                .foregroundStyle(.secondary)
            Button("Try Again") { model.start() }
                .buttonStyle(.borderedProminent)
        }
        .padding(40)
    }
}

struct ShushMark: View {
    var size: CGFloat = 42

    var body: some View {
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.23, style: .continuous))
        .frame(width: size, height: size)
        .shadow(color: .indigo.opacity(0.22), radius: size * 0.18, y: size * 0.08)
    }
}
