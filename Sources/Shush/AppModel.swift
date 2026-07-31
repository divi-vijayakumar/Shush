import AppKit
import CryptoKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    static let legacyVaultName = "shush"
    static let indexKey = "SHUSH_INDEX_V1"
    private static let legacyTokenAccount = "agent-vault-session"

    @Published var phase: AppPhase = .checking
    @Published var items: [ShushItem] = []
    @Published var selection: Set<UUID> = []
    @Published var filter: ItemFilter = .all
    @Published var searchText = ""
    @Published var isWorking = false
    @Published var activity = "Checking your local vault…"
    @Published var presentedError: String?
    @Published var clipboardNotice: String?
    @Published var scanFindings: [SecretFinding] = []
    @Published var scanSuppressedCount = 0
    @Published var isScanning = false
    @Published var accountProfile: AccountProfile?
    @Published var profiles: [ShushProfile] = []
    @Published var activeProfileID: UUID?
    @Published var pendingProfileRequests: [ProfileRequest] = []

    private let client = AgentVaultClient.shared
    private let backend = BackendManager.shared
    private var token: String?

    init() {
        let configuration = ProfileStore.load()
        profiles = Array(configuration.profiles.prefix(ProfileStore.maximumProfiles))
        activeProfileID = configuration.activeProfileID.flatMap { id in
            profiles.contains(where: { $0.id == id }) ? id : nil
        } ?? profiles.first?.id
        pendingProfileRequests = ProfileStore.pendingRequests()
    }

    var activeProfile: ShushProfile? {
        guard let activeProfileID else { return nil }
        return profiles.first { $0.id == activeProfileID }
    }

    var vaultName: String {
        activeProfile?.vaultName ?? Self.legacyVaultName
    }

    private var profileTokenAccount: String? {
        activeProfileID.map { "agent-vault-profile-\($0.uuidString.lowercased())" }
    }

    var filteredItems: [ShushItem] {
        items
            .filter(filter.includes)
            .filter {
                searchText.isEmpty ||
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                ($0.originalFilename?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var selectedItem: ShushItem? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return items.first { $0.id == id }
    }

    func start() {
        Task { await refreshState() }
    }

    func refreshState() async {
        phase = .checking
        activity = "Checking your local vault…"
        do {
            let status = try await client.status()
            if status.needsFirstUser {
                phase = .needsFirstSetup
                return
            }

            let savedToken: String?
            if let profileTokenAccount {
                savedToken = KeychainStore.read(account: profileTokenAccount)
            } else {
                savedToken = KeychainStore.read(account: Self.legacyTokenAccount)
            }
            guard let savedToken else {
                phase = .needsLogin
                return
            }
            do {
                try await client.authenticate(token: savedToken)
                token = savedToken
                if profiles.isEmpty {
                    let account = try await client.accountProfile(token: savedToken)
                    try migrateLegacyProfile(email: account.email, token: savedToken)
                }
                try await prepareVault()
            } catch {
                if let profileTokenAccount {
                    KeychainStore.delete(account: profileTokenAccount)
                } else {
                    KeychainStore.delete(account: Self.legacyTokenAccount)
                }
                token = nil
                phase = .needsLogin
            }
        } catch {
            phase = .serverOffline(existingData: await backend.databaseExists)
        }
    }

    func unlockBackend(passphrase: String) async {
        await perform("Unlocking Agent Vault…") {
            try await backend.start(masterPassword: passphrase)
            await refreshState()
        }
    }

    func createLocalVault(email: String, password: String) async {
        await perform("Creating your private local vault…") {
            if (try? await client.status()) == nil {
                try await backend.start(masterPassword: password)
            }
            let status = try await client.status()
            guard status.needsFirstUser else {
                throw ShushError.api("This Agent Vault already has an owner. Sign in instead.")
            }
            let auth = try await client.register(email: email, password: password)
            token = auth.token
            if profiles.isEmpty {
                try createInitialProfile(email: email, token: auth.token)
            } else if let profileTokenAccount {
                try KeychainStore.save(auth.token, account: profileTokenAccount)
            }
            try await prepareVault()
        }
    }

    func login(email: String, password: String) async {
        await perform("Signing in locally…") {
            let auth = try await client.login(email: email, password: password)
            let account = try await client.accountProfile(token: auth.token)
            if let activeProfile {
                guard account.email.compare(
                    activeProfile.email,
                    options: .caseInsensitive
                ) == .orderedSame else {
                    throw ShushError.api("This profile belongs to \(activeProfile.email).")
                }
                guard let profileTokenAccount else {
                    throw ShushError.invalidData("The active profile is damaged.")
                }
                try KeychainStore.save(auth.token, account: profileTokenAccount)
            } else {
                try createInitialProfile(email: account.email, token: auth.token)
            }
            token = auth.token
            try await prepareVault()
        }
    }

    func signOut() {
        if let profileTokenAccount {
            KeychainStore.delete(account: profileTokenAccount)
        }
        token = nil
        items = []
        accountProfile = nil
        selection = []
        scanFindings = []
        scanSuppressedCount = 0
        phase = .needsLogin
    }

    func addProfile(
        label: String,
        email: String,
        password: String,
        requestID: UUID? = nil
    ) async -> Bool {
        guard profiles.count < ProfileStore.maximumProfiles else {
            presentedError = "Shush supports up to \(ProfileStore.maximumProfiles) profiles."
            return false
        }
        let cleanLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanLabel.isEmpty else {
            presentedError = "Profile name cannot be empty."
            return false
        }
        guard !profiles.contains(where: {
            $0.label.compare(cleanLabel, options: .caseInsensitive) == .orderedSame
        }) else {
            presentedError = "A profile named \(cleanLabel) already exists."
            return false
        }

        isWorking = true
        activity = "Adding \(cleanLabel)…"
        defer { isWorking = false }
        do {
            let auth = try await client.login(email: email, password: password)
            let account = try await client.accountProfile(token: auth.token)
            let id = UUID()
            let newVault = ProfileStore.suggestedVaultName(label: cleanLabel, id: id)
            let vaults = try await client.listVaults(token: auth.token)
            if !vaults.contains(where: { $0.name == newVault }) {
                try await client.createVault(name: newVault, token: auth.token)
            }
            let profile = ShushProfile(
                id: id,
                label: cleanLabel,
                email: account.email,
                vaultName: newVault,
                createdAt: Date()
            )
            profiles.append(profile)
            activeProfileID = id
            try persistProfiles()
            try KeychainStore.save(auth.token, account: tokenAccount(for: id))
            token = auth.token
            selection = []
            items = []
            try await prepareVault()
            if let requestID {
                ProfileStore.removeRequest(requestID)
                refreshProfileRequests()
            }
            return true
        } catch {
            presentedError = error.localizedDescription
            return false
        }
    }

    func refreshProfileRequests() {
        pendingProfileRequests = ProfileStore.pendingRequests()
    }

    func dismissProfileRequest(_ id: UUID) {
        ProfileStore.removeRequest(id)
        refreshProfileRequests()
    }

    func switchProfile(to id: UUID) async {
        guard profiles.contains(where: { $0.id == id }), id != activeProfileID else {
            return
        }
        activeProfileID = id
        token = nil
        items = []
        selection = []
        accountProfile = nil
        searchText = ""
        filter = .all
        scanFindings = []
        scanSuppressedCount = 0
        do {
            try persistProfiles()
        } catch {
            presentedError = error.localizedDescription
        }
        await refreshState()
    }

    func removeProfile(_ id: UUID) async {
        guard profiles.count > 1 else {
            presentedError = "Keep at least one Shush profile."
            return
        }
        KeychainStore.delete(account: tokenAccount(for: id))
        profiles.removeAll { $0.id == id }
        if activeProfileID == id {
            activeProfileID = profiles.first?.id
            token = nil
            items = []
            selection = []
        }
        do {
            try persistProfiles()
        } catch {
            presentedError = error.localizedDescription
        }
        if activeProfileID != id {
            await refreshState()
        }
    }

    func saveQuickSecret(name: String, value: String, kind: SecretKind) async {
        let data = Data(value.utf8)
        await save(data: data, name: name, originalFilename: nil, preferredKind: kind)
    }

    func replace(_ item: ShushItem, with value: String) async {
        await perform("Encrypting replacement…") {
            let session = try requireToken()
            let replacement = try await storeItem(
                data: Data(value.utf8),
                name: item.name,
                originalFilename: item.originalFilename,
                kind: item.kind,
                token: session
            )
            guard let oldIndex = items.firstIndex(where: { $0.id == item.id }) else {
                try? await client.deleteCredentials(
                    replacement.partKeys,
                    vault: vaultName,
                    token: session
                )
                throw ShushError.invalidData("The original item is no longer in the vault.")
            }
            items[oldIndex].retiredAt = Date()
            items[oldIndex].replacementID = replacement.id
            items.append(replacement)
            do {
                try await saveIndex(token: session)
                selection = [replacement.id]
                filter = .all
            } catch {
                items.removeAll { $0.id == replacement.id }
                items[oldIndex].retiredAt = nil
                items[oldIndex].replacementID = nil
                try? await client.deleteCredentials(
                    replacement.partKeys,
                    vault: vaultName,
                    token: session
                )
                throw error
            }
        }
    }

    func scanDesktopAndDownloads() async {
        isScanning = true
        defer { isScanning = false }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = [
            home.appendingPathComponent("Desktop", isDirectory: true),
            home.appendingPathComponent("Downloads", isDirectory: true)
        ].filter { FileManager.default.fileExists(atPath: $0.path) }

        let findings = await Task.detached(priority: .userInitiated) {
            LocalSecretScanner.scan(urls: roots)
        }.value
        let visible = findings.filter {
            !isFindingAlreadyImported($0) && !ignoredFindingFingerprints.contains(findingFingerprint($0))
        }
        scanSuppressedCount = findings.count - visible.count
        scanFindings = visible
    }

    func importFinding(_ finding: SecretFinding) async {
        await save(
            data: Data(finding.value.utf8),
            name: "\(finding.kind) — \(finding.fileURL.lastPathComponent)",
            originalFilename: nil,
            preferredKind: .secret
        )
    }

    func isFindingAlreadyImported(_ finding: SecretFinding) -> Bool {
        let valueData = Data(finding.value.utf8)
        let valueFingerprint = Self.fingerprint(valueData)
        let expectedName = "\(finding.kind) — \(finding.fileURL.lastPathComponent)"
        return items.contains { item in
            item.valueFingerprint == valueFingerprint ||
                (item.valueFingerprint == nil &&
                    item.name.compare(expectedName, options: .caseInsensitive) == .orderedSame &&
                    item.byteCount == valueData.count)
        }
    }

    func ignoreFinding(_ finding: SecretFinding) {
        var fingerprints = ignoredFindingFingerprints
        fingerprints.insert(findingFingerprint(finding))
        UserDefaults.standard.set(Array(fingerprints), forKey: ignoredFindingDefaultsKey)
        scanFindings.removeAll { $0.id == finding.id }
    }

    func dismissFinding(_ finding: SecretFinding) {
        scanFindings.removeAll { $0.id == finding.id }
    }

    func moveFindingSourceToTrash(_ finding: SecretFinding) {
        let sourceURL = finding.fileURL
        NSWorkspace.shared.recycle([sourceURL]) { [weak self] _, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.presentedError = "Could not move \(sourceURL.lastPathComponent) to Trash: \(error.localizedDescription)"
                    return
                }
                self.scanFindings.removeAll { $0.fileURL == sourceURL }
            }
        }
    }

    func importFiles(_ urls: [URL]) async {
        for url in urls {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess { url.stopAccessingSecurityScopedResource() }
            }
            do {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values.isRegularFile == true else { continue }
                if let fileSize = values.fileSize, fileSize > SecretCodec.maximumFileBytes {
                    throw ShushError.fileTooLarge
                }
                let data = try Data(contentsOf: url, options: [.mappedIfSafe])
                let isText = String(data: data, encoding: .utf8) != nil
                let kind = SecretKind.infer(filename: url.lastPathComponent, isText: isText)
                await save(
                    data: data,
                    name: url.deletingPathExtension().lastPathComponent,
                    originalFilename: url.lastPathComponent,
                    preferredKind: kind
                )
            } catch {
                presentedError = "\(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
    }

    func reveal(_ item: ShushItem) async throws -> Data {
        let session = try requireToken()
        var encoded = ""
        for key in item.partKeys {
            encoded += try await client.revealCredential(
                key: key,
                vault: vaultName,
                token: session
            )
        }
        let data = try SecretCodec.decode(encoded, encoding: item.encoding)
        if item.valueFingerprint == nil,
           let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].valueFingerprint = Self.fingerprint(data)
            try? await saveIndex(token: session)
        }
        return data
    }

    func delete(_ item: ShushItem) async {
        await perform("Removing \(item.name)…") {
            let session = try requireToken()
            try await client.deleteCredentials(
                item.partKeys,
                vault: vaultName,
                token: session
            )
            items.removeAll { $0.id == item.id }
            try await saveIndex(token: session)
            selection.remove(item.id)
        }
    }

    func retireSelected() async {
        let ids = selection
        guard !ids.isEmpty else { return }
        await perform("Retiring selected items…") {
            let session = try requireToken()
            let original = items
            let now = Date()
            for index in items.indices
            where ids.contains(items[index].id) && !items[index].isRetired {
                items[index].retiredAt = now
                items[index].updatedAt = now
            }
            do {
                try await saveIndex(token: session)
                selection = []
                filter = .retired
            } catch {
                items = original
                throw error
            }
        }
    }

    func deleteSelected() async {
        let ids = selection
        guard !ids.isEmpty else { return }
        await perform("Deleting selected items…") {
            let session = try requireToken()
            let selected = items.filter { ids.contains($0.id) }
            try await client.deleteCredentials(
                selected.flatMap(\.partKeys),
                vault: vaultName,
                token: session
            )
            items.removeAll { ids.contains($0.id) }
            try await saveIndex(token: session)
            selection = []
        }
    }

    func updatePassword(current: String, new: String) async -> Bool {
        isWorking = true
        activity = "Updating your password…"
        defer { isWorking = false }
        do {
            let session = try requireToken()
            try await client.changePassword(current: current, new: new, token: session)
            return true
        } catch {
            presentedError = error.localizedDescription
            return false
        }
    }

    func duplicateCount(for item: ShushItem) -> Int {
        let sameName = items.filter {
            $0.id != item.id &&
            !$0.isRetired &&
            $0.name.compare(item.name, options: .caseInsensitive) == .orderedSame
        }
        let sameValue = item.valueFingerprint.map { fingerprint in
            items.filter {
                $0.id != item.id &&
                !$0.isRetired &&
                $0.valueFingerprint == fingerprint
            }
        } ?? []
        return Set((sameName + sameValue).map(\.id)).count
    }

    func copyToClipboard(_ string: String, label: String = "Copied securely") {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        clipboardNotice = label

        Task {
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            if NSPasteboard.general.string(forType: .string) == string {
                NSPasteboard.general.clearContents()
            }
        }
    }

    func copyForChat(_ value: String, item: ShushItem) {
        let filename = item.originalFilename ?? item.name
        let fenced = "\(filename)\n```\(item.kind.language)\n\(value)\n```"
        copyToClipboard(fenced, label: "Copied as a chat-ready code block")
    }

    private func save(
        data: Data,
        name: String,
        originalFilename: String?,
        preferredKind: SecretKind
    ) async {
        await perform("Encrypting \(name)…") {
            guard data.count <= SecretCodec.maximumFileBytes else {
                throw ShushError.fileTooLarge
            }
            let session = try requireToken()
            let newItem = try await storeItem(
                data: data,
                name: name,
                originalFilename: originalFilename,
                kind: preferredKind,
                token: session
            )
            do {
                items.append(newItem)
                try await saveIndex(token: session)
                selection = [newItem.id]
                phase = .ready
            } catch {
                items.removeAll { $0.id == newItem.id }
                try? await client.deleteCredentials(
                    newItem.partKeys,
                    vault: vaultName,
                    token: session
                )
                throw error
            }
        }
    }

    private func storeItem(
        data: Data,
        name: String,
        originalFilename: String?,
        kind: SecretKind,
        token: String
    ) async throws -> ShushItem {
        let id = UUID()
        let (encoding, encoded) = SecretCodec.encode(data)
        let chunks = SecretCodec.chunks(encoded)
        let stem = id.uuidString.replacingOccurrences(of: "-", with: "").uppercased()
        let keys = chunks.indices.map {
            String(format: "SHUSH_%@_P%04d", stem, $0 + 1)
        }

        do {
            for (key, chunk) in zip(keys, chunks) {
                try await client.setCredentials(
                    [key: chunk],
                    vault: vaultName,
                    token: token
                )
            }
        } catch {
            try? await client.deleteCredentials(keys, vault: vaultName, token: token)
            throw error
        }

        let now = Date()
        return ShushItem(
            id: id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            originalFilename: originalFilename,
            kind: kind,
            encoding: encoding,
            partKeys: keys,
            byteCount: data.count,
            savedAt: now,
            updatedAt: now,
            retiredAt: nil,
            replacementID: nil,
            valueFingerprint: Self.fingerprint(data)
        )
    }

    private func prepareVault() async throws {
        let session = try requireToken()
        let vaults = try await client.listVaults(token: session)
        if !vaults.contains(where: { $0.name == vaultName }) {
            try await client.createVault(name: vaultName, token: session)
        }
        try await loadIndex(token: session)
        accountProfile = try await client.accountProfile(token: session)
        phase = .ready
    }

    private func loadIndex(token: String) async throws {
        let keys = try await client.listCredentialKeys(vault: vaultName, token: token)
        guard keys.contains(Self.indexKey) else {
            items = []
            return
        }
        let raw = try await client.revealCredential(
            key: Self.indexKey,
            vault: vaultName,
            token: token
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = raw.data(using: .utf8) else {
            throw ShushError.invalidData("The Shush index is not valid UTF-8.")
        }
        items = try decoder.decode(ShushIndex.self, from: data).items
    }

    private func saveIndex(token: String) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(ShushIndex(items: items))
        guard data.count < 850_000, let string = String(data: data, encoding: .utf8) else {
            throw ShushError.invalidData("The Shush index has reached its local safety limit.")
        }
        try await client.setCredentials(
            [Self.indexKey: string],
            vault: vaultName,
            token: token
        )
    }

    private func requireToken() throws -> String {
        guard let token else { throw ShushError.authenticationRequired }
        return token
    }

    private func createInitialProfile(email: String, token: String) throws {
        let profile = ShushProfile(
            id: UUID(),
            label: "Personal",
            email: email,
            vaultName: Self.legacyVaultName,
            createdAt: Date()
        )
        profiles = [profile]
        activeProfileID = profile.id
        try persistProfiles()
        try KeychainStore.save(token, account: tokenAccount(for: profile.id))
        KeychainStore.delete(account: Self.legacyTokenAccount)
    }

    private func migrateLegacyProfile(email: String, token: String) throws {
        try createInitialProfile(email: email, token: token)
    }

    private func tokenAccount(for id: UUID) -> String {
        "agent-vault-profile-\(id.uuidString.lowercased())"
    }

    private func persistProfiles() throws {
        try ProfileStore.save(
            ProfileConfiguration(
                profiles: profiles,
                activeProfileID: activeProfileID
            )
        )
    }

    private var ignoredFindingDefaultsKey: String {
        "Shush.IgnoredScanFingerprints.\(activeProfileID?.uuidString.lowercased() ?? "legacy")"
    }

    private var ignoredFindingFingerprints: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: ignoredFindingDefaultsKey) ?? [])
    }

    private func findingFingerprint(_ finding: SecretFinding) -> String {
        Self.fingerprint(Data(finding.value.utf8))
    }

    private static func fingerprint(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func perform(_ message: String, operation: () async throws -> Void) async {
        isWorking = true
        activity = message
        defer { isWorking = false }
        do {
            try await operation()
        } catch ShushError.authenticationRequired {
            if let profileTokenAccount {
                KeychainStore.delete(account: profileTokenAccount)
            }
            token = nil
            phase = .needsLogin
            presentedError = ShushError.authenticationRequired.localizedDescription
        } catch {
            presentedError = error.localizedDescription
        }
    }
}
