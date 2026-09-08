import AppKit
import Combine
import Foundation
import TickCore

@MainActor
final class TicksViewModel: ObservableObject {
    @Published private(set) var state = TicksState()
    @Published private(set) var isBusy = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var writesBlocked = false
    @Published var selectedSpaceID: UUID? {
        didSet { defaults.set(selectedSpaceID?.uuidString, forKey: "ticks.selectedSpaceID") }
    }
    var isVisible = false
    private let store: any TicksStoring
    private let defaults: UserDefaults
    private var monitoringTask: Task<Void, Never>?
    private var observers: [AnyCancellable] = []

    init(store: any TicksStoring = TicksStore(), defaults: UserDefaults = .standard, automaticallySyncs: Bool = false) {
        self.store = store
        self.defaults = defaults
        self.selectedSpaceID = defaults.string(forKey: "ticks.selectedSpaceID").flatMap(UUID.init(uuidString:))
        if automaticallySyncs { beginMonitoring() }
    }

    deinit { monitoringTask?.cancel() }

    var spaces: [TickWidgetStoredProject] {
        TickWidgetStoredProject.activeSortedByDisplayOrder(state.snapshot.projects)
    }

    var activeSession: TickWidgetStoredSession? { state.snapshot.sessions.first(where: \.isActive) }
    var activeSpaceName: String {
        state.snapshot.projects.first { $0.id == activeSession?.projectID }?.name ?? "Space"
    }

    var canStart: Bool {
        !isBusy && !writesBlocked && state.canRecord && activeSession == nil &&
            spaces.contains { $0.id == selectedSpaceID }
    }

    var canStop: Bool { !isBusy && !writesBlocked && state.canRecord && activeSession != nil }

    struct WeeklySpace: Identifiable {
        let id: UUID
        let name: String
        let duration: TimeInterval
    }

    func weeklySummary(at date: Date, calendar: Calendar = .current) -> (spaces: [WeeklySpace], count: Int) {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else { return ([], 0) }
        // Match Tick's summary: assign each session to its reference date's week.
        let sessions = state.snapshot.sessions.filter { interval.contains($0.referenceDate) }
        let names = Dictionary(uniqueKeysWithValues: state.snapshot.projects.map { ($0.id, $0.name) })
        let rows = Dictionary(grouping: sessions, by: \.projectID).map { id, sessions in
            WeeklySpace(id: id, name: names[id] ?? "Unknown Space",
                        duration: sessions.reduce(0) { $0 + $1.duration(at: date) })
        }.sorted {
            if $0.duration == $1.duration { return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            return $0.duration > $1.duration
        }
        return (rows, sessions.count)
    }

    var syncStatus: String {
        if state.hasPendingChanges { return "Saved locally—waiting for iCloud" }
        if isBusy { return "Checking iCloud…" }
        if let date = state.checkpoint?.confirmedAt {
            return "Last checked \(date.formatted(date: .omitted, time: .shortened))"
        }
        return hasLoaded ? "No Spaces loaded from iCloud" : "Loading Spaces…"
    }

    func beginMonitoring() {
        guard monitoringTask == nil else { return }
        observers = [
            NotificationCenter.default.publisher(for: .ticksCloudChanged).sink { [weak self] _ in
                Task { @MainActor [weak self] in await self?.refresh() }
            },
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification).sink { [weak self] _ in
                Task { @MainActor [weak self] in await self?.refresh() }
            }
        ]
        monitoringTask = Task { [weak self] in
            await self?.refresh()
            while !Task.isCancelled {
                let frequent = self.map { $0.isVisible || $0.state.hasPendingChanges } ?? false
                do { try await Task.sleep(for: .seconds(frequent ? 30 : 300)) }
                catch { return }
                guard self != nil else { return }
                await self?.refresh()
            }
        }
    }

    func refresh() async {
        await perform { try await self.store.refresh() }
    }

    func start() async {
        guard canStart, let projectID = selectedSpaceID else { return }
        let date = Date.now
        await perform { try await self.store.start(projectID: projectID, at: date) }
    }

    func stop() async {
        guard canStop, let sessionID = activeSession?.id else { return }
        let date = Date.now
        await perform { try await self.store.stop(sessionID: sessionID, at: date) }
    }

    private func perform(_ operation: () async throws -> TicksState) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            if !hasLoaded { apply(try await store.load()) }
            apply(try await operation())
            writesBlocked = false
            errorMessage = nil
        } catch {
            if let cached = try? await store.load() { apply(cached) }
            writesBlocked = !TicksStore.isTemporaryCloudFailure(error) && !(error is TickTimerMutation.Failure)
            errorMessage = error.localizedDescription
        }
        hasLoaded = true
    }

    private func apply(_ state: TicksState) {
        self.state = state
        if !spaces.contains(where: { $0.id == selectedSpaceID }) {
            selectedSpaceID = spaces.first?.id
        }
    }
}
