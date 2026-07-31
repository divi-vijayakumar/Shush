import Foundation

actor BackendManager {
    static let shared = BackendManager()

    var databaseExists: Bool {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".agent-vault/agent-vault.db")
        return FileManager.default.fileExists(atPath: path.path)
    }

    func start(masterPassword: String) async throws {
        guard let binary = bundledBinaryURL() else {
            throw ShushError.backendUnavailable("The bundled Agent Vault binary is missing.")
        }

        let process = Process()
        process.executableURL = binary
        process.arguments = [
            "server",
            "--host", "127.0.0.1",
            "--port", "14321",
            "--mitm-port", "14322",
            "--detach",
            "--password-stdin"
        ]

        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = output

        do {
            try process.run()
        } catch {
            throw ShushError.backendUnavailable("Could not start the bundled backend: \(error.localizedDescription)")
        }

        input.fileHandleForWriting.write(Data((masterPassword + "\n").utf8))
        try? input.fileHandleForWriting.close()
        process.waitUntilExit()

        let message = String(
            data: output.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        guard process.terminationStatus == 0 else {
            throw ShushError.backendUnavailable(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        for _ in 0..<30 {
            if (try? await AgentVaultClient.shared.status()) != nil { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw ShushError.backendUnavailable("The backend did not become ready.")
    }

    private func bundledBinaryURL() -> URL? {
        if let url = Bundle.main.url(forResource: "agent-vault", withExtension: nil) {
            return url
        }
        let developmentPaths = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Vendor/agent-vault"),
            URL(fileURLWithPath: "/usr/local/bin/agent-vault"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/bin/agent-vault")
        ]
        return developmentPaths.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
