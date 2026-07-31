import Darwin
import CryptoKit
import Foundation
import Security

private let indexKey = "SHUSH_INDEX_V1"
private let baseURL = URL(
    string: ProcessInfo.processInfo.environment["SHUSH_ADDR"] ?? "http://127.0.0.1:14321"
)!

@main
struct ShushCLI {
    static func main() async {
        do {
            try await run(Array(CommandLine.arguments.dropFirst()))
        } catch {
            FileHandle.standardError.write(Data("shush: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private static func run(_ arguments: [String]) async throws {
        guard let command = arguments.first else {
            printHelp()
            return
        }

        if command == "profile" {
            try runProfile(Array(arguments.dropFirst()))
            return
        }
        let profile = try CLIProfileStore.resolve(arguments: arguments)
        let selectedVault = ProcessInfo.processInfo.environment["SHUSH_VAULT"]
            ?? profile?.vaultName
            ?? "shush"
        let client = Client(vaultName: selectedVault)
        switch command {
        case "auth":
            try await runAuth(
                Array(arguments.dropFirst()),
                client: client,
                profile: profile
            )
        case "list", "ls":
            let token = try SessionStore.requireToken(profileID: profile?.id)
            let index = try await client.loadIndex(token: token)
            if arguments.contains("--json") {
                try printJSON(index.items.sorted { $0.updatedAt > $1.updatedAt }.map(ListItem.init))
            } else if index.items.isEmpty {
                print("No secrets.")
            } else {
                for item in index.items.sorted(by: { $0.updatedAt > $1.updatedAt }) {
                    let state = item.retiredAt == nil ? "" : "\tretired"
                    print("\(item.id.uuidString.lowercased())\t\(item.name)\t\(item.kind.rawValue)\(state)")
                }
            }
        case "get":
            guard arguments.count >= 2 else {
                throw CLIError.usage("Usage: shush get <name-or-id>")
            }
            let token = try SessionStore.requireToken(profileID: profile?.id)
            let index = try await client.loadIndex(token: token)
            let item = try resolve(arguments[1], in: index.items)
            let data = try await client.reveal(item: item, token: token)
            FileHandle.standardOutput.write(data)
        case "put":
            guard arguments.count >= 2 else {
                throw CLIError.usage("Usage: <value> | shush put <name> [--kind secret|json|environment|yaml|text]")
            }
            guard isatty(STDIN_FILENO) == 0 else {
                throw CLIError.usage("Refusing to read a secret from an interactive terminal. Pipe it through stdin.")
            }
            let name = arguments[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { throw CLIError.usage("Secret name cannot be empty.") }
            let kind = try parseKind(arguments)
            let data = FileHandle.standardInput.readDataToEndOfFile()
            guard !data.isEmpty else { throw CLIError.usage("No secret value was received on stdin.") }
            guard data.count <= SecretCodec.maximumFileBytes else { throw CLIError.fileTooLarge }

            let token = try SessionStore.requireToken(profileID: profile?.id)
            var index = try await client.loadIndex(token: token)
            let activeMatches = index.items.indices.filter {
                index.items[$0].retiredAt == nil &&
                index.items[$0].name.compare(name, options: .caseInsensitive) == .orderedSame
            }
            if activeMatches.count > 1 {
                throw CLIError.conflict("More than one active item is named \(name). Use a distinct name.")
            }
            if !activeMatches.isEmpty && !arguments.contains("--replace") {
                throw CLIError.conflict("An active item named \(name) already exists. Pass --replace to retire it.")
            }

            let item = try await client.store(data: data, name: name, kind: kind, token: token)
            if let oldIndex = activeMatches.first {
                index.items[oldIndex].retiredAt = Date()
                index.items[oldIndex].replacementID = item.id
            }
            index.items.append(item)
            do {
                try await client.saveIndex(index, token: token)
            } catch {
                try? await client.delete(keys: item.partKeys, token: token)
                throw error
            }
            print(item.id.uuidString.lowercased())
        case "help", "--help", "-h":
            printHelp()
        case "version", "--version":
            print("shush 0.2.0")
        default:
            throw CLIError.usage("Unknown command \(command). Run `shush help`.")
        }
    }

    private static func runAuth(
        _ arguments: [String],
        client: Client,
        profile: CLIProfile?
    ) async throws {
        guard let command = arguments.first else {
            throw CLIError.usage("Usage: shush auth <login|status|logout>")
        }
        switch command {
        case "login":
            let email: String
            if let index = arguments.firstIndex(of: "--email"), arguments.indices.contains(index + 1) {
                email = arguments[index + 1]
            } else {
                FileHandle.standardError.write(Data("Email: ".utf8))
                email = readLine() ?? ""
            }
            guard !email.isEmpty else { throw CLIError.usage("Email cannot be empty.") }
            guard let pointer = getpass("Password: ") else {
                throw CLIError.usage("Could not read the password.")
            }
            let password = String(cString: pointer)
            let result = try await client.login(email: email, password: password)
            let account = try await client.account(token: result.token)
            if let profile,
               account.email.compare(profile.email, options: .caseInsensitive) != .orderedSame {
                throw CLIError.authentication("Profile \(profile.label) belongs to \(profile.email).")
            }
            try SessionStore.save(result.token, profileID: profile?.id)
            print("Authenticated to \(profile?.label ?? "the local Shush vault").")
        case "status":
            guard let token = SessionStore.read(profileID: profile?.id) else {
                print("Not authenticated. Run `shush auth login`.")
                return
            }
            do {
                try await client.authenticate(token: token)
                print("Authenticated. Local backend: \(baseURL.absoluteString)")
            } catch {
                SessionStore.delete(profileID: profile?.id)
                throw CLIError.authentication("The saved session expired. Run `shush auth login`.")
            }
        case "logout":
            SessionStore.delete(profileID: profile?.id)
            print("Local CLI session removed.")
        default:
            throw CLIError.usage("Usage: shush auth <login|status|logout>")
        }
    }

    private static func runProfile(_ arguments: [String]) throws {
        guard let command = arguments.first else {
            throw CLIError.usage("Usage: shush profile <list|current|use|bind|request>")
        }
        switch command {
        case "list":
            let configuration = CLIProfileStore.load()
            if arguments.contains("--json") {
                try printJSON(configuration.profiles)
            } else {
                for profile in configuration.profiles {
                    let marker = profile.id == configuration.activeProfileID ? "*" : " "
                    print("\(marker) \(profile.label)\t\(profile.email)\t\(profile.vaultName)")
                }
            }
        case "current":
            guard let profile = try CLIProfileStore.resolve(arguments: arguments) else {
                throw CLIError.notFound("No Shush profile is configured.")
            }
            print("\(profile.label)\t\(profile.email)\t\(profile.vaultName)")
        case "use":
            guard arguments.count >= 2 else {
                throw CLIError.usage("Usage: shush profile use <name-or-id>")
            }
            let profile = try CLIProfileStore.find(arguments[1])
            var configuration = CLIProfileStore.load()
            configuration.activeProfileID = profile.id
            try CLIProfileStore.save(configuration)
            print("Active profile: \(profile.label)")
        case "bind":
            guard arguments.count >= 2 else {
                throw CLIError.usage("Usage: shush profile bind <name-or-id>")
            }
            let profile = try CLIProfileStore.find(arguments[1])
            let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".shush-profile")
            try Data((profile.id.uuidString.lowercased() + "\n").utf8)
                .write(to: url, options: [.atomic])
            print("Bound \(url.path) to \(profile.label).")
        case "request":
            guard arguments.count >= 2,
                  let emailIndex = arguments.firstIndex(of: "--email"),
                  arguments.indices.contains(emailIndex + 1) else {
                throw CLIError.usage("Usage: shush profile request <name> --email <email>")
            }
            let request = CLIProfileRequest(
                id: UUID(),
                label: arguments[1].trimmingCharacters(in: .whitespacesAndNewlines),
                email: arguments[emailIndex + 1].trimmingCharacters(in: .whitespacesAndNewlines),
                createdAt: Date()
            )
            guard !request.label.isEmpty, request.email.contains("@") else {
                throw CLIError.usage("A profile name and valid email are required.")
            }
            try CLIProfileStore.saveRequest(request)
            if ProcessInfo.processInfo.environment["SHUSH_CONFIG"] == nil {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                process.arguments = ["-a", "Shush"]
                try? process.run()
            }
            print("Profile request \(request.id.uuidString.lowercased()) created.")
            print("Approve it in Shush → Manage Profiles. The agent never receives the password.")
        default:
            throw CLIError.usage("Usage: shush profile <list|current|use|bind|request>")
        }
    }

    private static func resolve(_ selector: String, in items: [Item]) throws -> Item {
        if let id = UUID(uuidString: selector),
           let item = items.first(where: { $0.id == id }) {
            return item
        }
        let matches = items.filter {
            $0.retiredAt == nil && $0.name.compare(selector, options: .caseInsensitive) == .orderedSame
        }
        if matches.count == 1 { return matches[0] }
        if matches.isEmpty { throw CLIError.notFound("No active item named \(selector).") }
        throw CLIError.conflict("More than one item is named \(selector). Use its UUID from `shush list`.")
    }

    private static func parseKind(_ arguments: [String]) throws -> SecretKind {
        guard let index = arguments.firstIndex(of: "--kind") else { return .secret }
        guard arguments.indices.contains(index + 1),
              let kind = SecretKind(rawValue: arguments[index + 1]) else {
            throw CLIError.usage("Invalid --kind. Use secret, json, environment, yaml, certificate, text, or other.")
        }
        return kind
    }

    private static func printJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(value))
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func printHelp() {
        print("""
        Shush — local secrets for humans and coding agents

        Usage:
          shush auth login [--email <email>]
          shush auth status
          shush auth logout
          shush profile list
          shush profile use <name>
          shush profile bind <name>
          shush profile request <name> --email <email>
          shush list [--json]
          shush get <name-or-id>
          <value> | shush put <name> [--kind <kind>] [--replace]

        The Shush app (or Agent Vault backend) must be unlocked first.
        Secret values for `put` are accepted only through stdin so they do not
        appear in shell history or process arguments.
        """)
    }
}

private actor Client {
    private let vaultName: String
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    init(vaultName: String) {
        self.vaultName = vaultName
    }

    func login(email: String, password: String) async throws -> AuthResult {
        try await request(
            path: "/v1/auth/login",
            method: "POST",
            body: ["email": email, "password": password, "device_label": "Shush CLI"],
            as: AuthResult.self
        )
    }

    func authenticate(token: String) async throws {
        let _: AccountIdentity = try await request(
            path: "/v1/auth/me",
            token: token,
            as: AccountIdentity.self
        )
    }

    func account(token: String) async throws -> AccountIdentity {
        try await request(path: "/v1/auth/me", token: token, as: AccountIdentity.self)
    }

    func loadIndex(token: String) async throws -> Index {
        let response: CredentialResponse = try await request(
            path: "/v1/credentials?vault=\(vaultName)",
            token: token,
            as: CredentialResponse.self
        )
        guard response.keys.contains(indexKey) else { return Index() }
        let raw = try await reveal(key: indexKey, token: token)
        guard let data = raw.data(using: .utf8) else { throw CLIError.invalidData("The Shush index is not UTF-8.") }
        return try decoder.decode(Index.self, from: data)
    }

    func saveIndex(_ index: Index, token: String) async throws {
        let data = try encoder.encode(index)
        guard data.count < 850_000, let value = String(data: data, encoding: .utf8) else {
            throw CLIError.invalidData("The Shush index reached its local safety limit.")
        }
        try await set([indexKey: value], token: token)
    }

    func reveal(item: Item, token: String) async throws -> Data {
        var encoded = ""
        for key in item.partKeys { encoded += try await reveal(key: key, token: token) }
        return try SecretCodec.decode(encoded, encoding: item.encoding)
    }

    func store(data: Data, name: String, kind: SecretKind, token: String) async throws -> Item {
        let id = UUID()
        let (encoding, encoded) = SecretCodec.encode(data)
        let chunks = SecretCodec.chunks(encoded)
        let stem = id.uuidString.replacingOccurrences(of: "-", with: "").uppercased()
        let keys = chunks.indices.map { String(format: "SHUSH_%@_P%04d", stem, $0 + 1) }
        do {
            for (key, chunk) in zip(keys, chunks) { try await set([key: chunk], token: token) }
        } catch {
            try? await delete(keys: keys, token: token)
            throw error
        }
        let now = Date()
        return Item(
            id: id, name: name, originalFilename: nil, kind: kind, encoding: encoding,
            partKeys: keys, byteCount: data.count, savedAt: now, updatedAt: now,
            retiredAt: nil, replacementID: nil,
            valueFingerprint: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        )
    }

    func delete(keys: [String], token: String) async throws {
        let _: DeleteResponse = try await request(
            path: "/v1/credentials", method: "DELETE", token: token,
            body: DeleteBody(vault: vaultName, keys: keys), as: DeleteResponse.self
        )
    }

    private func reveal(key: String, token: String) async throws -> String {
        let escaped = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
        let response: CredentialResponse = try await request(
            path: "/v1/credentials?vault=\(vaultName)&reveal=true&key=\(escaped)",
            token: token,
            as: CredentialResponse.self
        )
        guard let value = response.credentials?.first?.value else {
            throw CLIError.invalidData("Credential \(key) is missing.")
        }
        return value
    }

    private func set(_ credentials: [String: String], token: String) async throws {
        let _: SetResponse = try await request(
            path: "/v1/credentials", method: "POST", token: token,
            body: SetBody(vault: vaultName, credentials: credentials), as: SetResponse.self
        )
    }

    private func request<Response: Decodable>(
        path: String, method: String = "GET", token: String? = nil, as: Response.Type
    ) async throws -> Response {
        try await request(path: path, method: method, token: token, data: nil, as: Response.self)
    }

    private func request<Response: Decodable, Body: Encodable>(
        path: String, method: String, token: String? = nil, body: Body, as: Response.Type
    ) async throws -> Response {
        try await request(path: path, method: method, token: token, data: try encoder.encode(body), as: Response.self)
    }

    private func request<Response: Decodable>(
        path: String, method: String, token: String?, data: Data?, as: Response.Type
    ) async throws -> Response {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw CLIError.invalidData("Invalid local backend URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.httpBody = data
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if data != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let responseData: Data
        let response: URLResponse
        do {
            (responseData, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw CLIError.backend("Open and unlock Shush first. \(error.localizedDescription)")
        }
        guard let http = response as? HTTPURLResponse else {
            throw CLIError.backend("The local backend returned an invalid response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { throw CLIError.authentication("Authentication required. Run `shush auth login`.") }
            let apiError = try? decoder.decode(APIError.self, from: responseData)
            throw CLIError.backend(apiError?.error ?? "Local backend request failed (\(http.statusCode)).")
        }
        return try decoder.decode(Response.self, from: responseData)
    }
}

private enum SessionStore {
    private static let service = "com.shush.cli"

    static func save(_ value: String, profileID: UUID?) throws {
        delete(profileID: profileID)
        let status = SecItemAdd([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(profileID),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: Data(value.utf8)
        ] as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CLIError.authentication("Could not save the CLI session in Keychain (\(status)).")
        }
    }

    static func read(profileID: UUID?) -> String? {
        if let token = ProcessInfo.processInfo.environment["SHUSH_TOKEN"], !token.isEmpty {
            return token
        }
        var item: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(profileID),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ] as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func requireToken(profileID: UUID?) throws -> String {
        guard let token = read(profileID: profileID) else {
            throw CLIError.authentication("Not authenticated. Open Shush, then run `shush auth login`.")
        }
        return token
    }

    static func delete(profileID: UUID?) {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(profileID)
        ] as CFDictionary)
    }

    private static func account(_ profileID: UUID?) -> String {
        profileID.map { "agent-vault-profile-\($0.uuidString.lowercased())" }
            ?? "agent-vault-session"
    }
}

private struct CLIProfile: Codable, Identifiable {
    let id: UUID
    var label: String
    var email: String
    var vaultName: String
    let createdAt: Date
}

private struct CLIProfileConfiguration: Codable {
    var version = 1
    var profiles: [CLIProfile] = []
    var activeProfileID: UUID?
}

private struct CLIProfileRequest: Codable {
    let id: UUID
    let label: String
    let email: String
    let createdAt: Date
}

private enum CLIProfileStore {
    static func load() -> CLIProfileConfiguration {
        guard let data = try? Data(contentsOf: configurationURL) else {
            return CLIProfileConfiguration()
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(CLIProfileConfiguration.self, from: data))
            ?? CLIProfileConfiguration()
    }

    static func save(_ configuration: CLIProfileConfiguration) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let directory = configurationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(configuration).write(to: configurationURL, options: [.atomic])
    }

    static func saveRequest(_ request: CLIProfileRequest) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let directory = configurationURL.deletingLastPathComponent()
            .appendingPathComponent("profile-requests", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(
            "\(request.id.uuidString.lowercased()).json"
        )
        try encoder.encode(request).write(to: url, options: [.atomic])
    }

    static func resolve(arguments: [String]) throws -> CLIProfile? {
        if let index = arguments.firstIndex(of: "--profile"),
           arguments.indices.contains(index + 1) {
            return try find(arguments[index + 1])
        }
        if let environment = ProcessInfo.processInfo.environment["SHUSH_PROFILE"],
           !environment.isEmpty {
            return try find(environment)
        }
        if let binding = boundProfileIdentifier() {
            return try find(binding)
        }
        let configuration = load()
        guard let id = configuration.activeProfileID else {
            return configuration.profiles.first
        }
        return configuration.profiles.first { $0.id == id }
    }

    static func find(_ selector: String) throws -> CLIProfile {
        let profiles = load().profiles
        if let id = UUID(uuidString: selector),
           let profile = profiles.first(where: { $0.id == id }) {
            return profile
        }
        let matches = profiles.filter {
            $0.label.compare(selector, options: .caseInsensitive) == .orderedSame ||
            $0.email.compare(selector, options: .caseInsensitive) == .orderedSame
        }
        if matches.count == 1 { return matches[0] }
        if matches.isEmpty { throw CLIError.notFound("No Shush profile matches \(selector).") }
        throw CLIError.conflict("More than one profile matches \(selector). Use its UUID.")
    }

    private static func boundProfileIdentifier() -> String? {
        var directory = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        while true {
            let binding = directory.appendingPathComponent(".shush-profile")
            if let value = try? String(contentsOf: binding, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path { return nil }
            directory = parent
        }
    }

    private static var configurationURL: URL {
        if let override = ProcessInfo.processInfo.environment["SHUSH_CONFIG"],
           !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("Shush", isDirectory: true)
            .appendingPathComponent("profiles.json")
    }
}

private enum SecretKind: String, Codable {
    case secret, json, tfvars, environment, yaml, certificate, text, other
}

private enum SecretEncoding: String, Codable {
    case utf8, base64
}

private struct Item: Codable {
    let id: UUID
    var name: String
    var originalFilename: String?
    var kind: SecretKind
    var encoding: SecretEncoding
    var partKeys: [String]
    var byteCount: Int
    var savedAt: Date
    var updatedAt: Date
    var retiredAt: Date?
    var replacementID: UUID?
    var valueFingerprint: String? = nil
}

private struct ListItem: Encodable {
    let id: UUID
    let name: String
    let kind: SecretKind
    let byteCount: Int
    let updatedAt: Date
    let retired: Bool

    init(_ item: Item) {
        id = item.id
        name = item.name
        kind = item.kind
        byteCount = item.byteCount
        updatedAt = item.updatedAt
        retired = item.retiredAt != nil
    }
}

private struct Index: Codable {
    var version = 1
    var items: [Item] = []
}

private enum SecretCodec {
    static let chunkByteLimit = 420_000
    static let maximumFileBytes = 24 * 1_024 * 1_024

    static func encode(_ data: Data) -> (SecretEncoding, String) {
        if let string = String(data: data, encoding: .utf8), !string.contains("\0") { return (.utf8, string) }
        return (.base64, data.base64EncodedString())
    }

    static func decode(_ value: String, encoding: SecretEncoding) throws -> Data {
        if encoding == .utf8 { return Data(value.utf8) }
        guard let data = Data(base64Encoded: value) else { throw CLIError.invalidData("Stored Base64 data is damaged.") }
        return data
    }

    static func chunks(_ string: String) -> [String] {
        guard !string.isEmpty else { return [""] }
        var chunks: [String] = []
        var current = ""
        var bytes = 0
        for scalar in string.unicodeScalars {
            let piece = String(scalar)
            let size = piece.utf8.count
            if bytes + size > chunkByteLimit, !current.isEmpty {
                chunks.append(current)
                current = ""
                bytes = 0
            }
            current.append(piece)
            bytes += size
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}

private struct AuthResult: Decodable { let token: String }
private struct AccountIdentity: Decodable {
    let email: String
    let isOwner: Bool

    enum CodingKeys: String, CodingKey {
        case email
        case isOwner = "is_owner"
    }
}
private struct CredentialEntry: Decodable { let key: String; let value: String? }
private struct CredentialResponse: Decodable { let keys: [String]; let credentials: [CredentialEntry]? }
private struct SetBody: Encodable { let vault: String; let credentials: [String: String] }
private struct SetResponse: Decodable { let set: [String] }
private struct DeleteBody: Encodable { let vault: String; let keys: [String] }
private struct DeleteResponse: Decodable { let deleted: [String] }
private struct APIError: Decodable { let error: String }

private enum CLIError: LocalizedError {
    case usage(String), authentication(String), backend(String), invalidData(String)
    case conflict(String), notFound(String), fileTooLarge

    var errorDescription: String? {
        switch self {
        case .usage(let message), .authentication(let message), .backend(let message),
             .invalidData(let message), .conflict(let message), .notFound(let message):
            return message
        case .fileTooLarge:
            return "The value is larger than Shush's 24 MB safety limit."
        }
    }
}
