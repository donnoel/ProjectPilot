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
        var mode: String? = nil
        var chainID: String? = nil
        var sequence: Int? = nil
        var baseFilename: String? = nil
        var previousFilename: String? = nil
        var encryptedBytes: Int64? = nil
        var restoreVerifiedAt: Date? = nil
    }

    struct Snapshot: Codable, Sendable {
        let version: Int
        let startedAt: Date
        var fileCount = 0
        var databaseCount = 0
    }

    struct RecoveryEntry: Codable, Equatable, Sendable {
        let kind: String
        let digestOrTarget: String
    }

    struct RecoveryIndex: Codable, Sendable {
        let version: Int
        let kits: [Receipt]
    }

    static let folderName = "CodexBackups"
    static let interval: TimeInterval = 24 * 60 * 60
    static let maximumSourceBytes: Int64 = 1024 * 1024 * 1024
    static let maximumImageBytes: Int64 = 512 * 1024 * 1024
    static let maximumStoredBytes: Int64 = 2 * 1024 * 1024 * 1024
    static let directories: Set<String> = ["memories", "memories_v2", "automations", "rules", "skills", "worktrees"]
    static let files: Set<String> = ["AGENTS.md", "AGENTS.override.md", "config.toml", ".codex-global-state.json"]

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
        guard [1, 2, 3].contains(value.version), isSnapshotFilename(value.filename), value.sha256.count == 64 else {
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
            return files.contains(first) || (first.hasPrefix("memories_") && first.hasSuffix(".sqlite"))
        }
        guard directories.contains(first), let name = parts.last else { return false }
        if first == "automations" { return isDirectory ? parts.count <= 2 : parts.count == 3 && name == "automation.toml" }
        if ["wal", "shm", "journal"].contains(where: { name.hasSuffix("-" + $0) }) || name.hasSuffix(".lock") || name == ".DS_Store" { return false }
        if first == "worktrees" {
            let generated: Set<String> = ["node_modules", ".venv", ".build", "DerivedData", "Build", "build", "dist", ".next", ".cache", "cdk.out"]
            if parts.dropFirst().contains(where: generated.contains) { return false }
            if isDirectory && name == ".git" { return false }
        }
        return true
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
        for old in try fm.contentsOfDirectory(at: stagingParent, includingPropertiesForKeys: nil) where UUID(uuidString: old.lastPathComponent) != nil {
            try rejectRedirectedDestination(old)
            try fm.removeItem(at: old)
        }
        for folder in [home.appendingPathComponent("Development"), local, cloud.deletingLastPathComponent(), cloud] {
            try rejectRedirectedDestination(folder)
        }
        try fm.createDirectory(at: local, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.createDirectory(at: cloud, withIntermediateDirectories: true)
        let previous = try latestReceipt(in: local)
        if let previous, previous.version == 3, !needsSnapshot(receipt: previous, now: now, force: force) {
            guard fm.fileExists(atPath: local.appendingPathComponent(previous.filename).path),
                  fm.fileExists(atPath: cloud.appendingPathComponent(previous.filename).path) else {
                throw Failure("A recovery kit copy is missing. Choose Back up Codex now to replace it.")
            }
            return previous
        }
        let staging = try makeStagingDirectory(home: home)
        defer { try? fm.removeItem(at: staging) }
        let payload = staging.appendingPathComponent("Recovery", isDirectory: true)
        try fm.createDirectory(at: payload, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let snapshot = try stage(home: home, destination: payload, now: now)
        let manifest = try recoveryManifest(at: payload)
        try JSONEncoder().encode(manifest).write(to: payload.appendingPathComponent("RecoveryManifest.json"), options: .atomic)
        try JSONEncoder().encode(snapshot).write(to: payload.appendingPathComponent("Snapshot.json"), options: .atomic)
        try Data(restoreInstructions.utf8).write(to: payload.appendingPathComponent("RESTORE.md"), options: .atomic)
        let stored = try encrypt(payload: payload, staging: staging, local: local, password: password, now: now)
        let source = local.appendingPathComponent(stored.filename)
        let destination = cloud.appendingPathComponent(stored.filename)
        var published = false
        defer {
            if !published {
                try? fm.removeItem(at: source)
                try? fm.removeItem(at: destination)
            }
        }
        let bytes = Int64(try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        guard bytes <= maximumImageBytes else { throw Failure("The encrypted recovery kit exceeded 512 MiB. Existing backups were preserved; review its source files.") }
        let partial = cloud.appendingPathComponent(".\(UUID().uuidString).dmg.partial")
        defer { try? fm.removeItem(at: partial) }
        try fm.copyItem(at: source, to: partial)
        guard try sha256(partial) == stored.digest else { throw Failure("The encrypted cloud-folder copy failed verification. Existing backups were preserved.") }
        try fm.moveItem(at: partial, to: destination)
        // A successful checksum alone is insufficient: unlock the cloud copy and rehearse a full restore.
        try verifyRecoveryKit(destination, password: password, expected: manifest, staging: staging)
        let receipt = Receipt(version: 3, filename: stored.filename, createdAt: now, sha256: stored.digest,
                              fileCount: snapshot.fileCount, databaseCount: snapshot.databaseCount,
                              mode: "recovery-kit", encryptedBytes: bytes, restoreVerifiedAt: Date())
        let oldIndex = try recoveryIndex(in: local)
        let retained = retainedKits(oldIndex.kits + [receipt])
        let index = RecoveryIndex(version: 3, kits: retained)
        // Publish both verified receipts before retiring any previous image or legacy chain.
        for folder in [local, cloud] {
            for name in ["RecoveryKits.json", "Latest.json", "RESTORE.md"] { try rejectRedirectedDestination(folder.appendingPathComponent(name)) }
            try JSONEncoder().encode(index).write(to: folder.appendingPathComponent("RecoveryKits.json"), options: .atomic)
            try JSONEncoder().encode(receipt).write(to: folder.appendingPathComponent("Latest.json"), options: .atomic)
            try Data(restoreInstructions.utf8).write(to: folder.appendingPathComponent("RESTORE.md"), options: .atomic)
        }
        published = true
        for folder in [local, cloud] {
            try prune(in: folder, keeping: Set(retained.map(\.filename)))
            let oldChain = folder.appendingPathComponent("Chain.json")
            if fm.fileExists(atPath: oldChain.path) { try rejectRedirectedDestination(oldChain); try fm.removeItem(at: oldChain) }
        }
        let oldState = home.appendingPathComponent("Library/Application Support/ProjectPilot/CodexBackupState.json")
        if fm.fileExists(atPath: oldState.path) { try rejectRedirectedDestination(oldState); try fm.removeItem(at: oldState) }
        return receipt
    }

    static func recoveryIndex(in folder: URL) throws -> RecoveryIndex {
        let url = folder.appendingPathComponent("RecoveryKits.json")
        try rejectRedirectedDestination(url)
        guard FileManager.default.fileExists(atPath: url.path) else { return RecoveryIndex(version: 3, kits: []) }
        let index = try JSONDecoder().decode(RecoveryIndex.self, from: Data(contentsOf: url))
        guard index.version == 3, index.kits.allSatisfy({ $0.version == 3 && isSnapshotFilename($0.filename) && $0.sha256.count == 64 && $0.restoreVerifiedAt != nil && ($0.encryptedBytes ?? 0) > 0 }) else {
            throw Failure("The recovery kit index is invalid. Existing backups were preserved.")
        }
        return index
    }

    static func retainedKits(_ kits: [Receipt], budget: Int64 = maximumStoredBytes) -> [Receipt] {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var days = Set<Date>(), weeks = Set<Date>(), retained: [Receipt] = []
        var total: Int64 = 0
        for kit in kits.sorted(by: { $0.createdAt > $1.createdAt }) {
            let day = calendar.startOfDay(for: kit.createdAt)
            let week = calendar.dateInterval(of: .weekOfYear, for: kit.createdAt)!.start
            guard !days.contains(day) else { continue }
            let daily = days.count < 7
            guard daily || (weeks.count < 2 && !weeks.contains(week)) else { continue }
            let bytes = kit.encryptedBytes ?? maximumImageBytes
            guard retained.isEmpty || total + bytes <= budget else { continue }
            retained.append(kit); total += bytes; days.insert(day)
            if !daily { weeks.insert(week) }
        }
        return retained
    }

    static func recoveryManifest(at root: URL) throws -> [String: RecoveryEntry] {
        let fm = FileManager.default
        var result: [String: RecoveryEntry] = [:]
        func collect(_ url: URL, relative: String) throws {
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey])
            if values.isSymbolicLink == true {
                result[relative] = RecoveryEntry(kind: "symlink", digestOrTarget: try fm.destinationOfSymbolicLink(atPath: url.path))
            } else if values.isDirectory == true {
                result[relative] = RecoveryEntry(kind: "directory", digestOrTarget: "")
                for child in try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
                    try collect(child, relative: relative + "/" + child.lastPathComponent)
                }
            } else if values.isRegularFile == true {
                result[relative] = RecoveryEntry(kind: "file", digestOrTarget: try sha256(url))
            } else { throw Failure("An unsupported file entered recovery staging.") }
        }
        for name in ["CodexHome", "AgentSkills"] {
            let url = root.appendingPathComponent(name)
            if fm.fileExists(atPath: url.path) { try collect(url, relative: name) }
        }
        return result
    }

    static func verifyRecoveryKit(_ image: URL, password: String, expected: [String: RecoveryEntry], staging: URL) throws {
        let fm = FileManager.default
        let mount = staging.appendingPathComponent("Mounted", isDirectory: true)
        let restored = staging.appendingPathComponent("RestoreCheck", isDirectory: true)
        try fm.createDirectory(at: mount, withIntermediateDirectories: false)
        try fm.createDirectory(at: restored, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        _ = try ProjectPilotViewModel.runProcess(["/usr/bin/hdiutil", "attach", image.path, "-readonly", "-nobrowse", "-mountpoint", mount.path, "-stdinpass"], timeoutSeconds: 120, standardInput: Data(password.utf8) + Data([0]))
        do {
            let stored = try JSONDecoder().decode([String: RecoveryEntry].self, from: Data(contentsOf: mount.appendingPathComponent("RecoveryManifest.json")))
            guard stored == expected else { throw Failure("The recovery manifest did not match the staged files. Old backups were preserved.") }
            for name in ["CodexHome", "AgentSkills"] where fm.fileExists(atPath: mount.appendingPathComponent(name).path) {
                try fm.copyItem(at: mount.appendingPathComponent(name), to: restored.appendingPathComponent(name))
            }
            guard try recoveryManifest(at: restored) == expected else { throw Failure("The decrypted restore check did not match. Old backups were preserved.") }
        } catch {
            _ = try? ProjectPilotViewModel.runProcess(["/usr/bin/hdiutil", "detach", mount.path], timeoutSeconds: 60)
            throw error
        }
        _ = try ProjectPilotViewModel.runProcess(["/usr/bin/hdiutil", "detach", mount.path], timeoutSeconds: 60)
    }

    private static func makeStagingDirectory(home: URL) throws -> URL {
        let fm = FileManager.default
        let parent = home.appendingPathComponent("Library/Application Support/ProjectPilot/CodexBackupStaging", isDirectory: true)
        try rejectRedirectedDestination(parent)
        try fm.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let staging = parent.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return staging
    }

    private static func encrypt(payload: URL, staging: URL, local: URL, password: String,
                                now: Date) throws -> (filename: String, digest: String) {
        let fm = FileManager.default
        let image = staging.appendingPathComponent("Encrypted.dmg")
        _ = try ProjectPilotViewModel.runProcess([
            "/usr/bin/hdiutil", "create", "-srcfolder", payload.path, "-volname", "Codex Recovery",
            "-format", "ULFO", "-encryption", "AES-256", "-stdinpass", image.path
        ], timeoutSeconds: 1800, standardInput: Data(password.utf8) + Data([0]))
        try verifyImage(image, password: password)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let filename = "Codex-\(formatter.string(from: now))-\(UUID().uuidString).dmg"
        let digest = try sha256(image)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: image.path)
        try fm.moveItem(at: image, to: local.appendingPathComponent(filename))
        return (filename, digest)
    }

    static func verifyImage(_ image: URL, password: String) throws {
        let output = try ProjectPilotViewModel.runProcess(["/usr/bin/hdiutil", "isencrypted", image.path, "-plist"], timeoutSeconds: 30)
        let plist = try PropertyListSerialization.propertyList(from: Data(output.utf8), format: nil) as? [String: Any]
        guard plist?["encrypted"] as? Bool == true else { throw Failure("The Codex disk image is not encrypted. It was not published.") }
        _ = try ProjectPilotViewModel.runProcess(["/usr/bin/hdiutil", "verify", "-stdinpass", image.path],
                                                 timeoutSeconds: 600, standardInput: Data(password.utf8) + Data([0]))
    }

    static func stage(home: URL, destination: URL, now: Date, maximumBytes: Int64 = maximumSourceBytes) throws -> Snapshot {
        let fm = FileManager.default, source = home.appendingPathComponent(".codex", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: source.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw Failure("The Codex data folder was not found. Previous encrypted snapshots were preserved.")
        }
        guard source.resolvingSymlinksInPath() == source.standardizedFileURL else {
            throw Failure("The Codex source is a symbolic link. Review its backup location before continuing.")
        }
        var snapshot = Snapshot(version: 3, startedAt: now)
        var sourceBytes: Int64 = 0
        let target = destination.appendingPathComponent("CodexHome", isDirectory: true)
        try fm.createDirectory(at: target, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        func copy(_ from: URL, _ to: URL, parts: [String], filtering: Bool) throws {
            let values = try from.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
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
                sourceBytes += Int64(values.fileSize ?? 0)
                guard sourceBytes <= maximumBytes else { throw Failure("Recovery essentials exceeded the 1 GiB source budget. Existing backups were preserved; review large worktree or skill files.") }
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
        let stagedBytes = try FileManager.default.subpathsOfDirectory(atPath: destination.path).reduce(Int64(0)) { total, path in
            let values = try destination.appendingPathComponent(path).resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            return total + (values.isRegularFile == true && values.isSymbolicLink != true ? Int64(values.fileSize ?? 0) : 0)
        }
        guard stagedBytes <= maximumBytes else { throw Failure("The staged recovery kit exceeded its size budget. Existing backups were preserved.") }
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

    static func prune(in folder: URL, keeping retained: Set<String>) throws {
        let fm = FileManager.default
        let snapshots = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { isSnapshotFilename($0.lastPathComponent) && !retained.contains($0.lastPathComponent) }
        for old in snapshots { try fm.removeItem(at: old) }
    }

    static func rejectRedirectedDestination(_ url: URL) throws {
        guard url.standardizedFileURL.path == url.resolvingSymlinksInPath().path else {
            throw Failure("A Codex backup destination is a symbolic link. Existing data was not touched.")
        }
    }

    static let restoreInstructions = """
    # Restore the small encrypted Codex recovery kit

    Each version-3 recovery kit is independent. No baseline or delta chain is needed.
    1. Download one Codex-*.dmg listed in RecoveryKits.json from iCloud Drive >
       Development > CodexBackups. Keep an untouched copy and your separately saved
       recovery password. ProjectPilot cannot recover a forgotten password.
    2. Open the image with that password. Copy CodexHome and AgentSkills into a
       separate recovery folder. Do not change the mounted image or live Codex data.
    3. Install Codex, quit it and all CLI/background sessions, and preserve its fresh
       data separately. Recover the selected CodexHome files under ~/.codex and
       AgentSkills under ~/.agents/skills. Review config paths and automation
       schedules before enabling them. Sign in again and reinstall plug-ins.
    4. Restore Development repositories using their normal backups/Git. Recover
       unpublished files from CodexHome/worktrees into those repositories before
       deliberately reconnecting worktrees. Old .git pointers may have stale paths.
       Symlinks are saved as links; their external targets need separate recovery.
    5. Check instructions, skills, memories, automation definitions and recovered
       source files. This kit does NOT restore full conversations, transcript or
       history databases, attachments, generated images, dictation or caches.

    Scope: global instructions, config, local project preferences, rules, both skill
    libraries, memories and memory databases, automation.toml definitions, and
    non-generated worktree source, including unpublished files. No auth.json,
    browser sign-ins, logs, downloaded plug-ins, generated dependencies or builds.
    Application secrets outside these roots and the OS Keychain need their own plan.

    AES-256 encryption is required. Passwords never enter these files or command
    arguments. SQLite uses a consistent read-only snapshot and quick_check.
    Every kit is unlocked from the cloud-folder copy, restored to private temporary
    storage and compared with its encrypted SHA-256 manifest before publication
    or removal of older images. Nothing is restored into the live Codex folder.

    Daily automatic backups retain up to seven daily and two older weekly copies,
    limited to 2 GiB per destination; newest copies take priority. A kit exceeding
    1 GiB of source files or a 512 MiB encrypted image fails visibly without
    discarding the previous recovery copy. Old baseline/delta chains are retired
    only after the first recovery kit passes the full restore check and publication.
    A verified local iCloud folder copy does NOT prove server upload completed.
    Before erasing this Mac, download and unlock the kit from another device.
    """
}
