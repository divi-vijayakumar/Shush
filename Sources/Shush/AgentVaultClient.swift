import Foundation

actor AgentVaultClient {
    static let shared = AgentVaultClient()

    let baseURL = URL(string: "http://127.0.0.1:14321")!
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init() {
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
    }

    func status() async throws -> VaultStatus {
        try await request(path: "/v1/status", as: VaultStatus.self)
    }

    func authenticate(token: String) async throws {
        let _: AccountProfile = try await request(
            path: "/v1/auth/me",
            token: token,
            as: AccountProfile.self
        )
    }

    func accountProfile(token: String) async throws -> AccountProfile {
        try await request(path: "/v1/auth/me", token: token, as: AccountProfile.self)
    }

    func changePassword(current: String, new: String, token: String) async throws {
        let _: ChangePasswordResponse = try await request(
            path: "/v1/auth/change-password",
            method: "POST",
            token: token,
            body: [
                "current_password": current,
                "new_password": new
            ],
            as: ChangePasswordResponse.self
        )
    }

    func register(email: String, password: String) async throws -> AuthResult {
        try await request(
            path: "/v1/auth/register",
            method: "POST",
            body: [
                "email": email,
                "password": password,
                "device_label": "Shush for Mac"
            ],
            as: AuthResult.self
        )
    }

    func login(email: String, password: String) async throws -> AuthResult {
        try await request(
            path: "/v1/auth/login",
            method: "POST",
            body: [
                "email": email,
                "password": password,
                "device_label": "Shush for Mac"
            ],
            as: AuthResult.self
        )
    }

    func listVaults(token: String) async throws -> [VaultSummary] {
        let response: VaultListResponse = try await request(
            path: "/v1/vaults",
            token: token,
            as: VaultListResponse.self
        )
        return response.vaults
    }

    func createVault(name: String, token: String) async throws {
        let _: VaultCreated = try await request(
            path: "/v1/vaults",
            method: "POST",
            token: token,
            body: ["name": name],
            as: VaultCreated.self
        )
    }

    func listCredentialKeys(vault: String, token: String) async throws -> [String] {
        let encoded = vault.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? vault
        let response: CredentialListResponse = try await request(
            path: "/v1/credentials?vault=\(encoded)",
            token: token,
            as: CredentialListResponse.self
        )
        return response.keys
    }

    func revealCredential(key: String, vault: String, token: String) async throws -> String {
        let encodedVault = vault.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? vault
        let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
        let response: CredentialListResponse = try await request(
            path: "/v1/credentials?vault=\(encodedVault)&reveal=true&key=\(encodedKey)",
            token: token,
            as: CredentialListResponse.self
        )
        guard let value = response.credentials?.first?.value else {
            throw ShushError.invalidData("Credential \(key) is missing.")
        }
        return value
    }

    func setCredentials(_ credentials: [String: String], vault: String, token: String) async throws {
        let body = SetCredentialsBody(vault: vault, credentials: credentials)
        let _: SetCredentialsResponse = try await request(
            path: "/v1/credentials",
            method: "POST",
            token: token,
            body: body,
            as: SetCredentialsResponse.self
        )
    }

    func deleteCredentials(_ keys: [String], vault: String, token: String) async throws {
        guard !keys.isEmpty else { return }
        let body = DeleteCredentialsBody(vault: vault, keys: keys)
        let _: DeleteCredentialsResponse = try await request(
            path: "/v1/credentials",
            method: "DELETE",
            token: token,
            body: body,
            as: DeleteCredentialsResponse.self
        )
    }

    private func request<Response: Decodable>(
        path: String,
        method: String = "GET",
        token: String? = nil,
        as type: Response.Type
    ) async throws -> Response {
        try await request(path: path, method: method, token: token, data: nil, as: type)
    }

    private func request<Response: Decodable, Body: Encodable>(
        path: String,
        method: String = "GET",
        token: String? = nil,
        body: Body,
        as type: Response.Type
    ) async throws -> Response {
        try await request(path: path, method: method, token: token, data: try encoder.encode(body), as: type)
    }

    private func request<Response: Decodable>(
        path: String,
        method: String,
        token: String?,
        data: Data?,
        as type: Response.Type
    ) async throws -> Response {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw ShushError.invalidData("Invalid Agent Vault URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.httpBody = data
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if data != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let responseData: Data
        let response: URLResponse
        do {
            (responseData, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ShushError.backendUnavailable(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ShushError.api("Agent Vault returned an invalid response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { throw ShushError.authenticationRequired }
            let apiError = try? decoder.decode(APIError.self, from: responseData)
            throw ShushError.api(apiError?.error ?? "Agent Vault request failed (\(http.statusCode)).")
        }
        do {
            return try decoder.decode(Response.self, from: responseData)
        } catch {
            throw ShushError.invalidData("Could not read Agent Vault’s response: \(error.localizedDescription)")
        }
    }
}

private struct VaultCreated: Decodable {
    let name: String
}

private struct ChangePasswordResponse: Decodable {
    let message: String?
}

private struct SetCredentialsBody: Encodable {
    let vault: String
    let credentials: [String: String]
}

private struct SetCredentialsResponse: Decodable {
    let set: [String]
}

private struct DeleteCredentialsBody: Encodable {
    let vault: String
    let keys: [String]
}

private struct DeleteCredentialsResponse: Decodable {
    let deleted: [String]
}

private struct APIError: Decodable {
    let error: String
}
