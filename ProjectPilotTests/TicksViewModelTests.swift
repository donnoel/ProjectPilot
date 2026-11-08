import CloudKit
import Foundation
import Testing
import TickCore
@testable import ProjectPilot

@MainActor
struct TicksViewModelTests {
    @Test func authenticationFailureBlocksControlsWithoutDiscardingCachedSpaces() async throws {
        let fixture = makeState()
        let store = ViewModelTestStore(state: fixture, failure: .notAuthenticated)
        let suite = "TicksViewModelTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = TicksViewModel(store: store, defaults: defaults)
        await model.refresh()
        #expect(model.spaces.count == 1)
        #expect(model.writesBlocked)
        #expect(!model.canStart)
        #expect(model.errorMessage != nil)
    }

    @Test func offlineCacheRemainsUsableAndPendingStatusIsHonest() async throws {
        var fixture = makeState()
        try TickTimerMutation.start(in: &fixture.snapshot, projectID: fixture.snapshot.projects[0].id, at: .now)
        let store = ViewModelTestStore(state: fixture, failure: .networkUnavailable)
        let suite = "TicksViewModelTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = TicksViewModel(store: store, defaults: defaults)
        await model.refresh()
        #expect(model.canStop)
        #expect(model.canPause)
        #expect(!model.canResume)
        #expect(!model.canStart)
        #expect(model.syncStatus == "Saved locally—waiting for iCloud")
    }

    @Test func pausedSessionCanResumeOrStopButCannotPauseAgain() async throws {
        var fixture = makeState()
        try TickTimerMutation.start(in: &fixture.snapshot, projectID: fixture.snapshot.projects[0].id, at: .now)
        fixture.snapshot.sessions[0].pausedAt = .now
        let suite = "TicksViewModelTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = TicksViewModel(store: ViewModelTestStore(state: fixture), defaults: defaults)

        await model.refresh()

        #expect(model.canResume)
        #expect(model.canStop)
        #expect(!model.canPause)
        #expect(!model.canStart)
    }

    @Test func unavailableSavedSelectionFallsBackToAnExistingSpace() async throws {
        let fixture = makeState()
        let suite = "TicksViewModelTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(UUID().uuidString, forKey: "ticks.selectedSpaceID")
        let model = TicksViewModel(store: ViewModelTestStore(state: fixture), defaults: defaults)
        await model.refresh()
        #expect(model.selectedSpaceID == fixture.snapshot.projects[0].id)
        #expect(model.canStart)
    }

    @Test func runningTickDetailsSaveThroughTheViewModel() async throws {
        var fixture = makeState()
        let sessionID = UUID()
        try TickTimerMutation.start(
            in: &fixture.snapshot,
            projectID: fixture.snapshot.projects[0].id,
            sessionID: sessionID,
            at: .now
        )
        let store = ViewModelTestStore(state: fixture)
        let suite = "TicksViewModelTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = TicksViewModel(store: store, defaults: defaults)
        await model.refresh()

        let saved = await model.updateDetails(
            sessionID: sessionID,
            title: "  Review launch plan  ",
            notes: " Capture follow-up items. "
        )

        #expect(saved)
        #expect(model.activeSession?.title == "Review launch plan")
        #expect(model.activeSession?.notes == "Capture follow-up items.")
    }

    @Test func offlineRunningTickDetailsDismissAfterSavingToTheOutbox() async throws {
        var fixture = makeState()
        let sessionID = UUID()
        try TickTimerMutation.start(
            in: &fixture.snapshot,
            projectID: fixture.snapshot.projects[0].id,
            sessionID: sessionID,
            at: .now
        )
        let store = ViewModelTestStore(state: fixture)
        let suite = "TicksViewModelTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = TicksViewModel(store: store, defaults: defaults)
        await model.refresh()
        await store.setFailure(.networkUnavailable)

        let saved = await model.updateDetails(
            sessionID: sessionID,
            title: "Offline work",
            notes: "Saved before reconnecting."
        )

        #expect(saved)
        #expect(model.activeSession?.title == "Offline work")
        #expect(model.state.hasPendingChanges)
        #expect(model.syncStatus == "Saved locally—waiting for iCloud")
    }

    private func makeState() -> TicksState {
        let snapshot = TickWidgetStorageSnapshot(projects: [TickWidgetStoredProject(
            id: UUID(), name: "Beam", createdAt: .now, isArchived: false
        )], sessions: [])
        return TicksState(snapshot: snapshot, checkpoint: TickCloudCheckpoint(
            accountID: "test", acknowledged: TickCloudPayload(snapshot: snapshot), confirmedAt: .now
        ))
    }
}

private actor ViewModelTestStore: TicksStoring {
    var state: TicksState
    var failure: CKError.Code?
    init(state: TicksState, failure: CKError.Code? = nil) { self.state = state; self.failure = failure }
    func setFailure(_ failure: CKError.Code?) { self.failure = failure }
    func load() -> TicksState { state }
    func refresh() throws -> TicksState {
        if let failure { throw CKError(failure) }
        return state
    }
    func start(projectID: UUID, at date: Date) throws -> TicksState { try refresh() }
    func pause(sessionID: UUID, at date: Date) throws -> TicksState { try refresh() }
    func resume(sessionID: UUID, at date: Date) throws -> TicksState { try refresh() }
    func stop(sessionID: UUID, at date: Date) throws -> TicksState { try refresh() }
    func updateDetails(sessionID: UUID, title: String, notes: String) throws -> TicksState {
        try TickTimerMutation.updateDetails(
            in: &state.snapshot,
            sessionID: sessionID,
            title: title,
            notes: notes
        )
        if let failure { throw CKError(failure) }
        return state
    }
}
