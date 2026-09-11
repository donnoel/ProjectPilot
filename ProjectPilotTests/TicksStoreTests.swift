import CloudKit
import Foundation
import Testing
import TickCore
@testable import ProjectPilot

struct TicksStoreTests {
    private func fixture() -> TickCloudPayload {
        TickCloudPayload(snapshot: TickWidgetStorageSnapshot(projects: [TickWidgetStoredProject(
            id: UUID(), name: "Beam", createdAt: Date(timeIntervalSince1970: 100), isArchived: false
        )], sessions: []))
    }

    @Test func threeClientsStartAndStopSameSession() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let payload = fixture()
        let cloud = FakeTicksCloud(payload)
        let mac = TicksStore(transport: cloud, fileURL: root.appendingPathComponent("mac.json"))
        let phone = TicksStore(transport: cloud, fileURL: root.appendingPathComponent("phone.json"))
        let pad = TicksStore(transport: cloud, fileURL: root.appendingPathComponent("pad.json"))
        let running = try await mac.start(projectID: payload.snapshot.projects[0].id, at: Date(timeIntervalSince1970: 200))
        let session = try #require(running.snapshot.sessions.first)
        #expect(try await phone.refresh().snapshot.sessions.first?.id == session.id)
        _ = try await pad.stop(sessionID: session.id, at: Date(timeIntervalSince1970: 260))
        #expect(try await mac.refresh().snapshot.sessions.first?.duration(at: .now) == 60)
        #expect(try await phone.refresh().snapshot.sessions.first?.isActive == false)
    }

    @Test func pauseAndResumeSyncAcrossClientsWithoutCountingPausedTime() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let payload = fixture()
        let cloud = FakeTicksCloud(payload)
        let mac = TicksStore(transport: cloud, fileURL: root.appendingPathComponent("mac.json"))
        let phone = TicksStore(transport: cloud, fileURL: root.appendingPathComponent("phone.json"))
        let running = try await mac.start(projectID: payload.snapshot.projects[0].id,
                                          at: Date(timeIntervalSince1970: 200))
        let sessionID = try #require(running.snapshot.sessions.first?.id)

        _ = try await mac.pause(sessionID: sessionID, at: Date(timeIntervalSince1970: 260))
        let paused = try await phone.refresh()
        #expect(paused.snapshot.sessions[0].pausedAt == Date(timeIntervalSince1970: 260))
        #expect(paused.snapshot.sessions[0].duration(at: Date(timeIntervalSince1970: 300)) == 60)

        _ = try await phone.resume(sessionID: sessionID, at: Date(timeIntervalSince1970: 320))
        let resumed = try await mac.refresh()
        #expect(resumed.snapshot.sessions[0].pausedAt == nil)
        #expect(resumed.snapshot.sessions[0].duration(at: Date(timeIntervalSince1970: 380)) == 120)
    }

    @Test func offlineOutboxSurvivesRelaunchAndPreservesRemoteRename() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("state.json")
        var payload = fixture()
        let cloud = FakeTicksCloud(payload)
        let mac = TicksStore(transport: cloud, fileURL: url)
        _ = try await mac.refresh()
        await cloud.setOffline(true)
        await #expect(throws: (any Error).self) {
            try await mac.start(projectID: payload.snapshot.projects[0].id, at: Date(timeIntervalSince1970: 200))
        }
        #expect(try await mac.load().hasPendingChanges)
        payload.snapshot.projects[0].name = "Beam campaign"
        await cloud.replace(payload)
        await cloud.setOffline(false)
        let relaunched = TicksStore(transport: cloud, fileURL: url)
        let synced = try await relaunched.refresh()
        #expect(!synced.hasPendingChanges)
        #expect(synced.snapshot.projects[0].name == "Beam campaign")
        #expect(synced.snapshot.sessions.filter(\.isActive).count == 1)
        #expect(await cloud.payload?.snapshot == synced.snapshot)
    }

    @Test func staleStopLeavesNewRemoteTimerRunning() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let payload = fixture()
        let cloud = FakeTicksCloud(payload)
        let mac = TicksStore(transport: cloud, fileURL: root.appendingPathComponent("state.json"))
        let running = try await mac.start(projectID: payload.snapshot.projects[0].id, at: Date(timeIntervalSince1970: 200))
        let firstID = try #require(running.snapshot.sessions.first?.id)
        var remote = try #require(await cloud.payload)
        try TickTimerMutation.stop(in: &remote.snapshot, sessionID: firstID, at: Date(timeIntervalSince1970: 210))
        let nextID = UUID()
        try TickTimerMutation.start(in: &remote.snapshot, projectID: remote.snapshot.projects[0].id,
                                    sessionID: nextID, at: Date(timeIntervalSince1970: 220))
        await cloud.replace(remote)
        let result = try await mac.stop(sessionID: firstID, at: Date(timeIntervalSince1970: 230))
        #expect(result.snapshot.sessions.first(where: \.isActive)?.id == nextID)
    }

    @Test func accountSwitchBlocksWritesAndKeepsOriginalCache() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cloud = FakeTicksCloud(fixture())
        let store = TicksStore(transport: cloud, fileURL: root.appendingPathComponent("state.json"))
        let initial = try await store.refresh()
        await cloud.changeAccount()
        await #expect(throws: (any Error).self) {
            try await store.start(projectID: initial.snapshot.projects[0].id, at: .now)
        }
        #expect(try await store.load().snapshot == initial.snapshot)
        #expect(await cloud.saveCount == 0)
    }

    @Test func malformedCacheAndMissingCloudRecordNeverOverwriteHistory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let cloud = FakeTicksCloud(fixture())
        let url = root.appendingPathComponent("state.json")
        let store = TicksStore(transport: cloud, fileURL: url)
        let initial = try await store.refresh()
        await cloud.replace(nil)
        await #expect(throws: (any Error).self) { try await store.refresh() }
        #expect(try await store.load().snapshot == initial.snapshot)
        try Data("broken".utf8).write(to: url, options: .atomic)
        await #expect(throws: (any Error).self) { try await store.refresh() }
        #expect(try Data(contentsOf: url) == Data("broken".utf8))
        #expect(await cloud.saveCount == 0)
    }

    @Test func firstReadDoesNotCreateEmptyCloudRecord() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cloud = FakeTicksCloud(nil)
        let store = TicksStore(transport: cloud, fileURL: root.appendingPathComponent("state.json"))
        #expect(try await store.refresh().canRecord == false)
        #expect(await cloud.saveCount == 0)
    }

    @Test func optimisticConflictRetriesWithoutDuplicatingStart() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let payload = fixture()
        let cloud = FakeTicksCloud(payload)
        await cloud.conflictOnNextSave()
        let store = TicksStore(transport: cloud, fileURL: root.appendingPathComponent("state.json"))
        let state = try await store.start(projectID: payload.snapshot.projects[0].id, at: .now)
        #expect(state.snapshot.sessions.count == 1)
        #expect(!state.hasPendingChanges)
        #expect(await cloud.saveCount == 1)
    }
}

private actor FakeTicksCloud: TickCloudTransport {
    var payload: TickCloudPayload?
    var saveCount = 0
    private var account = "account-a"
    private var offline = false
    private var version = 0
    private var conflict = false

    init(_ payload: TickCloudPayload?) { self.payload = payload }
    func setOffline(_ value: Bool) { offline = value }
    func changeAccount() { account = "account-b" }
    func conflictOnNextSave() { conflict = true }
    func replace(_ value: TickCloudPayload?) { payload = value; version += 1 }
    func accountID() throws -> String {
        if offline { throw CKError(.networkUnavailable) }
        return account
    }
    func subscribe() {}
    func fetch() throws -> TickCloudRemote? {
        if offline { throw CKError(.networkUnavailable) }
        return payload.map { TickCloudRemote(payload: $0, version: Data(String(version).utf8)) }
    }
    func save(_ payload: TickCloudPayload, version: Data?) throws -> TickCloudRemote {
        if offline { throw CKError(.networkUnavailable) }
        if conflict { conflict = false; throw TickCloudError.conflict }
        guard version == Data(String(self.version).utf8) else { throw TickCloudError.conflict }
        self.payload = payload
        self.version += 1
        saveCount += 1
        return TickCloudRemote(payload: payload, version: Data(String(self.version).utf8))
    }
}
