import Foundation
import Testing
@testable import ProjectPilot

struct DevelopmentBackupEfficiencyTests {
    @Test func idleBackupDoesNotRunAgainUntilHourlySafetyCheck() {
        var schedule = DevelopmentBackupSchedule(now: 0)
        #expect(!schedule.shouldRun(at: 59))
        #expect(schedule.shouldRun(at: 60))
        schedule.began(at: 60)
        schedule.finished(at: 90, succeeded: true)
        #expect(!schedule.shouldRun(at: 150))
        #expect(!schedule.shouldRun(at: 3689))
        #expect(schedule.shouldRun(at: 3690))
    }

    @Test func editingBurstsAreBatchedWithoutStarvingContinuousEdits() {
        var schedule = DevelopmentBackupSchedule(now: 0)
        schedule.began(at: 60)
        schedule.finished(at: 90, succeeded: true)
        schedule.changed(at: 100)
        #expect(!schedule.shouldRun(at: 160)) // Minimum five minutes between starts.
        schedule.changed(at: 350)
        #expect(!schedule.shouldRun(at: 360)) // Still editing.
        #expect(schedule.shouldRun(at: 410))
        schedule.changed(at: 999)
        #expect(schedule.shouldRun(at: 1000)) // Fifteen minutes since first pending edit.
    }

    @Test func editsDuringCopySurviveCompletionAndFailuresBackOff() {
        var schedule = DevelopmentBackupSchedule(now: 0)
        schedule.began(at: 60)
        schedule.changed(at: 80)
        schedule.finished(at: 90, succeeded: true)
        #expect(schedule.firstChange == 80)
        #expect(schedule.shouldRun(at: 360))
        schedule.began(at: 360)
        schedule.finished(at: 400, succeeded: false)
        schedule.changed(at: 500)
        #expect(!schedule.shouldRun(at: 1299))
        #expect(schedule.shouldRun(at: 1300))
    }

    @Test func generatedFilesAreIgnoredButGitAndSourceChangesRemainProtected() {
        let exclusions = ["node_modules/", ".build/", "*.xcuserstate", ".DS_Store"]
        for relative in ["App/node_modules/pkg/index.js", "App/.build/debug/a", "App/User.xcuserstate", ".DS_Store"] {
            #expect(!DevelopmentBackupMonitor.affectsBackup(
                path: "/source/" + relative, root: "/source", exclusions: exclusions
            ))
        }
        for path in ["/source", "/source/App/File.swift", "/source/App/.git/objects/ab/123", "/source/App/Removed"] {
            #expect(DevelopmentBackupMonitor.affectsBackup(path: path, root: "/source", exclusions: exclusions))
        }
        #expect(!DevelopmentBackupMonitor.affectsBackup(path: "/source-other/a", root: "/source", exclusions: exclusions))
    }

    @Test func filesystemMonitorNoticesNestedSourceChanges() async throws {
        // Exercise the same user-volume event delivery as ~/Development, outside OS scratch storage.
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".PPMonitorTest-\(UUID().uuidString)")
        let nested = root.appendingPathComponent("App/Sources")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let monitor = DevelopmentBackupMonitor(root: root, exclusions: ["node_modules/"])
        #expect(monitor.isWatching)
        #expect(monitor.beginIfNeeded(force: true))
        monitor.finished(succeeded: true)
        #expect(!monitor.hasPendingChanges)
        try Data("change".utf8).write(to: nested.appendingPathComponent("Source.swift"))
        for _ in 0..<150 {
            if monitor.hasPendingChanges { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(monitor.hasPendingChanges)
    }

    @Test func processWaitReturnsOutputAndEnforcesTimeout() throws {
        #expect(try ProjectPilotViewModel.runProcess(["/bin/echo", "done"], timeoutSeconds: 2) == "done\n")
        #expect(throws: (any Error).self) {
            try ProjectPilotViewModel.runProcess(["/bin/sleep", "30"], timeoutSeconds: 0.1)
        }
    }
}
