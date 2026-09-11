import CloudKit
import Foundation
import TickCore

nonisolated struct TicksState: Codable, Sendable {
    var snapshot: TickWidgetStorageSnapshot = .empty
    var checkpoint: TickCloudCheckpoint?

    var hasPendingChanges: Bool {
        guard let acknowledged = checkpoint?.acknowledged else { return false }
        return snapshot != acknowledged.snapshot
    }

    var canRecord: Bool { checkpoint?.acknowledged != nil }
}

nonisolated protocol TicksStoring: Sendable {
    func load() async throws -> TicksState
    func refresh() async throws -> TicksState
    func start(projectID: UUID, at date: Date) async throws -> TicksState
    func pause(sessionID: UUID, at date: Date) async throws -> TicksState
    func resume(sessionID: UUID, at date: Date) async throws -> TicksState
    func stop(sessionID: UUID, at date: Date) async throws -> TicksState
}

/// The Mac owns its cache. Only CloudKit connects it to the iPhone and iPad;
/// ProjectPilot never opens Tick's on-device App Group or iCloud Drive files.
actor TicksStore: TicksStoring {
    nonisolated static let subscriptionID = "projectpilot-ticks-snapshot-v1"
    private let transport: any TickCloudTransport
    private let fileURL: URL
    private var flight: Task<TicksState, Error>?
    private var subscribedAccount: String?

    init(transport: any TickCloudTransport = ProvisionedTicksTransport(),
         fileURL: URL = TicksStore.defaultFileURL) {
        self.transport = transport
        self.fileURL = fileURL
    }

    nonisolated static var defaultFileURL: URL {
        let environment = Bundle.main.object(forInfoDictionaryKey: "TickCloudEnvironment") as? String ?? "Development"
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("dn.ProjectPilot/Ticks/\(environment)/state.json")
    }

    func load() throws -> TicksState {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return TicksState() }
        // A failed decode must never become an empty snapshot and overwrite cloud history.
        do { return try TickCloudCodec.decode(TicksState.self, from: Data(contentsOf: fileURL)) }
        catch is DecodingError { throw Failure.unreadableCache }
    }

    private func save(_ state: TicksState) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try TickCloudCodec.encode(state).write(to: fileURL, options: .atomic)
    }

    func refresh() async throws -> TicksState {
        if let flight { return try await flight.value }
        let task = Task {
            defer { self.flight = nil }
            return try await self.synchronize()
        }
        flight = task
        return try await task.value
    }

    func start(projectID: UUID, at date: Date) async throws -> TicksState {
        try await refreshBeforeAction()
        var state = try load()
        guard state.canRecord else { throw Failure.needsFirstSync }
        try TickTimerMutation.start(in: &state.snapshot, projectID: projectID, at: date)
        try save(state)
        return try await refresh()
    }

    func pause(sessionID: UUID, at date: Date) async throws -> TicksState {
        try await refreshBeforeAction()
        var state = try load()
        guard state.canRecord else { throw Failure.needsFirstSync }
        try TickTimerMutation.pause(in: &state.snapshot, sessionID: sessionID, at: date)
        try save(state)
        return try await refresh()
    }

    func resume(sessionID: UUID, at date: Date) async throws -> TicksState {
        try await refreshBeforeAction()
        var state = try load()
        guard state.canRecord else { throw Failure.needsFirstSync }
        try TickTimerMutation.resume(in: &state.snapshot, sessionID: sessionID, at: date)
        try save(state)
        return try await refresh()
    }

    func stop(sessionID: UUID, at date: Date) async throws -> TicksState {
        try await refreshBeforeAction()
        var state = try load()
        guard state.canRecord else { throw Failure.needsFirstSync }
        try TickTimerMutation.stop(in: &state.snapshot, sessionID: sessionID, at: date)
        try save(state)
        return try await refresh()
    }

    private func refreshBeforeAction() async throws {
        do { _ = try await refresh() }
        catch {
            // Offline capture is allowed only after this cache has joined a known
            // account. Authentication, account changes and malformed data block writes.
            guard Self.isTemporaryCloudFailure(error), try load().canRecord else { throw error }
        }
    }

    private func synchronize() async throws -> TicksState {
        let account = try await transport.accountID()
        let initial = try load()
        if let boundAccount = initial.checkpoint?.accountID, boundAccount != account {
            throw TickCloudError.accountChanged
        }

        for _ in 0..<4 {
            let remote = try await transport.fetch()
            let local = try load()
            guard remote != nil else {
                guard local.checkpoint?.acknowledged == nil else { throw TickCloudError.invalidRecord }
                // A read-only first connection must not create a blank cloud record.
                return local
            }
            guard let remote else { throw TickCloudError.invalidRecord }
            let merged = TickCloudMerge.resolve(base: local.checkpoint?.acknowledged?.snapshot ?? .empty,
                                               local: local.snapshot, remote: remote.payload)
            let saved: TickCloudRemote
            do {
                saved = merged == remote.payload ? remote : try await transport.save(merged, version: remote.version)
            } catch TickCloudError.conflict {
                continue
            }

            guard try await transport.accountID() == account else { throw TickCloudError.accountChanged }
            // Actor reentrancy permits another local action during an upload. Keep
            // those edits in the durable outbox until the next acknowledgment.
            let latest = try load()
            let resolved = TickCloudMerge.resolve(base: local.snapshot, local: latest.snapshot, remote: saved.payload)
            let state = TicksState(snapshot: resolved.snapshot, checkpoint: TickCloudCheckpoint(
                accountID: account, acknowledged: saved.payload, confirmedAt: .now
            ))
            try save(state)
            if !state.hasPendingChanges {
                if subscribedAccount != account {
                    try await transport.subscribe()
                    subscribedAccount = account
                }
                return state
            }
        }
        throw TickCloudError.busy
    }

    nonisolated static func isTemporaryCloudFailure(_ error: Error) -> Bool {
        if let error = error as? TickCloudError {
            switch error {
            case .busy, .conflict: return true
            case .accountChanged, .invalidRecord: return false
            }
        }
        guard let error = error as? CKError else { return false }
        return [.networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy]
            .contains(error.code)
    }

    nonisolated enum Failure: LocalizedError {
        case needsFirstSync
        case unreadableCache

        var errorDescription: String? {
            switch self {
            case .needsFirstSync: "Connect to iCloud and load your Spaces before recording a Tick."
            case .unreadableCache: "Ticks could not read its saved data. The local file has been preserved."
            }
        }
    }
}
