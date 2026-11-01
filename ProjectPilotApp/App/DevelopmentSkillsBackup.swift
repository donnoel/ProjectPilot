import Foundation

/// Stage the two user-level skill libraries before the Development mirror runs.
nonisolated enum DevelopmentSkillsBackup {
    private struct BackupError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func sourceURLs(homeDirectoryURL: URL) -> [URL] {
        [".agents/skills", ".codex/skills"].map {
            homeDirectoryURL.appendingPathComponent($0, isDirectory: true)
        }
    }

    static func synchronize(
        homeDirectoryURL: URL,
        runProcess: ([String]) throws -> Void
    ) throws {
        let fm = FileManager.default
        let home = homeDirectoryURL.standardizedFileURL.resolvingSymlinksInPath()
        let development = home.appendingPathComponent("Development", isDirectory: true)
        let destination = development.appendingPathComponent("skills", isDirectory: true)
        let sources = sourceURLs(homeDirectoryURL: home)
        let copies = ["agents", "codex"].map { destination.appendingPathComponent($0, isDirectory: true) }

        // Validate every source first. A missing library must not erase its last backup.
        for source in sources {
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: source.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw BackupError(message: "Skills backup source not found: \(source.path). The iCloud mirror was not updated.")
            }
        }
        // Never follow a destination alias back into the live skills or another folder.
        for url in [development, destination] + copies {
            guard url.resolvingSymlinksInPath().path == url.path else {
                throw BackupError(message: "Skills backup destination must not be a symbolic link: \(url.path).")
            }
            var isDirectory: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue {
                throw BackupError(message: "Skills backup destination is not a folder: \(url.path).")
            }
        }

        for (source, copy) in zip(sources, copies) {
            try fm.createDirectory(at: copy, withIntermediateDirectories: true)
            // Check contents because skills are small, and leave unchanged copies untouched.
            try runProcess([
                "/usr/bin/rsync", "-rltp", "--checksum", "--delete", "--exclude=.DS_Store", "--",
                source.path + "/", copy.path + "/"
            ])
        }

        let instructions = Data(restoreInstructions.utf8)
        let readme = destination.appendingPathComponent("README.md")
        guard readme.resolvingSymlinksInPath().path == readme.path else {
            throw BackupError(message: "Skills restore instructions must not be a symbolic link.")
        }
        if (try? Data(contentsOf: readme)) != instructions {
            try instructions.write(to: readme, options: .atomic)
        }
    }

    static func cloudMirrorArguments(developmentURL: URL, backupURL: URL) -> [String] {
        // A small checksum pass also catches skill edits with unchanged sizes and dates,
        // without checksumming every repository in the larger Development mirror.
        [
            "/usr/bin/rsync", "-rltp", "--checksum", "--delete", "--",
            developmentURL.appendingPathComponent("skills").path + "/",
            backupURL.appendingPathComponent("skills").path + "/"
        ]
    }

    private static let restoreInstructions = """
    # Skills backup

    ProjectPilot refreshes these copies before its normal Development-to-iCloud backup:

    - `agents/` copies `~/.agents/skills/`.
    - `codex/` copies `~/.codex/skills/`, including `.system`.

    Edit the original hidden folders, not these managed copies. Removed source files
    are also removed from these copies and the iCloud mirror.

    To restore on a replacement Mac, download this entire folder from iCloud Drive,
    quit Codex, create `~/.agents/skills` and `~/.codex/skills`, and copy each library's
    contents (including hidden files) back to its matching original location. Restore
    your Development repositories too: some skills refer to canonical files there.
    Symbolic links are preserved; restore their targets as well.

    This contains skill files only, not Codex credentials, sessions, settings, or
    plugin caches. Reinstall plugins separately. A completed ProjectPilot copy does
    not confirm that iCloud has finished uploading it.

    """
}
