import Foundation
import SQLite3
import Testing
@testable import ProjectPilot

@Suite(.serialized)
struct CodexCloudBackupTests {
    @Test func selectsRecoveryDataWithoutCredentialsCachesOrGeneratedDependencies() {
        for path in ["AGENTS.md", "config.toml", "state_5.sqlite", "thread_history_1.sqlite", "memories_v2_1.sqlite",
                     "sessions/2026/rollout.jsonl", "skills/example/build/reference.md", "worktrees/example/App.swift"] {
            #expect(CodexCloudBackup.shouldInclude(path.components(separatedBy: "/"), isDirectory: false))
        }
        for path in ["auth.json", "logs_2.sqlite", "sqlite/logs_2.sqlite", "sqlite/state.sqlite3-journal", "state_5.sqlite-wal", "state_5.sqlite-shm", "plugins", "backups", "browser",
                     "worktrees/example/node_modules/code.js", "automations/example/.venv/file", "sqlite/state.db-wal"] {
            #expect(!CodexCloudBackup.shouldInclude(path.components(separatedBy: "/"), isDirectory: ["plugins", "backups", "browser"].contains(path)))
        }
    }

    @Test func passwordRequiresRecoveryAcknowledgmentAndMatchingLongInput() throws {
        let password = "Fixture-only-password-2026"
        try CodexBackupPassword.validate(password, confirmation: password, recoverySaved: true)
        #expect(throws: (any Error).self) { try CodexBackupPassword.validate(password, confirmation: password, recoverySaved: false) }
        #expect(throws: (any Error).self) { try CodexBackupPassword.validate(password, confirmation: "different", recoverySaved: true) }
        #expect(throws: (any Error).self) { try CodexBackupPassword.validate("short", confirmation: "short", recoverySaved: true) }
        #expect(throws: (any Error).self) { try CodexBackupPassword.validate(password + "\0", confirmation: password + "\0", recoverySaved: true) }
    }

    @Test func sqliteSnapshotIncludesCommittedWALAndRemainsIndependent() throws {
        let home = try fixtureHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let source = home.appendingPathComponent(".codex/state_5.sqlite")
        var database: OpaquePointer?
        #expect(sqlite3_open(source.path, &database) == SQLITE_OK)
        defer { sqlite3_close(database) }
        #expect(sqlite3_exec(database, "PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0; CREATE TABLE proof(value TEXT); INSERT INTO proof VALUES('from WAL');", nil, nil, nil) == SQLITE_OK)
        let copy = home.appendingPathComponent("snapshot.sqlite")
        try CodexCloudBackup.snapshotDatabase(from: source, to: copy)
        #expect(try value(in: copy) == "from WAL")
        #expect(sqlite3_exec(database, "UPDATE proof SET value='new live value';", nil, nil, nil) == SQLITE_OK)
        #expect(try value(in: copy) == "from WAL")
        #expect(try value(in: source) == "new live value")
    }

    @Test func stagesBothSkillLibrariesAndUnpublishedFilesWithoutFollowingSymlinks() throws {
        let home = try fixtureHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try write("settings", home, ".codex/config.toml")
        try write("fixture credential", home, ".codex/auth.json")
        try write("source", home, ".codex/worktrees/example/untracked.swift")
        try write("generated", home, ".codex/worktrees/example/node_modules/ignored.js")
        try write("reference", home, ".codex/skills/custom/build/.hidden")
        try write("agent", home, ".agents/skills/custom/SKILL.md")
        try write("outside", home, "outside/keep.txt")
        let link = home.appendingPathComponent(".codex/worktrees/example/link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: home.appendingPathComponent("outside"))
        let target = home.appendingPathComponent("stage")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let snapshot = try CodexCloudBackup.stage(home: home, destination: target, now: Date())
        #expect(snapshot.fileCount == 5)
        #expect(FileManager.default.fileExists(atPath: target.appendingPathComponent("CodexHome/config.toml").path))
        #expect(!FileManager.default.fileExists(atPath: target.appendingPathComponent("CodexHome/auth.json").path))
        #expect(!FileManager.default.fileExists(atPath: target.appendingPathComponent("CodexHome/worktrees/example/node_modules").path))
        #expect(try String(contentsOf: target.appendingPathComponent("AgentSkills/custom/SKILL.md"), encoding: .utf8) == "agent")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: target.appendingPathComponent("CodexHome/worktrees/example/link").path) == home.appendingPathComponent("outside").path)
        #expect(try String(contentsOf: home.appendingPathComponent("outside/keep.txt"), encoding: .utf8) == "outside")
    }

    @Test func sqliteSnapshotFinishesWhileAnotherConnectionContinuouslyWrites() throws {
        let home = try fixtureHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let source = home.appendingPathComponent(".codex/live.sqlite")
        var creator: OpaquePointer?
        #expect(sqlite3_open(source.path, &creator) == SQLITE_OK)
        #expect(sqlite3_exec(creator, "PRAGMA journal_mode=WAL; CREATE TABLE proof(value TEXT, padding BLOB); INSERT INTO proof VALUES('initial',zeroblob(16777216));", nil, nil, nil) == SQLITE_OK)
        sqlite3_close(creator)
        let state = WriterState()
        let ready = DispatchSemaphore(value: 0)
        let done = DispatchGroup()
        done.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            defer { done.leave() }
            var writer: OpaquePointer?
            guard sqlite3_open(source.path, &writer) == SQLITE_OK else { state.fail(); ready.signal(); return }
            defer { sqlite3_close(writer) }
            sqlite3_busy_timeout(writer, 1000)
            let deadline = ProcessInfo.processInfo.systemUptime + 10
            var generation = 0
            while !state.stopped, ProcessInfo.processInfo.systemUptime < deadline {
                generation += 1
                if sqlite3_exec(writer, "UPDATE proof SET value='\(generation)';", nil, nil, nil) != SQLITE_OK { state.fail() }
                ready.signal()
                sqlite3_sleep(1)
            }
        }
        defer { state.stop(); done.wait() }
        #expect(ready.wait(timeout: .now() + 3) == .success)
        let copy = home.appendingPathComponent("fixed-view.sqlite")
        try CodexCloudBackup.snapshotDatabase(from: source, to: copy, timeout: 5)
        #expect(try Int(value(in: copy)) != nil)
        #expect(!state.failed)
    }

    @Test func retentionOnlyRemovesOldOwnedSnapshots() throws {
        let folder = try fixtureHome()
        defer { try? FileManager.default.removeItem(at: folder) }
        var names: [String] = []
        for day in 1...5 {
            let name = "Codex-2026110\(day)T120000Z-\(UUID().uuidString).dmg"
            names.append(name)
            try Data("fixture".utf8).write(to: folder.appendingPathComponent(name))
        }
        try Data("keep".utf8).write(to: folder.appendingPathComponent("unrelated.dmg"))
        try CodexCloudBackup.prune(in: folder, keeping: Set([names[4], names[2]]))
        let remaining = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(remaining.filter(CodexCloudBackup.isSnapshotFilename).count == 2)
        #expect(remaining.contains(names[4]) && remaining.contains(names[2]))
        #expect(remaining.contains("unrelated.dmg"))
        #expect(CodexCloudBackup.needsSnapshot(receipt: nil, now: Date(), force: false))
        let receipt = CodexCloudBackup.Receipt(version: 1, filename: names[4], createdAt: Date(), sha256: "", fileCount: 0, databaseCount: 0)
        #expect(!CodexCloudBackup.needsSnapshot(receipt: receipt, now: receipt.createdAt.addingTimeInterval(60), force: false))
        #expect(CodexCloudBackup.needsSnapshot(receipt: receipt, now: receipt.createdAt, force: true))
    }

    @Test func refusesCloudDestinationRedirectBeforeCopyingAnything() throws {
        let home = try fixtureHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let cloud = CodexCloudBackup.cloudFolder(home: home)
        try FileManager.default.createDirectory(at: cloud.deletingLastPathComponent(), withIntermediateDirectories: true)
        let outside = home.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: cloud, withDestinationURL: outside)
        #expect(throws: (any Error).self) { try CodexCloudBackup.createAndCopy(home: home, password: "Fixture-only-password-2026", force: true) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }

    @Test func encryptedImageCanBeRestoredAndFailurePreservesLastGoodCopy() throws {
        let home = try fixtureHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try write("fixture settings", home, ".codex/config.toml")
        try write("fixture session", home, ".codex/sessions/one.jsonl")
        try write("must not enter archive", home, ".codex/auth.json")
        let password = "Fixture-only-password-2026"
        let receipt = try CodexCloudBackup.createAndCopy(home: home, password: password, force: true)
        let cloud = CodexCloudBackup.cloudFolder(home: home)
        let image = cloud.appendingPathComponent(receipt.filename)
        #expect(try CodexCloudBackup.sha256(image) == receipt.sha256)
        #expect(try CodexCloudBackup.latestReceipt(in: cloud) == receipt)
        #expect(throws: (any Error).self) { try CodexCloudBackup.verifyImage(image, password: "wrong fixture password") }
        let mount = home.appendingPathComponent("Mounted")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        _ = try ProjectPilotViewModel.runProcess(["/usr/bin/hdiutil", "attach", image.path, "-readonly", "-nobrowse", "-mountpoint", mount.path, "-stdinpass"], timeoutSeconds: 60, standardInput: Data(password.utf8) + Data([0]))
        defer { _ = try? ProjectPilotViewModel.runProcess(["/usr/bin/hdiutil", "detach", mount.path], timeoutSeconds: 30) }
        #expect(try String(contentsOf: mount.appendingPathComponent("CodexHome/config.toml"), encoding: .utf8) == "fixture settings")
        #expect(!FileManager.default.fileExists(atPath: mount.appendingPathComponent("CodexHome/auth.json").path))
        #expect(FileManager.default.fileExists(atPath: mount.appendingPathComponent("RESTORE.md").path))
        // A bad live database must not replace the last successfully copied snapshot.
        try write("invalid SQLite", home, ".codex/state_5.sqlite")
        #expect(throws: (any Error).self) { try CodexCloudBackup.createAndCopy(home: home, password: password, force: true) }
        #expect(try CodexCloudBackup.latestReceipt(in: cloud) == receipt)
        #expect(try CodexCloudBackup.sha256(image) == receipt.sha256)
        #expect(try FileManager.default.contentsOfDirectory(atPath: home.appendingPathComponent("Library/Application Support/ProjectPilot/CodexBackupStaging").path) == ["backup.lock"])
        for path in ["Development/CodexBackups", "Library/Mobile Documents/com~apple~CloudDocs/Development/CodexBackups"] {
            let names = try FileManager.default.contentsOfDirectory(atPath: home.appendingPathComponent(path).path)
            #expect(names.allSatisfy { CodexCloudBackup.isSnapshotFilename($0) || ["Latest.json", "Chain.json", "RESTORE.md"].contains($0) })
        }
    }

    @Test func laterBackupsContainOnlyChangesAndDeletionMetadata() throws {
        let home = try fixtureHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try write("initial settings", home, ".codex/config.toml")
        try write("unchanged history", home, ".codex/sessions/large-history.jsonl")
        let password = "Fixture-only-password-2026"
        let first = try CodexCloudBackup.createAndCopy(home: home, password: password, force: true,
                                                       now: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(first.mode == "full")
        let unchanged = try CodexCloudBackup.createAndCopy(home: home, password: password, force: true,
                                                           now: Date(timeIntervalSince1970: 1_800_001_800))
        #expect(unchanged == first)
        #expect(try FileManager.default.contentsOfDirectory(at: CodexCloudBackup.localFolder(home: home),
                                                            includingPropertiesForKeys: nil)
            .filter { CodexCloudBackup.isSnapshotFilename($0.lastPathComponent) }.count == 1)

        try write("changed settings", home, ".codex/config.toml")
        let second = try CodexCloudBackup.createAndCopy(home: home, password: password, force: true,
                                                        now: Date(timeIntervalSince1970: 1_800_003_600))
        #expect(second.mode == "delta")
        #expect(second.baseFilename == first.filename)
        #expect(second.previousFilename == first.filename)
        let cloud = CodexCloudBackup.cloudFolder(home: home)
        let mount = home.appendingPathComponent("DeltaMount")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        _ = try ProjectPilotViewModel.runProcess(["/usr/bin/hdiutil", "attach", cloud.appendingPathComponent(second.filename).path,
                                                   "-readonly", "-nobrowse", "-mountpoint", mount.path, "-stdinpass"],
                                                  timeoutSeconds: 60, standardInput: Data(password.utf8) + Data([0]))
        #expect(try String(contentsOf: mount.appendingPathComponent("CodexHome/config.toml"), encoding: .utf8) == "changed settings")
        #expect(!FileManager.default.fileExists(atPath: mount.appendingPathComponent("CodexHome/sessions/large-history.jsonl").path))
        let metadata = try JSONDecoder().decode(CodexCloudBackup.DeltaMetadata.self,
                                                from: Data(contentsOf: mount.appendingPathComponent("Delta.json")))
        #expect(metadata.changedPaths == ["CodexHome/config.toml"])
        #expect(metadata.deletedPaths.isEmpty)
        _ = try ProjectPilotViewModel.runProcess(["/usr/bin/hdiutil", "detach", mount.path], timeoutSeconds: 30)

        try FileManager.default.removeItem(at: home.appendingPathComponent(".codex/config.toml"))
        let third = try CodexCloudBackup.createAndCopy(home: home, password: password, force: true,
                                                       now: Date(timeIntervalSince1970: 1_800_007_200))
        #expect(third.mode == "delta")
        _ = try ProjectPilotViewModel.runProcess(["/usr/bin/hdiutil", "attach", cloud.appendingPathComponent(third.filename).path,
                                                   "-readonly", "-nobrowse", "-mountpoint", mount.path, "-stdinpass"],
                                                  timeoutSeconds: 60, standardInput: Data(password.utf8) + Data([0]))
        let deletion = try JSONDecoder().decode(CodexCloudBackup.DeltaMetadata.self,
                                                from: Data(contentsOf: mount.appendingPathComponent("Delta.json")))
        #expect(deletion.changedPaths.isEmpty)
        #expect(deletion.deletedPaths == ["CodexHome/config.toml"])
        _ = try ProjectPilotViewModel.runProcess(["/usr/bin/hdiutil", "detach", mount.path], timeoutSeconds: 30)
        let chain = try JSONDecoder().decode(CodexCloudBackup.ChainIndex.self,
                                             from: Data(contentsOf: cloud.appendingPathComponent("Chain.json")))
        #expect(chain.artifacts == [first.filename, second.filename, third.filename])
    }

    @Test func legacyFullSnapshotsMigrateWithoutCreatingAnotherFullImage() throws {
        let home = try fixtureHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try write("baseline", home, ".codex/config.toml")
        let password = "Fixture-only-password-2026"
        let baseline = try CodexCloudBackup.createAndCopy(home: home, password: password, force: true)
        let legacy = CodexCloudBackup.Receipt(version: 1, filename: baseline.filename,
                                              createdAt: baseline.createdAt, sha256: baseline.sha256,
                                              fileCount: baseline.fileCount, databaseCount: baseline.databaseCount)
        let local = CodexCloudBackup.localFolder(home: home)
        let cloud = CodexCloudBackup.cloudFolder(home: home)
        for folder in [local, cloud] {
            try JSONEncoder().encode(legacy).write(to: folder.appendingPathComponent("Latest.json"), options: .atomic)
            try Data("obsolete".utf8).write(to: folder.appendingPathComponent("Codex-20260101T000000Z-\(UUID().uuidString).dmg"))
        }
        try FileManager.default.removeItem(at: CodexCloudBackup.stateURL(home: home))
        try write("changed after baseline", home, ".codex/config.toml")
        let migrated = try CodexCloudBackup.createAndCopy(home: home, password: password, force: true,
                                                          now: baseline.createdAt.addingTimeInterval(3_600))
        #expect(migrated.mode == "delta")
        let chain = try JSONDecoder().decode(CodexCloudBackup.ChainIndex.self,
                                             from: Data(contentsOf: cloud.appendingPathComponent("Chain.json")))
        #expect(chain.artifacts == [baseline.filename, migrated.filename])
        for folder in [local, cloud] {
            let images = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                .filter { CodexCloudBackup.isSnapshotFilename($0.lastPathComponent) }
                .map(\.lastPathComponent).sorted()
            #expect(images.sorted() == chain.artifacts.sorted())
        }
    }

    @Test func privateProcessInputDoesNotNeedCommandLineArguments() throws {
        #expect(try ProjectPilotViewModel.runProcess(["/bin/cat"], timeoutSeconds: 5, standardInput: Data("fixture input".utf8)) == "fixture input")
    }

    @Test func healthReportsUnconfiguredStaleAndFailedCodexBackups() {
        let now = Date()
        #expect(SystemHealthChecker.codexBackupWarning(configured: false, lastCopiedAt: nil, error: nil, now: now) != nil)
        #expect(SystemHealthChecker.codexBackupWarning(configured: true, lastCopiedAt: now, error: nil, now: now) == nil)
        #expect(SystemHealthChecker.codexBackupWarning(configured: true, lastCopiedAt: now.addingTimeInterval(-90000), error: nil, now: now) != nil)
        #expect(SystemHealthChecker.codexBackupWarning(configured: true, lastCopiedAt: now, error: "failed", now: now)?.detail == "failed")
    }

    private func fixtureHome() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PPCodexBackup-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".codex"), withIntermediateDirectories: true)
        return root
    }

    /// Test-only shared flags; every read/write is protected by the same lock.
    private final class WriterState: @unchecked Sendable {
        private let lock = NSLock()
        private var shouldStop = false
        private var didFail = false
        var stopped: Bool { lock.withLock { shouldStop } }
        var failed: Bool { lock.withLock { didFail } }
        func stop() { lock.withLock { shouldStop = true } }
        func fail() { lock.withLock { didFail = true } }
    }

    private func write(_ text: String, _ root: URL, _ relative: String) throws {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func value(in url: URL) throws -> String {
        var database: OpaquePointer?, statement: OpaquePointer?
        defer { sqlite3_finalize(statement); sqlite3_close(database) }
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              sqlite3_prepare_v2(database, "SELECT value FROM proof", -1, &statement, nil) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW, let value = sqlite3_column_text(statement, 0) else {
            throw CodexCloudBackup.Failure("Fixture database query failed")
        }
        return String(cString: value)
    }
}
