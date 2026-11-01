import Foundation
import Testing
@testable import ProjectPilot

struct DevelopmentSkillsBackupTests {
    @Test func bothLibrariesAndHiddenReferencesReachTheCloudMirrorWithoutChangingSources() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try write("agents version", to: home, path: ".agents/skills/shared/SKILL.md")
        try write("codex version", to: home, path: ".codex/skills/shared/SKILL.md")
        try write("reference", to: home, path: ".codex/skills/.system/example/build/dist/.hidden")
        try write("keep", to: home, path: "Development/Existing/File.swift")

        try synchronize(home)
        let source = home.appendingPathComponent("Development")
        let cloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Development")
        try FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)
        _ = try ProjectPilotViewModel.runProcess(
            ProjectPilotViewModel.developmentBackupRsyncArguments(sourceURL: source, backupURL: cloud, dryRun: false),
            timeoutSeconds: 10
        )

        for root in [source, cloud] {
            #expect(try read(root, path: "skills/agents/shared/SKILL.md") == "agents version")
            #expect(try read(root, path: "skills/codex/shared/SKILL.md") == "codex version")
            #expect(try read(root, path: "skills/codex/.system/example/build/dist/.hidden") == "reference")
            #expect(try read(root, path: "skills/README.md").contains("~/.agents/skills/"))
            #expect(try read(root, path: "Existing/File.swift") == "keep")
        }
        #expect(try read(home, path: ".agents/skills/shared/SKILL.md") == "agents version")
        #expect(try read(home, path: ".codex/skills/shared/SKILL.md") == "codex version")
    }

    @Test func sameSizeSameDateEditsAndRemovalsAreCopiedAndIdleRunsDoNotRewriteFiles() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let relative = ".agents/skills/example/SKILL.md"
        try write("before", to: home, path: relative)
        // Use an exact whole-second fixture; Foundation setters round subsecond dates.
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_700_000_000)],
            ofItemAtPath: home.appendingPathComponent(relative).path
        )
        try write("old", to: home, path: ".codex/skills/removed/SKILL.md")
        try synchronize(home)
        let development = home.appendingPathComponent("Development")
        let cloud = home.appendingPathComponent("CloudMirror")
        try FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)
        _ = try ProjectPilotViewModel.runProcess(
            DevelopmentSkillsBackup.cloudMirrorArguments(developmentURL: development, backupURL: cloud),
            timeoutSeconds: 10
        )
        let copied = home.appendingPathComponent("Development/skills/agents/example/SKILL.md")
        let readme = home.appendingPathComponent("Development/skills/README.md")
        let copiedDate = try modificationDate(copied)
        let readmeDate = try modificationDate(readme)
        try synchronize(home)
        #expect(try modificationDate(copied) == copiedDate)
        #expect(try modificationDate(readme) == readmeDate)

        let original = home.appendingPathComponent(relative)
        let originalDate = try modificationDate(original)
        try write("after!", to: home, path: relative)
        try FileManager.default.setAttributes([.modificationDate: originalDate], ofItemAtPath: original.path)
        try FileManager.default.removeItem(at: home.appendingPathComponent(".codex/skills/removed"))
        try synchronize(home)
        #expect(try String(contentsOf: copied, encoding: .utf8) == "after!")
        #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent("Development/skills/codex/removed").path))
        #expect(try modificationDate(original) == originalDate)
        _ = try ProjectPilotViewModel.runProcess(
            DevelopmentSkillsBackup.cloudMirrorArguments(developmentURL: development, backupURL: cloud),
            timeoutSeconds: 10
        )
        #expect(try read(cloud, path: "skills/agents/example/SKILL.md") == "after!")
        #expect(!FileManager.default.fileExists(atPath: cloud.appendingPathComponent("skills/codex/removed").path))
    }

    @Test func missingSourceKeepsBothLastCopiesAndFailsBeforeRunningRsync() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try write("saved", to: home, path: ".agents/skills/example/SKILL.md")
        try synchronize(home)
        try write("edited", to: home, path: ".agents/skills/example/SKILL.md")
        try FileManager.default.removeItem(at: home.appendingPathComponent(".codex/skills"))
        var ranProcess = false
        #expect(throws: (any Error).self) {
            try DevelopmentSkillsBackup.synchronize(homeDirectoryURL: home) { _ in ranProcess = true }
        }
        #expect(!ranProcess)
        #expect(try read(home, path: "Development/skills/agents/example/SKILL.md") == "saved")
    }

    @Test func destinationSymlinkCannotRedirectDeletionIntoLiveSkills() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try write("original", to: home, path: ".agents/skills/example/SKILL.md")
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Development/skills"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: home.appendingPathComponent("Development/skills/codex"),
            withDestinationURL: home.appendingPathComponent(".agents/skills")
        )
        #expect(throws: (any Error).self) { try synchronize(home) }
        #expect(try read(home, path: ".agents/skills/example/SKILL.md") == "original")
    }

    @Test func processFailureIsPropagatedInsteadOfReportingACompleteSkillsCopy() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(throws: CocoaError.self) {
            try DevelopmentSkillsBackup.synchronize(homeDirectoryURL: home) { _ in
                throw CocoaError(.fileReadNoPermission)
            }
        }
        #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent("Development/skills/README.md").path))
    }

    private func makeHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("PPSkills-\(UUID().uuidString)")
        for path in ["Development", ".agents/skills", ".codex/skills"] {
            try FileManager.default.createDirectory(at: home.appendingPathComponent(path), withIntermediateDirectories: true)
        }
        return home
    }

    private func synchronize(_ home: URL) throws {
        try DevelopmentSkillsBackup.synchronize(homeDirectoryURL: home) { arguments in
            _ = try ProjectPilotViewModel.runProcess(arguments, timeoutSeconds: 10)
        }
    }

    private func write(_ text: String, to root: URL, path: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func read(_ root: URL, path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private func modificationDate(_ url: URL) throws -> Date {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try #require(attributes[.modificationDate] as? Date)
    }
}
