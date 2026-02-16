import Combine
import Foundation

@MainActor
final class ProjectPilotViewModel: ObservableObject {
    enum Platform: String, CaseIterable, Identifiable {
        case iOS, macOS, tvOS
        var id: String { rawValue }

        var folderName: String { rawValue }
    }

    enum StatusLevel: Equatable {
        case info
        case error
        case success
    }

    struct StatusLine: Equatable {
        let level: StatusLevel
        let message: String
    }

    @Published var projectName: String = ""
    @Published var selectedPlatforms: Set<Platform> = [.macOS]

    @Published var statusLine: StatusLine? = nil
    @Published var isRunning: Bool = false

    // Your hard-coded root.
    private let developmentRootURL = URL(fileURLWithPath: "/Users/donnoel/Development", isDirectory: true)

    func createProjectSkeleton() {
        guard !isRunning else { return }
        Task { await createProjectSkeletonAsync() }
    }

    func clearStatus() {
        statusLine = nil
    }

    // MARK: - Pipeline

    private func createProjectSkeletonAsync() async {
        let name = sanitizedProjectName
        guard !name.isEmpty else {
            setStatus(.error, "Please enter a project name.")
            return
        }

        let projectURL = developmentRootURL.appendingPathComponent(name, isDirectory: true)

        isRunning = true
        defer { isRunning = false }

        do {
            setStatus(.info, "Creating folder…")
            try createFolder(projectURL)

            setStatus(.info, "Generating Xcode project…")
            let typeName = sanitizeTypeName(name)
            try await createXcodeProject(projectName: typeName, platforms: selectedPlatforms, at: projectURL)

            setStatus(.info, "Initializing git…")
            _ = try runInDirectory(projectURL, ["/usr/bin/git", "init"])
            _ = try runInDirectory(projectURL, ["/usr/bin/git", "add", "-A"])
            _ = try? runInDirectory(projectURL, ["/usr/bin/git", "commit", "-m", "Initial commit"])

            setStatus(.info, "Creating GitHub repo…")
            try setupGitHubRepo(name: name, projectURL: projectURL)

            setStatus(.info, "Opening in Xcode…")
            try openInXcode(projectURL: projectURL)

            // You asked: clear the “text box” after folder created / after success.
            // Practically: keep success only briefly then clear.
            setStatus(.success, "Done ✅")
            try? await Task.sleep(nanoseconds: 700_000_000)
            clearStatus()
        } catch {
            setStatus(.error, error.localizedDescription)
        }
    }

    private func createFolder(_ url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            throw PPError("Folder already exists: \(url.lastPathComponent)")
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    // MARK: - Xcode Project Generation (XcodeGen)

    private func createXcodeProject(projectName: String, platforms: Set<Platform>, at projectURL: URL) async throws {
        // Build a simple, real-folder layout (no “Sources/”), because you prefer
        // Xcode showing folder references (blue) that mirror the filesystem.
        let sharedURL = projectURL.appendingPathComponent("Shared", isDirectory: true)
        try FileManager.default.createDirectory(at: sharedURL, withIntermediateDirectories: true)

        // Create per-platform folders (macOS/iOS/tvOS) only for selected platforms.
        for platform in platforms {
            let platformURL = projectURL.appendingPathComponent(platform.folderName, isDirectory: true)
            try FileManager.default.createDirectory(at: platformURL, withIntermediateDirectories: true)
        }

        // Shared ContentView
        let contentViewURL = sharedURL.appendingPathComponent("ContentView.swift")
        try contentViewTemplate(projectName: projectName).write(to: contentViewURL, atomically: true, encoding: .utf8)

        // Platform App entrypoints
        for platform in platforms {
            let platformURL = projectURL.appendingPathComponent(platform.folderName, isDirectory: true)
            let appFileURL = platformURL.appendingPathComponent("\(projectName)App.swift")
            try appEntryTemplate(projectName: projectName, platform: platform).write(to: appFileURL, atomically: true, encoding: .utf8)
        }

        // Default-ish test folders (blue folder references) + placeholder tests.
        let unitTestsURL = projectURL.appendingPathComponent("\(projectName)Tests", isDirectory: true)
        let uiTestsURL = projectURL.appendingPathComponent("\(projectName)UITests", isDirectory: true)
        try FileManager.default.createDirectory(at: unitTestsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: uiTestsURL, withIntermediateDirectories: true)

        let unitTestFileURL = unitTestsURL.appendingPathComponent("\(projectName)Tests.swift")
        let uiTestFileURL = uiTestsURL.appendingPathComponent("\(projectName)UITests.swift")

        if !FileManager.default.fileExists(atPath: unitTestFileURL.path) {
            try unitTestTemplate(projectName: projectName).write(to: unitTestFileURL, atomically: true, encoding: .utf8)
        }
        if !FileManager.default.fileExists(atPath: uiTestFileURL.path) {
            try uiTestTemplate(projectName: projectName).write(to: uiTestFileURL, atomically: true, encoding: .utf8)
        }

        // XcodeGen manifest + generate project
        let ymlURL = projectURL.appendingPathComponent("project.yml")
        try makeProjectYml(projectName: projectName, platforms: platforms).write(to: ymlURL, atomically: true, encoding: .utf8)

        // Generate the .xcodeproj using XcodeGen.
        let xcodegen = try resolveXcodeGen()
        if xcodegen == "/usr/bin/env" {
            _ = try run(["/usr/bin/env", "xcodegen", "generate"], cwd: projectURL)
        } else {
            _ = try run([xcodegen, "generate"], cwd: projectURL)
        }
    }

    private func makeProjectYml(projectName: String, platforms: Set<Platform>) -> String {
        // Prefer macOS as the “primary” platform if selected; otherwise pick the first selected.
        let orderedSelected = Platform.allCases.filter { platforms.contains($0) }
        let primary = orderedSelected.first(where: { $0 == .macOS }) ?? orderedSelected.first ?? .macOS
        let isMultiPlatform = Set(orderedSelected).count > 1

        func platformConfig(_ platform: Platform) -> (platformString: String, deployment: String, bundleSuffix: String, folderName: String) {
            switch platform {
            case .macOS:
                return ("macOS", "14.0", "macos", platform.folderName)
            case .iOS:
                return ("iOS", "17.0", "ios", platform.folderName)
            case .tvOS:
                return ("tvOS", "17.0", "tvos", platform.folderName)
            }
        }

        func appTargetName(for platform: Platform) -> String {
            if isMultiPlatform { return "\(projectName)-\(platform.rawValue)" }
            return projectName
        }

        // App targets
        var targetsYAML: [String] = []
        for platform in orderedSelected {
            let cfg = platformConfig(platform)
            let tName = appTargetName(for: platform)
            let bundleId = "dn.\(projectName.lowercased()).\(cfg.bundleSuffix)"

            targetsYAML.append(
"""
  \(tName):
    type: application
    platform: \(cfg.platformString)
    deploymentTarget: "\(cfg.deployment)"
    bundleId: \(bundleId)
    settings:
      base:
        GENERATE_INFOPLIST_FILE: YES
    sources:
      - path: Shared
        type: folder
      - path: \(cfg.folderName)
        type: folder
"""
            )
        }

        // Unit Tests + UI Tests for the primary platform only (keeps the project simple and matches Xcode defaults).
        let primaryTargetName = appTargetName(for: primary)

        targetsYAML.append(
"""
  \(projectName)Tests:
    type: bundle.unit-test
    platform: \(platformConfig(primary).platformString)
    deploymentTarget: "\(platformConfig(primary).deployment)"
    sources:
      - path: \(projectName)Tests
        type: folder
    dependencies:
      - target: \(primaryTargetName)
"""
        )

        targetsYAML.append(
"""
  \(projectName)UITests:
    type: bundle.ui-testing
    platform: \(platformConfig(primary).platformString)
    deploymentTarget: "\(platformConfig(primary).deployment)"
    sources:
      - path: \(projectName)UITests
        type: folder
    dependencies:
      - target: \(primaryTargetName)
"""
        )

        return """
name: \(projectName)
options:
  createIntermediateGroups: false
  indentWidth: 4
  tabWidth: 4
settings:
  base:
    SWIFT_VERSION: 5.0

targets:
\(targetsYAML.joined(separator: "\n"))
"""
    }

    private func contentViewTemplate(projectName: String) -> String {
        """
import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 10) {
            Text("\(projectName)")
                .font(.title)
            Text("Ready")
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }
}

#Preview {
    ContentView()
}
"""
    }

    private func appEntryTemplate(projectName: String, platform: Platform) -> String {
        // Keep this simple and Apple-native.
        // macOS needs a WindowGroup; iOS/tvOS too.
        """
import SwiftUI

@main
struct \(projectName)App: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
"""
    }

    private func unitTestTemplate(projectName: String) -> String {
        """
import XCTest

final class \(projectName)Tests: XCTestCase {
    func testExample() throws {
        // Arrange / Act / Assert
        XCTAssertTrue(true)
    }
}
"""
    }

    private func uiTestTemplate(projectName: String) -> String {
        """
import XCTest

final class \(projectName)UITests: XCTestCase {
    func testExample() throws {
        let app = XCUIApplication()
        app.launch()
        // Basic smoke test
        XCTAssertTrue(app.windows.count >= 0)
    }
}
"""
    }
    // MARK: - GitHub

    private func setupGitHubRepo(name: String, projectURL: URL) throws {
        let ghPath = resolveGH()

        // Ensure auth is valid (gives clear error early)
        _ = try runInDirectory(projectURL, [ghPath, "auth", "status"])

        // Create repo and push.
        // If it already exists, gh will error; we catch and try “set remote + push”.
        do {
            _ = try runInDirectory(projectURL, [ghPath, "repo", "create", name, "--private", "--source=.", "--remote=origin", "--push"])
        } catch {
            // Fallback: try adding remote if missing, then push.
            // (We don't guess your org/user here; gh can infer with `repo view` but keep it simple.)
            // If you want, we can improve this next.
            _ = try? runInDirectory(projectURL, ["/usr/bin/git", "remote", "-v"])
            throw PPError("GitHub repo create failed. If the repo already exists, add remote manually or tell me your GitHub org/user and I’ll wire it cleanly.")
        }
    }

    // MARK: - Open in Xcode

    private func openInXcode(projectURL: URL) throws {
        let xcodeproj = projectURL.appendingPathComponent("\(projectURL.lastPathComponent).xcodeproj", isDirectory: true)
        if !FileManager.default.fileExists(atPath: xcodeproj.path) {
            throw PPError("Missing .xcodeproj at \(xcodeproj.lastPathComponent). (XcodeGen generation may have failed.)")
        }
        _ = try run([ "/usr/bin/open", "-a", "Xcode", xcodeproj.path ])
    }

    // MARK: - Process helpers

    private func resolveXcodeGen() throws -> String {
        let candidates = [
            "/opt/homebrew/bin/xcodegen",
            "/usr/local/bin/xcodegen",
            "/usr/bin/xcodegen"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        // As a fallback, try PATH resolution
        if (try? run(["/usr/bin/env", "xcodegen", "--version"])) != nil {
            return "/usr/bin/env"
        }
        throw PPError("xcodegen not found. Install with: brew install xcodegen")
    }

    private func resolveGH() -> String {
        let candidates = [
            "/opt/homebrew/bin/gh",
            "/usr/local/bin/gh",
            "/usr/bin/gh"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return "gh" // rely on PATH; if missing, command will fail with a good error
    }

    private func runInDirectory(_ directory: URL, _ argv: [String]) throws -> String {
        try run(argv, cwd: directory)
    }

    private func run(_ argv: [String], cwd: URL? = nil) throws -> String {
        guard let exe = argv.first else { throw PPError("Invalid command.") }
        let args = Array(argv.dropFirst())

        let process = Process()
        process.executableURL = URL(fileURLWithPath: exe)
        process.arguments = args
        if let cwd { process.currentDirectoryURL = cwd }

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        try process.run()
        process.waitUntilExit()

        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()

        let outStr = String(data: outData, encoding: .utf8) ?? ""
        let errStr = String(data: errData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            let msg = errStr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw PPError(msg.isEmpty ? "Command failed: \(exe) \(args.joined(separator: " "))" : msg)
        }

        return outStr
    }

    private func writeText(_ text: String, to url: URL) throws {
        guard let data = text.data(using: .utf8) else {
            throw PPError("Failed to encode text for \(url.lastPathComponent)")
        }
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Sanitization

    private var sanitizedProjectName: String {
        let trimmed = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // Allow letters, numbers, space, dash, underscore.
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
        let cleanedScalars = trimmed.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let cleaned = String(cleanedScalars)
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned
    }

    private func sanitizeTypeName(_ name: String) -> String {
        // Turn "Loom Tools" into "LoomTools"
        let comps = name
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let joined = comps.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
        return joined.isEmpty ? "App" : joined
    }

    // MARK: - Status

    private func setStatus(_ level: StatusLevel, _ message: String) {
        statusLine = StatusLine(level: level, message: message)
    }

    // MARK: - Defaults

    private static let defaultGitignore = """
    # Xcode
    DerivedData/
    *.xcuserdata
    *.xcuserstate
    *.xccheckout
    *.xcscmblueprint

    # SwiftPM
    .build/

    # macOS
    .DS_Store

    # Logs
    *.log

    # Fastlane (if you ever use it)
    fastlane/report.xml
    fastlane/Preview.html
    fastlane/screenshots
    fastlane/test_output
    """

    // MARK: - Errors

    private struct PPError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
