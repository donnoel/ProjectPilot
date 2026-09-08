import Foundation
import Security
import TickCore

nonisolated enum TicksCloudAccess {
    static var isConfigured: Bool {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return false }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return false }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let values = information as? [String: Any],
              let entitlements = values[kSecCodeInfoEntitlementsDict as String] as? [String: Any],
              let containers = entitlements["com.apple.developer.icloud-container-identifiers"] as? [String],
              let services = entitlements["com.apple.developer.icloud-services"] as? [String] else { return false }
        return containers.contains(TickCloudKitTransport.containerIdentifier) && services.contains("CloudKit")
    }

    enum Failure: LocalizedError {
        case missingEntitlements
        var errorDescription: String? {
            "This copy of ProjectPilot isn't authorized for Ticks in iCloud. Install a signed build with Ticks access."
        }
    }
}

/// CKContainer traps when a development/test executable lacks its entitlements.
/// Fail visibly before touching CloudKit; injected test transports never use it.
actor ProvisionedTicksTransport: TickCloudTransport {
    private let cloud = TickCloudKitTransport(subscriptionID: TicksStore.subscriptionID)

    func accountID() async throws -> String {
        guard TicksCloudAccess.isConfigured else { throw TicksCloudAccess.Failure.missingEntitlements }
        return try await cloud.accountID()
    }
    func fetch() async throws -> TickCloudRemote? { try await cloud.fetch() }
    func save(_ payload: TickCloudPayload, version: Data?) async throws -> TickCloudRemote {
        try await cloud.save(payload, version: version)
    }
    func subscribe() async throws { try await cloud.subscribe() }
}
