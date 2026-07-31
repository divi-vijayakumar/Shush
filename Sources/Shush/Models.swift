import Foundation
import UniformTypeIdentifiers

enum SecretKind: String, Codable, CaseIterable, Identifiable {
    case secret
    case json
    case tfvars
    case environment
    case yaml
    case certificate
    case text
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .secret: "Secret"
        case .json: "JSON"
        case .tfvars: "TFVars"
        case .environment: "Environment"
        case .yaml: "YAML"
        case .certificate: "Certificate"
        case .text: "Text"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .secret: "key.fill"
        case .json: "curlybraces"
        case .tfvars: "shippingbox.fill"
        case .environment: "terminal.fill"
        case .yaml: "list.bullet.rectangle"
        case .certificate: "checkmark.seal.fill"
        case .text: "doc.text.fill"
        case .other: "doc.fill"
        }
    }

    var language: String {
        switch self {
        case .json: "json"
        case .tfvars: "hcl"
        case .environment: "dotenv"
        case .yaml: "yaml"
        case .certificate: "text"
        case .secret, .text, .other: "text"
        }
    }

    static func infer(filename: String, isText: Bool) -> SecretKind {
        let lower = filename.lowercased()
        let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
        if ext == "json" { return .json }
        if ext == "tfvars" || lower.hasSuffix(".tfvars.json") { return .tfvars }
        if ext == "env" || lower == ".env" || lower.contains(".env.") { return .environment }
        if ["yaml", "yml"].contains(ext) { return .yaml }
        if ["pem", "crt", "cer", "p12", "pfx", "key"].contains(ext) { return .certificate }
        if isText { return .text }
        return .other
    }
}

enum SecretEncoding: String, Codable {
    case utf8
    case base64
}

struct ShushItem: Identifiable, Codable, Hashable {
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

    var subtitle: String {
        let source = originalFilename ?? kind.label
        return "\(source) · \(ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file))"
    }

    var isRetired: Bool { retiredAt != nil }
}

struct ShushIndex: Codable {
    var version = 1
    var items: [ShushItem] = []
}

enum ItemFilter: String, CaseIterable, Identifiable {
    case all
    case secrets
    case structured
    case files
    case retired

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "All items"
        case .secrets: "Quick secrets"
        case .structured: "JSON & config"
        case .files: "Other files"
        case .retired: "Retired"
        }
    }

    var symbol: String {
        switch self {
        case .all: "square.grid.2x2.fill"
        case .secrets: "key.fill"
        case .structured: "curlybraces.square.fill"
        case .files: "doc.on.doc.fill"
        case .retired: "archivebox.fill"
        }
    }

    func includes(_ item: ShushItem) -> Bool {
        switch self {
        case .all:
            !item.isRetired
        case .secrets:
            item.kind == .secret && !item.isRetired
        case .structured:
            [.json, .tfvars, .environment, .yaml].contains(item.kind) && !item.isRetired
        case .files:
            ![.secret, .json, .tfvars, .environment, .yaml].contains(item.kind) && !item.isRetired
        case .retired:
            item.isRetired
        }
    }
}

struct SecretFinding: Identifiable, Hashable {
    let id = UUID()
    let kind: String
    let value: String
    let fileURL: URL
    let line: Int

    var maskedValue: String {
        guard value.count > 8 else { return "••••••••" }
        return "\(value.prefix(4))••••••\(value.suffix(4))"
    }
}

enum AppPhase: Equatable {
    case checking
    case serverOffline(existingData: Bool)
    case needsFirstSetup
    case needsLogin
    case ready
    case failed(String)
}

struct VaultStatus: Decodable {
    let initialized: Bool
    let needsFirstUser: Bool

    enum CodingKeys: String, CodingKey {
        case initialized
        case needsFirstUser = "needs_first_user"
    }
}

struct AuthResult: Decodable {
    let token: String
    let expiresAt: String?

    enum CodingKeys: String, CodingKey {
        case token
        case expiresAt = "expires_at"
    }
}

struct AccountProfile: Decodable {
    let email: String
    let isOwner: Bool

    enum CodingKeys: String, CodingKey {
        case email
        case isOwner = "is_owner"
    }
}

struct VaultSummary: Decodable {
    let name: String
}

struct VaultListResponse: Decodable {
    let vaults: [VaultSummary]
}

struct CredentialEntry: Decodable {
    let key: String
    let value: String?
}

struct CredentialListResponse: Decodable {
    let keys: [String]
    let credentials: [CredentialEntry]?
}

enum SecretCodec {
    static let chunkByteLimit = 420_000
    static let maximumFileBytes = 24 * 1_024 * 1_024

    static func encode(_ data: Data) -> (SecretEncoding, String) {
        if let string = String(data: data, encoding: .utf8), !string.contains("\0") {
            return (.utf8, string)
        }
        return (.base64, data.base64EncodedString())
    }

    static func decode(_ value: String, encoding: SecretEncoding) throws -> Data {
        switch encoding {
        case .utf8:
            return Data(value.utf8)
        case .base64:
            guard let data = Data(base64Encoded: value) else {
                throw ShushError.invalidData("The stored Base64 value is damaged.")
            }
            return data
        }
    }

    static func chunks(_ string: String, maxBytes: Int = chunkByteLimit) -> [String] {
        guard !string.isEmpty else { return [""] }
        var chunks: [String] = []
        var current = ""
        var currentBytes = 0
        for scalar in string.unicodeScalars {
            let piece = String(scalar)
            let size = piece.utf8.count
            if currentBytes + size > maxBytes, !current.isEmpty {
                chunks.append(current)
                current = ""
                currentBytes = 0
            }
            current.append(piece)
            currentBytes += size
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}

enum ShushError: LocalizedError {
    case backendUnavailable(String)
    case authenticationRequired
    case invalidData(String)
    case api(String)
    case fileTooLarge

    var errorDescription: String? {
        switch self {
        case .backendUnavailable(let detail): "Agent Vault is unavailable. \(detail)"
        case .authenticationRequired: "Your local Agent Vault session has expired. Sign in again."
        case .invalidData(let detail): detail
        case .api(let detail): detail
        case .fileTooLarge: "This file is larger than Shush’s 24 MB safety limit."
        }
    }
}
