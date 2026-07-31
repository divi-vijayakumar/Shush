import Foundation

struct ShushProfile: Codable, Identifiable, Hashable {
    let id: UUID
    var label: String
    var email: String
    var vaultName: String
    let createdAt: Date
}

struct ProfileConfiguration: Codable {
    var version = 1
    var profiles: [ShushProfile] = []
    var activeProfileID: UUID?
}

struct ProfileRequest: Codable, Identifiable, Hashable {
    let id: UUID
    let label: String
    let email: String
    let createdAt: Date
}

enum ProfileStore {
    static let maximumProfiles = 10

    static func load() -> ProfileConfiguration {
        guard let data = try? Data(contentsOf: configurationURL) else {
            return ProfileConfiguration()
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(ProfileConfiguration.self, from: data)) ?? ProfileConfiguration()
    }

    static func save(_ configuration: ProfileConfiguration) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)
        let directory = configurationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try data.write(to: configurationURL, options: [.atomic])
    }

    static func suggestedVaultName(label: String, id: UUID = UUID()) -> String {
        let slug = label.lowercased()
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character(String($0)) : "-" }
            .reduce(into: "") { $0.append($1) }
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        let base = slug.isEmpty ? "profile" : String(slug.prefix(40))
        return "shush-\(base)-\(id.uuidString.prefix(6).lowercased())"
    }

    static func pendingRequests() -> [ProfileRequest] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: requestsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(ProfileRequest.self, from: data)
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    static func removeRequest(_ id: UUID) {
        try? FileManager.default.removeItem(
            at: requestsDirectory.appendingPathComponent("\(id.uuidString.lowercased()).json")
        )
    }

    private static var configurationURL: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("Shush", isDirectory: true)
            .appendingPathComponent("profiles.json")
    }

    private static var requestsDirectory: URL {
        configurationURL.deletingLastPathComponent()
            .appendingPathComponent("profile-requests", isDirectory: true)
    }
}
