import CryptoKit
import Darwin
import Foundation
import SQLite3

/// Encrypted, versioned recovery copies. Nothing in this service restores into live Codex.
nonisolated enum CodexCloudBackup {
    struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    struct Receipt: Codable, Equatable, Sendable {
        let version: Int
        let filename: String
        let createdAt: Date
        let sha256: String
        let fileCount: Int
        let databaseCount: Int
    }

    struct Snapshot: Codable, Sendable {
        let version: Int
        let startedAt: Date
        var fileCount = 0
        var databaseCount = 0
    }

    static let folderName = "CodexBackups"
    static let interval: TimeInterval = 60 * 60
    static let retainedSnapshots = 3
    static let directories: Set<String> = [
        "sessions", "archived_sessions", "memories", "memories_v2", "automations",
        "rules", "skills", "attachments", "generated_images", "visualizations",
        "worktrees", "sqlite", "state", "dictation-history"
    ]
    static let files: Set<String> = ["AGENTS.md", "config.toml", ".codex-global-state.json", "session_index.jsonl", "history.jsonl"]

    static func localFolder(home: URL) -> URL {
        home.appendingPathComponent("Development/\(folderName)", isDirectory: true)
    }

    static func cloudFolder(home: URL) -> URL {
        home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Development/\(folderName)", isDirectory: true)
    }

    static func latestReceipt(in folder: URL) throws -> Receipt? {
        let url = folder.appendingPathComponent("Latest.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let value = try JSONDecoder().decode(Receipt.self, from: Data(contentsOf: url))
        guard value.version == 1, isSnapshotFilename(value.filename), value.sha256.count == 64 else {
            throw Failure("The Codex backup receipt is invalid; existing snapshots were preserved.")
        }
        return value
    }

    static func needsSnapshot(receipt: Receipt?, now: Date, force: Bool) -> Bool {
        force || receipt == nil || now.timeIntervalSince(receipt!.createdAt) >= interval
    }

    static func shouldInclude(_ parts: [String], isDirectory: Bool) -> Bool {
        guard let first = parts.first else { return false }
        if parts.count == 1 {
            if isDirectory { return directories.contains(first) }
            return files.contains(first) || (["sqlite", "sqlite3", "db"].contains((first as NSString).pathExtension) && !first.hasPrefix("logs_"))
        }
        guard directories.contains(first) else { return false }
        if let name = parts.last {
            if ["sqlite", "sqlite3", "db"].contains(where: { ext in
                ["wal", "shm", "journal"].contains { name.hasSuffix(".\(ext)-\($0)") }
            }) { return false }
            if first == "sqlite", name.hasPrefix("logs_") { return false }
        }
        if first == "worktrees" || first == "automations" {
            let generated: Set<String> = ["node_modules", ".venv", ".build", "DerivedData", "Build", "build", "dist", ".next", ".cache", "cdk.out"]
            if parts.dropFirst().contains(where: generated.contains) { return false }
            if isDirectory && parts.last == ".git" { return false }
        }
        return !(parts.last?.hasSuffix(".lock") ?? false)
    }

    static func createAndCopy(home: URL, password: String, force: Bool, now: Date = Date()) throws -> Receipt {
        let fm = FileManager.default
        let home = home.standardizedFileURL.resolvingSymlinksInPath()
        let local = localFolder(home: home), cloud = cloudFolder(home: home)
        let stagingParent = home.appendingPathComponent("Library/Application Support/ProjectPilot/CodexBackupStaging", isDirectory: true)
        try rejectRedirectedDestination(stagingParent)
        try fm.createDirectory(at: stagingParent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let descriptor = open(stagingParent.appendingPathComponent("backup.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw Failure("The private Codex backup lock could not be opened.") }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw Failure("Another ProjectPilot process is backing up Codex. Wait for it to finish.") }
        defer { flock(descriptor, LOCK_UN) }
        // A crashed process may leave private plaintext staging. Only this service's UUID folders are removed.
        for old in try fm.contentsOfDirectory(at: stagingParent, includingPropertiesForKeys: nil) where UUID(uuidString: old.lastPathComponent) != nil {
            try rejectRedirectedDestination(old)
            try fm.removeItem(at: old)
        }
        for folder in [home.appendingPathComponent("Development"), local,
                       cloud.deletingLastPathComponent(), cloud] { try rejectRedirectedDestination(folder) }
        try fm.createDirectory(at: local, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.createDirectory(at: cloud, withIntermediateDirectories: true)
        let previous = try latestReceipt(in: local)
        let receipt: Receipt
        if needsSnapshot(receipt: previous, now: now, force: force) {
            receipt = try create(home: home, local: local, password: password, now: now)
        } else if let previous, fm.fileExists(atPath: local.appendingPathComponent(previous.filename).path) {
            receipt = previous
        } else {
            throw Failure("The last encrypted Codex snapshot is missing. Use Back up Codex now to create a replacement.")
        }
        // Publish only ciphertext. A failed copy never rotates the last good archives.
        let source = local.appendingPathComponent(receipt.filename)
        let destination = cloud.appendingPathComponent(receipt.filename)
        try rejectRedirectedDestination(destination)
        if try !fm.fileExists(atPath: destination.path) || sha256(destination) != receipt.sha256 {
            let partial = cloud.appendingPathComponent(".\(UUID().uuidString).dmg.partial")
            defer { try? fm.removeItem(at: partial) }
            try fm.copyItem(at: source, to: partial)
            guard try sha256(partial) == receipt.sha256 else { throw Failure("The encrypted iCloud copy failed verification. Previous snapshots were preserved.") }
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.moveItem(at: partial, to: destination)
        }
        let data = try JSONEncoder().encode(receipt)
        for folder in [local, cloud] {
            for name in ["Latest.json", "RESTORE.md"] { try rejectRedirectedDestination(folder.appendingPathComponent(name)) }
        }
        try data.write(to: cloud.appendingPathComponent("Latest.json"), options: .atomic)
        try Data(restoreInstructions.utf8).write(to: cloud.appendingPathComponent("RESTORE.md"), options: .atomic)
        try data.write(to: local.appendingPathComponent("Latest.json"), options: .atomic)
        try Data(restoreInstructions.utf8).write(to: local.appendingPathComponent("RESTORE.md"), options: .atomic)
        try prune(in: local, keeping: receipt.filename)
        try prune(in: cloud, keeping: receipt.filename)
        return receipt
    }

    private static func create(home: URL, local: URL, password: String, now: Date) throws -> Receipt {
        let fm = FileManager.default
        let parent = home.appendingPathComponent("Library/Application Support/ProjectPilot/CodexBackupStaging", isDirectory: true)
        try rejectRedirectedDestination(parent)
        try fm.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let staging = parent.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: staging) }
        let payload = staging.appendingPathComponent("Recovery", isDirectory: true)
        try fm.createDirectory(at: payload, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let snapshot = try stage(home: home, destination: payload, now: now)
        try JSONEncoder().encode(snapshot).write(to: payload.appendingPathComponent("Snapshot.json"), options: .atomic)
        try Data(restoreInstructions.utf8).write(to: payload.appendingPathComponent("RESTORE.md"), options: .atomic)
        let image = staging.appendingPathComponent("Encrypted.dmg")
        let secretInput = Data(password.utf8) + Data([0])
        _ = try ProjectPilotViewModel.runProcess([
            "/usr/bin/hdiutil", "create", "-srcfolder", payload.path, "-volname", "Codex Recovery",
            "-format", "ULFO", "-encryption", "AES-256", "-stdinpass", image.path
        ], timeoutSeconds: 1800, standardInput: secretInput)
        try verifyImage(image, password: password)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let filename = "Codex-\(formatter.string(from: now))-\(UUID().uuidString).dmg"
        let digest = try sha256(image)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: image.path)
        try fm.moveItem(at: image, to: local.appendingPathComponent(filename))
        return Receipt(version: 1, filename: filename, createdAt: now, sha256: digest,
                       fileCount: snapshot.fileCount, databaseCount: snapshot.databaseCount)
    }

    static func verifyImage(_ image: URL, password: String) throws {
        let output = try ProjectPilotViewModel.runProcess(["/usr/bin/hdiutil", "isencrypted", image.path, "-plist"], timeoutSeconds: 30)
        let plist = try PropertyListSerialization.propertyList(from: Data(output.utf8), format: nil) as? [String: Any]
        guard plist?["encrypted"] as? Bool == true else { throw Failure("The Codex disk image is not encrypted. It was not published.") }
        _ = try ProjectPilotViewModel.runProcess(["/usr/bin/hdiutil", "verify", "-stdinpass", image.path],
                                                 timeoutSeconds: 600, standardInput: Data(password.utf8) + Data([0]))
    }

    static func stage(home: URL, destination: URL, now: Date) throws -> Snapshot {
        let fm = FileManager.default, source = home.appendingPathComponent(".codex", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: source.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw Failure("The Codex data folder was not found. Previous encrypted snapshots were preserved.")
        }
        guard source.resolvingSymlinksInPath() == source.standardizedFileURL else {
            throw Failure("The Codex source is a symbolic link. Review its backup location before continuing.")
        }
        var snapshot = Snapshot(version: 1, startedAt: now)
        let target = destination.appendingPathComponent("CodexHome", isDirectory: true)
        try fm.createDirectory(at: target, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        func copy(_ from: URL, _ to: URL, parts: [String], filtering: Bool) throws {
            let values = try from.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey])
            let directory = values.isDirectory == true && values.isSymbolicLink != true
            if values.isSymbolicLink == true, parts.count == 1, directories.contains(parts[0]) {
                throw Failure("A Codex data library is a symbolic link. Review its target before backing it up.")
            }
            if filtering && !shouldInclude(parts, isDirectory: directory) { return }
            if directory {
                try fm.createDirectory(at: to, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                for child in try fm.contentsOfDirectory(at: from, includingPropertiesForKeys: nil).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    try copy(child, to.appendingPathComponent(child.lastPathComponent), parts: parts + [child.lastPathComponent], filtering: filtering)
                }
            } else if values.isSymbolicLink == true {
                try fm.createSymbolicLink(atPath: to.path, withDestinationPath: fm.destinationOfSymbolicLink(atPath: from.path))
                snapshot.fileCount += 1
            } else if values.isRegularFile == true {
                if ["sqlite", "sqlite3"].contains(from.pathExtension) || from.pathExtension == "db" && isSQLite(from) {
                    try snapshotDatabase(from: from, to: to)
                    snapshot.databaseCount += 1
                } else if clonefile(from.path, to.path, 0) != 0 {
                    try fm.copyItem(at: from, to: to)
                }
                snapshot.fileCount += 1
            }
        }
        for child in try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
            try copy(child, target.appendingPathComponent(child.lastPathComponent), parts: [child.lastPathComponent], filtering: true)
        }
        let agentSkills = home.appendingPathComponent(".agents/skills", isDirectory: true)
        if fm.fileExists(atPath: agentSkills.path) {
            guard agentSkills.resolvingSymlinksInPath() == agentSkills.standardizedFileURL else {
                throw Failure("The agent skills source is a symbolic link. Review its target before backing it up.")
            }
            try copy(agentSkills, destination.appendingPathComponent("AgentSkills"), parts: [], filtering: false)
        }
        return snapshot
    }

    private static func isSQLite(_ url: URL) -> Bool {
        guard let file = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? file.close() }
        return (try? file.read(upToCount: 16)) == Data("SQLite format 3\0".utf8)
    }

    static func snapshotDatabase(from source: URL, to destination: URL, timeout: TimeInterval = 120) throws {
        var input: OpaquePointer?, output: OpaquePointer?
        defer { if let input { sqlite3_close(input) }; if let output { sqlite3_close(output) } }
        guard sqlite3_open_v2(source.path, &input, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              sqlite3_open_v2(destination.path, &output, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            throw Failure("A Codex database could not be opened for a consistent snapshot. Previous archives were preserved.")
        }
        // BEGIN is deferred: an actual read must establish the WAL view before backup_init.
        // Otherwise each live Codex write can restart the incremental copy indefinitely.
        guard sqlite3_exec(input, "BEGIN; SELECT name FROM sqlite_schema LIMIT 1;", nil, nil, nil) == SQLITE_OK,
              let backup = sqlite3_backup_init(output, "main", input, "main") else {
            throw Failure("A Codex database snapshot could not be started. Previous archives were preserved.")
        }
        defer { sqlite3_exec(input, "ROLLBACK", nil, nil, nil) }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var status = sqlite3_backup_step(backup, 512)
        while [SQLITE_OK, SQLITE_BUSY, SQLITE_LOCKED].contains(status), ProcessInfo.processInfo.systemUptime < deadline {
            sqlite3_sleep(10)
            status = sqlite3_backup_step(backup, 512)
        }
        let finished = sqlite3_backup_finish(backup)
        guard status == SQLITE_DONE, finished == SQLITE_OK else {
            let reason = ProcessInfo.processInfo.systemUptime >= deadline ? "exceeded its time budget" : "failed (SQLite status \(status))"
            throw Failure("The snapshot of \(source.lastPathComponent) \(reason). Previous archives were preserved; retry later.")
        }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(output, "PRAGMA quick_check", -1, &statement, nil) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW,
              let text = sqlite3_column_text(statement, 0), String(cString: text) == "ok" else {
            throw Failure("A Codex database snapshot failed its integrity check. No new archive was published.")
        }
    }

    static func sha256(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        while let data = try file.read(upToCount: 1024 * 1024), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func isSnapshotFilename(_ name: String) -> Bool {
        name.range(of: #"^Codex-[0-9]{8}T[0-9]{6}Z-[0-9A-Fa-f-]{36}\.dmg$"#, options: .regularExpression) != nil
    }

    static func prune(in folder: URL, keeping latest: String) throws {
        let fm = FileManager.default
        let snapshots = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { isSnapshotFilename($0.lastPathComponent) && $0.lastPathComponent != latest }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in snapshots.dropFirst(retainedSnapshots - 1) { try fm.removeItem(at: old) }
    }

    static func rejectRedirectedDestination(_ url: URL) throws {
        guard url.standardizedFileURL.path == url.resolvingSymlinksInPath().path else {
            throw Failure("A Codex backup destination is a symbolic link. Existing data was not touched.")
        }
    }

    static let restoreInstructions = """
    # Restore Codex from a ProjectPilot encrypted backup

    1. On the replacement Mac, download a complete Codex-*.dmg from iCloud Drive >
       Development > CodexBackups. Latest.json identifies the last copied snapshot.
       Keep another copy of the image before doing recovery work.
    2. Double-click the disk image in Finder. Enter the recovery password you saved
       separately in your password manager or other safe place. ProjectPilot cannot
       recover a forgotten password. The old Mac's local Keychain alone is not a
       recovery plan. The image contains no saved copy of its password.
    3. Install Codex but quit it and all Codex CLI/background sessions before
       restoring. Keep any fresh ~/.codex folder separately; do not merge databases
       into a running app or overwrite newer work.
    4. In Finder use Go > Go to Folder to open your home folder. Press Command-Shift-.
       to show hidden files. Copy CodexHome from the mounted image into your home
       folder, then rename that COPY to .codex. Do not change the mounted image.
    5. Copy AgentSkills (if present) into ~/.agents/skills, including hidden files.
       Restore your Development repositories too. Worktrees may contain absolute
       .git pointers: recover their changed files into restored repositories before
       recreating worktree links. Symlink targets must be restored separately.
    6. Reopen Codex, sign in again, and check familiar conversations, memories,
       settings, skills, and task definitions. Review automation schedules before
       enabling anything. Reinstall plugins. Restore outside-project credentials
       and other applications through their own approved recovery methods.
    7. In ProjectPilot > Backup, set up Codex backup with the SAME saved password.
       Keep this password outside these archives and outside Git repositories.

    Scope: config, global instructions, automations, rules, both skill libraries,
    sessions and archived sessions, memories, attachments, generated images,
    visualizations, local state databases, dictation history, and worktree files.
    Excluded: auth.json and browser sign-ins, logs/caches, downloaded plugins,
    old Codex backup folders, lock/socket files, database WAL/SHM sidecars, and
    generated build/dependency folders inside worktrees and automations.

    SQLite databases use the online backup API and pass quick_check. Their WAL data
    is included in each database snapshot. Separate files/databases are captured
    over a time window, not as one atomic whole-app snapshot. Pending cross-file
    activity at that time may require normal application recovery.

    Snapshots are encrypted with AES-256 before entering Development or iCloud.
    Backups run at most hourly automatically, or on Back up Codex now. The latest
    three snapshots are retained after a verified copy to the local iCloud folder.
    This is a rolling recovery window, not a permanent historical archive. A copied
    and verified local iCloud file does not prove Apple's servers finished upload.
    Check iCloud sync/download availability before erasing the original Mac.
    """
}
