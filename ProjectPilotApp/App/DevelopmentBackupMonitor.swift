import CoreServices
import Foundation

/// Monotonic scheduling keeps idle checks cheap and batches bursts of source changes.
nonisolated struct DevelopmentBackupSchedule: Sendable {
    private(set) var firstChange: TimeInterval?
    private(set) var lastChange: TimeInterval
    private(set) var lastAttempt: TimeInterval?
    private(set) var lastSuccess: TimeInterval?
    private var retryAfter: TimeInterval?

    init(now: TimeInterval) {
        firstChange = now
        lastChange = now
    }

    mutating func changed(at now: TimeInterval) {
        if firstChange == nil { firstChange = now }
        lastChange = now
    }

    func shouldRun(at now: TimeInterval) -> Bool {
        if let retryAfter, now < retryAfter { return false }
        if let lastAttempt, now - lastAttempt < 300 { return false }
        // Reconcile hourly even if notifications were lost or the source was recreated.
        if let lastSuccess, now - lastSuccess >= 3600 { return true }
        guard let firstChange else { return false }
        return now - lastChange >= 60 || now - firstChange >= 900
    }

    mutating func began(at now: TimeInterval) {
        lastAttempt = now
        firstChange = nil
        retryAfter = nil
    }

    mutating func finished(at now: TimeInterval, succeeded: Bool) {
        if succeeded {
            lastSuccess = now
        } else {
            changed(at: now)
            retryAfter = now + 900
        }
    }
}

/// FSEvents owns a retained state object; the callback never touches UI state.
nonisolated final class DevelopmentBackupMonitor {
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var schedule = DevelopmentBackupSchedule(now: ProcessInfo.processInfo.systemUptime)
        let root: String
        let exclusions: [String]

        init(root: String, exclusions: [String]) {
            self.root = root
            self.exclusions = exclusions
        }

        func receive(paths: [String], flags: UnsafePointer<FSEventStreamEventFlags>) {
            let recoveryFlags = FSEventStreamEventFlags(
                kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped |
                kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagRootChanged |
                kFSEventStreamEventFlagEventIdsWrapped
            )
            let relevant = paths.enumerated().contains { index, path in
                flags[index] & recoveryFlags != 0 ||
                    DevelopmentBackupMonitor.affectsBackup(path: path, root: root, exclusions: exclusions)
            }
            if relevant {
                lock.withLock { schedule.changed(at: ProcessInfo.processInfo.systemUptime) }
            }
        }
    }

    private let state: State
    private let stream: FSEventStreamRef?

    init(root: URL, exclusions: [String]) {
        let state = State(root: root.standardizedFileURL.resolvingSymlinksInPath().path, exclusions: exclusions)
        self.state = state
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(state).toOpaque(),
            retain: { info in
                guard let info else { return nil }
                return UnsafeRawPointer(Unmanaged<State>.fromOpaque(info).retain().toOpaque())
            },
            release: { info in
                if let info { Unmanaged<State>.fromOpaque(info).release() }
            },
            copyDescription: nil
        )
        let stream = FSEventStreamCreate(
            nil,
            { _, info, count, rawPaths, flags, _ in
                guard let info else { return }
                let paths = Unmanaged<CFArray>.fromOpaque(rawPaths).takeUnretainedValue() as! [String]
                guard paths.count == count else { return }
                Unmanaged<State>.fromOpaque(info).takeUnretainedValue().receive(paths: paths, flags: flags)
            },
            &context, [state.root] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 5,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes |
                kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot)
        )
        if let stream {
            FSEventStreamSetDispatchQueue(stream, DispatchQueue(label: "ProjectPilot.backup-events", qos: .utility))
            if FSEventStreamStart(stream) {
                self.stream = stream
            } else {
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
                self.stream = nil
            }
        } else {
            self.stream = nil
        }
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    var hasPendingChanges: Bool { state.lock.withLock { state.schedule.firstChange != nil } }
    var isWatching: Bool { stream != nil }

    func beginIfNeeded(force: Bool = false) -> Bool {
        state.lock.withLock {
            let now = ProcessInfo.processInfo.systemUptime
            guard force || state.schedule.shouldRun(at: now) else { return false }
            state.schedule.began(at: now)
            return true
        }
    }

    func finished(succeeded: Bool) {
        state.lock.withLock {
            state.schedule.finished(at: ProcessInfo.processInfo.systemUptime, succeeded: succeeded)
        }
    }

    static func affectsBackup(path: String, root: String, exclusions: [String]) -> Bool {
        guard path != root else { return true }
        guard path.hasPrefix(root + "/") else { return false }
        let components = path.dropFirst(root.count + 1).split(separator: "/").map(String.init)
        return !components.contains { component in
            exclusions.contains { pattern in
                let name = pattern.hasSuffix("/") ? String(pattern.dropLast()) : pattern
                return name.hasPrefix("*") ? component.hasSuffix(String(name.dropFirst())) : component == name
            }
        }
    }
}
