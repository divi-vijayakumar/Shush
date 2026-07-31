import Foundation
import XCTest
@testable import Shush

final class SecretCodecTests: XCTestCase {
    func testUTF8RoundTripAcrossChunks() throws {
        let original = String(repeating: "quiet-secret-🔐\n", count: 200)
        let chunks = SecretCodec.chunks(original, maxBytes: 37)
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertEqual(chunks.joined(), original)
        XCTAssertTrue(chunks.allSatisfy { $0.utf8.count <= 37 })
    }

    func testBinaryRoundTrip() throws {
        let original = Data([0x00, 0xFF, 0x10, 0x42])
        let (encoding, encoded) = SecretCodec.encode(original)
        XCTAssertEqual(encoding, .base64)
        XCTAssertEqual(try SecretCodec.decode(encoded, encoding: encoding), original)
    }

    func testFilterHidesRetiredItemsFromAll() {
        let retired = ShushItem(
            id: UUID(),
            name: "Old key",
            originalFilename: nil,
            kind: .secret,
            encoding: .utf8,
            partKeys: ["OLD"],
            byteCount: 3,
            savedAt: Date(),
            updatedAt: Date(),
            retiredAt: Date(),
            replacementID: UUID()
        )
        XCTAssertFalse(ItemFilter.all.includes(retired))
        XCTAssertTrue(ItemFilter.retired.includes(retired))
    }

    func testLocalScannerFindsProviderPrefixedSecret() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent(".env")
        try Data("STRIPE_KEY=sk_test_abcdefghijklmnop123456".utf8).write(to: file)

        let results = LocalSecretScanner.scan(urls: [directory])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.value, "sk_test_abcdefghijklmnop123456")
        XCTAssertEqual(results.first?.line, 1)
    }

    func testLocalScannerIgnoresCodePropertyNamedAccessToken() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("bundle.js")
        try Data("value = a.initialLoggingMetadata.accessToken\n".utf8).write(to: file)

        XCTAssertTrue(LocalSecretScanner.scan(urls: [directory]).isEmpty)
    }

    @MainActor
    func testSweepRecognizesPreviouslyImportedLegacyFinding() {
        let finding = SecretFinding(
            kind: "Stripe secret key",
            value: "sk_test_abcdefghijklmnop123456",
            fileURL: URL(fileURLWithPath: "/tmp/downloaded.env"),
            line: 1
        )
        let model = AppModel()
        model.items = [
            ShushItem(
                id: UUID(),
                name: "Stripe secret key — downloaded.env",
                originalFilename: nil,
                kind: .secret,
                encoding: .utf8,
                partKeys: ["SHUSH_TEST_P0001"],
                byteCount: Data(finding.value.utf8).count,
                savedAt: Date(),
                updatedAt: Date(),
                retiredAt: nil,
                replacementID: nil
            )
        ]

        XCTAssertTrue(model.isFindingAlreadyImported(finding))
    }

    func testOlderIndexWithoutFingerprintStillDecodes() throws {
        let json = """
        {
          "version": 1,
          "items": [{
            "id": "00000000-0000-0000-0000-000000000001",
            "name": "Legacy key",
            "kind": "secret",
            "encoding": "utf8",
            "partKeys": ["SHUSH_LEGACY_P0001"],
            "byteCount": 6,
            "savedAt": "2026-07-30T00:00:00Z",
            "updatedAt": "2026-07-30T00:00:00Z"
          }]
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let index = try decoder.decode(ShushIndex.self, from: Data(json.utf8))
        XCTAssertEqual(index.items.first?.name, "Legacy key")
        XCTAssertNil(index.items.first?.valueFingerprint)
    }

    func testAccountProfileDecodesEmailAndOwnerRole() throws {
        let profile = try JSONDecoder().decode(
            AccountProfile.self,
            from: Data(#"{"email":"owner@shush.local","is_owner":true,"type":"user"}"#.utf8)
        )
        XCTAssertEqual(profile.email, "owner@shush.local")
        XCTAssertTrue(profile.isOwner)
    }

    func testProfileVaultNamesAreIsolatedAndBackendCompatible() {
        let first = ProfileStore.suggestedVaultName(
            label: "Personal Projects",
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        )
        let second = ProfileStore.suggestedVaultName(
            label: "Work",
            id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        )

        XCTAssertEqual(first, "shush-personal-projects-aaaaaa")
        XCTAssertEqual(second, "shush-work-bbbbbb")
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(ProfileStore.maximumProfiles, 10)
    }

    func testProfileConfigurationRoundTrip() throws {
        let profile = ShushProfile(
            id: UUID(),
            label: "Work",
            email: "me@company.test",
            vaultName: "shush-work-123456",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let configuration = ProfileConfiguration(
            profiles: [profile],
            activeProfileID: profile.id
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let restored = try decoder.decode(
            ProfileConfiguration.self,
            from: encoder.encode(configuration)
        )
        XCTAssertEqual(restored.profiles, [profile])
        XCTAssertEqual(restored.activeProfileID, profile.id)
    }
}
