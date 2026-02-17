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

    // Platform-specific settings (applied into the generated Xcode project).
    @Published var iOSBundleIdentifier: String = ""
    @Published var macOSBundleIdentifier: String = ""
    @Published var tvOSBundleIdentifier: String = ""

    @Published var statusLine: StatusLine? = nil
    @Published var isRunning: Bool = false

    /// If enabled, `gh repo create` will create a public repository. Default is private.
    @Published var createPublicGitHubRepo: Bool = false

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

        // Ensure default platform settings exist before generation.
        populatePlatformDefaultsIfNeeded(projectName: name)

        let projectURL = developmentRootURL.appendingPathComponent(name, isDirectory: true)

        isRunning = true
        defer { isRunning = false }

        do {
            setStatus(.info, "Creating folder…")
            try createFolder(projectURL)

            setStatus(.info, "Generating Xcode project…")
            let typeName = sanitizeTypeName(name)
            try createXcodeProjectFromTemplate(projectName: typeName, at: projectURL)

            // Git ignore (before first commit).
            try writeGitignoreIfNeeded(at: projectURL)

            setStatus(.info, "Initializing git…")
            // Ensure the local default branch is `main`.
            // (`git init -b main` is supported on modern Git; we still defensively rename below.)
            _ = try runInDirectory(projectURL, ["/usr/bin/git", "init", "-b", "main"])
            _ = try? runInDirectory(projectURL, ["/usr/bin/git", "branch", "-M", "main"])
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

    // MARK: - Xcode Project Generation (Template .xcodeproj)

    /// Generates a multi-platform SwiftUI project whose **Xcode project settings** match the provided
    /// `ExampleProjectFile.xcodeproj` template.
    ///
    /// Notes:
    /// - This template uses Xcode's *file system synchronized groups* (PBXFileSystemSynchronizedRootGroup),
    ///   so we don't need to enumerate every Swift file in the pbxproj.
    /// - The only intended customization is the **project name**.
    private func createXcodeProjectFromTemplate(projectName: String, at projectURL: URL) throws {
        // Folder layout expected by the template.
        let appFolderURL = projectURL.appendingPathComponent(projectName, isDirectory: true)
        let unitTestsURL = projectURL.appendingPathComponent("\(projectName)Tests", isDirectory: true)
        let uiTestsURL = projectURL.appendingPathComponent("\(projectName)UITests", isDirectory: true)

        try FileManager.default.createDirectory(at: appFolderURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: unitTestsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: uiTestsURL, withIntermediateDirectories: true)

        // App sources
        try writeIfMissing(url: appFolderURL.appendingPathComponent("\(projectName)App.swift"),
                           contents: multiplatformAppTemplate(projectName: projectName))
        try writeIfMissing(url: appFolderURL.appendingPathComponent("ContentView.swift"),
                           contents: multiplatformContentViewTemplate())
        try writeIfMissing(url: appFolderURL.appendingPathComponent("Info.plist"),
                           contents: infoPlistTemplate())
        try writeIfMissing(url: appFolderURL.appendingPathComponent("\(projectName).entitlements"),
                           contents: entitlementsTemplate())

        // Assets
        try createDefaultAssetCatalogs(in: appFolderURL)

        // Tests
        try writeIfMissing(url: unitTestsURL.appendingPathComponent("\(projectName)Tests.swift"),
                           contents: unitTestTemplate(projectName: projectName))
        try writeIfMissing(url: uiTestsURL.appendingPathComponent("\(projectName)UITests.swift"),
                           contents: uiTestTemplate(projectName: projectName))
        try writeIfMissing(url: uiTestsURL.appendingPathComponent("\(projectName)UITestsLaunchTests.swift"),
                           contents: uiLaunchTestTemplate(projectName: projectName))

        // Xcode project
        try writeXcodeproj(projectName: projectName, at: projectURL)
    }

    private func writeXcodeproj(projectName: String, at projectURL: URL) throws {
        let xcodeprojURL = projectURL.appendingPathComponent("\(projectName).xcodeproj", isDirectory: true)
        let workspaceURL = xcodeprojURL.appendingPathComponent("project.xcworkspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

        let pbxprojURL = xcodeprojURL.appendingPathComponent("project.pbxproj")
        let workspaceContentsURL = workspaceURL.appendingPathComponent("contents.xcworkspacedata")

        var pbxproj = Self.pbxprojTemplate
            .replacingOccurrences(of: "ExampleProjectFile", with: projectName)

        // Apply platform selections.
        pbxproj = applySupportedPlatforms(to: pbxproj)

        // Apply platform-specific settings.
        pbxproj = applyBundleIdentifiers(projectName: projectName, to: pbxproj)


        try pbxproj.write(to: pbxprojURL, atomically: true, encoding: .utf8)

        let workspaceContents = """
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<Workspace
   version = \"1.0\">
   <FileRef
      location = \"self:\">
   </FileRef>
</Workspace>
"""
        try workspaceContents.write(to: workspaceContentsURL, atomically: true, encoding: .utf8)
    }

    private func populatePlatformDefaultsIfNeeded(projectName: String) {
        let base = "dn.\(sanitizeBundleComponent(projectName.lowercased()))"

        if iOSBundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            iOSBundleIdentifier = base
        }
        if macOSBundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            macOSBundleIdentifier = base
        }
        if tvOSBundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            tvOSBundleIdentifier = base
        }
    }

    private func sanitizeBundleComponent(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-")
        var out = ""
        out.reserveCapacity(value.count)
        for scalar in value.unicodeScalars {
            if allowed.contains(scalar) {
                out.unicodeScalars.append(scalar)
            } else {
                out.append("-")
            }
        }
        return out
            .replacingOccurrences(of: "--", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
    }

    private func applySupportedPlatforms(to pbxproj: String) -> String {
        // Template default: "iphoneos iphonesimulator macosx".
        var platforms: [String] = []

        if selectedPlatforms.contains(.iOS) {
            platforms.append(contentsOf: ["iphoneos", "iphonesimulator"])
        }
        if selectedPlatforms.contains(.macOS) {
            platforms.append("macosx")
        }
        if selectedPlatforms.contains(.tvOS) {
            platforms.append(contentsOf: ["appletvos", "appletvsimulator"])
        }

        // Safety: always keep at least one.
        if platforms.isEmpty {
            platforms = ["macosx"]
        }

        let joined = platforms.joined(separator: " ")
        return pbxproj.replacingOccurrences(of: "SUPPORTED_PLATFORMS = \"iphoneos iphonesimulator macosx\";",
                                            with: "SUPPORTED_PLATFORMS = \"\(joined)\";")
    }

    private func applyBundleIdentifiers(projectName: String, to pbxproj: String) -> String {
        let base = baseBundleIdentifier(projectName: projectName)
        let tests = "\(base)Tests"
        let uiTests = "\(base)UITests"

        var updated = pbxproj

        // First, replace template defaults.
        updated = updated.replacingOccurrences(of: "PRODUCT_BUNDLE_IDENTIFIER = dn.\(projectName);",
                                              with: "PRODUCT_BUNDLE_IDENTIFIER = \(base);")
        updated = updated.replacingOccurrences(of: "PRODUCT_BUNDLE_IDENTIFIER = dn.\(projectName)Tests;",
                                              with: "PRODUCT_BUNDLE_IDENTIFIER = \(tests);")
        updated = updated.replacingOccurrences(of: "PRODUCT_BUNDLE_IDENTIFIER = dn.\(projectName)UITests;",
                                              with: "PRODUCT_BUNDLE_IDENTIFIER = \(uiTests);")

        // App target bundle id (add per-sdk overrides when they differ).
        let appNeedOverrides = (selectedPlatforms.contains(.iOS) && iOSBundleIdentifier != base)
            || (selectedPlatforms.contains(.macOS) && macOSBundleIdentifier != base)
            || (selectedPlatforms.contains(.tvOS) && tvOSBundleIdentifier != base)

        if appNeedOverrides {
            let replacement = bundleIdentifierBlock(base: base)
            updated = updated.replacingOccurrences(of: "PRODUCT_BUNDLE_IDENTIFIER = \(base);",
                                                  with: replacement)
        }

        return updated
    }

    private func baseBundleIdentifier(projectName: String) -> String {
        let fallback = "dn.\(sanitizeBundleComponent(projectName.lowercased()))"
        if selectedPlatforms.contains(.iOS) {
            return iOSBundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : iOSBundleIdentifier
        }
        if selectedPlatforms.contains(.macOS) {
            return macOSBundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : macOSBundleIdentifier
        }
        if selectedPlatforms.contains(.tvOS) {
            return tvOSBundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : tvOSBundleIdentifier
        }
        return fallback
    }

    private func bundleIdentifierBlock(base: String) -> String {
        var lines: [String] = []
        lines.append("PRODUCT_BUNDLE_IDENTIFIER = \(base);")

        if selectedPlatforms.contains(.iOS) {
            let id = iOSBundleIdentifier
            lines.append("PRODUCT_BUNDLE_IDENTIFIER[sdk=iphoneos*] = \(id);")
            lines.append("PRODUCT_BUNDLE_IDENTIFIER[sdk=iphonesimulator*] = \(id);")
        }
        if selectedPlatforms.contains(.tvOS) {
            let id = tvOSBundleIdentifier
            lines.append("PRODUCT_BUNDLE_IDENTIFIER[sdk=appletvos*] = \(id);")
            lines.append("PRODUCT_BUNDLE_IDENTIFIER[sdk=appletvsimulator*] = \(id);")
        }
        if selectedPlatforms.contains(.macOS) {
            let id = macOSBundleIdentifier
            lines.append("PRODUCT_BUNDLE_IDENTIFIER[sdk=macosx*] = \(id);")
        }

        return lines.joined(separator: "\n                ")
    }

    private func writeIfMissing(url: URL, contents: String) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func createDefaultAssetCatalogs(in appFolderURL: URL) throws {
        let assetsURL = appFolderURL.appendingPathComponent("Assets.xcassets", isDirectory: true)
        if !FileManager.default.fileExists(atPath: assetsURL.path) {
            try FileManager.default.createDirectory(at: assetsURL, withIntermediateDirectories: true)
            let contents = """
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""
            try contents.write(to: assetsURL.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
        }

        // AccentColor
        let accentURL = assetsURL.appendingPathComponent("AccentColor.colorset", isDirectory: true)
        if !FileManager.default.fileExists(atPath: accentURL.path) {
            try FileManager.default.createDirectory(at: accentURL, withIntermediateDirectories: true)
            let contents = """
{
  "colors" : [
    {
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""
            try contents.write(to: accentURL.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
        }

        // AppIcon (placeholder; images can be added later)
        let appIconURL = assetsURL.appendingPathComponent("AppIcon.appiconset", isDirectory: true)
        if !FileManager.default.fileExists(atPath: appIconURL.path) {
            try FileManager.default.createDirectory(at: appIconURL, withIntermediateDirectories: true)
            let contents = """
{
  "images" : [
    {
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""
            try contents.write(to: appIconURL.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
        }

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

    private func uiLaunchTestTemplate(projectName: String) -> String {
        """
import XCTest

final class \(projectName)UITestsLaunchTests: XCTestCase {
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()
    }
}
"""
    }

    private func multiplatformAppTemplate(projectName: String) -> String {
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

    private func multiplatformContentViewTemplate() -> String {
        """
import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "globe")
                .imageScale(.large)
            Text("Hello, world!")
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
"""
    }

    private func infoPlistTemplate() -> String {
        """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
</dict>
</plist>
"""
    }

    private func entitlementsTemplate() -> String {
        """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
"""
    }
    // MARK: - GitHub

    private func setupGitHubRepo(name: String, projectURL: URL) throws {
        let gh = resolvedGHCommandPrefix()
        let repoName = sanitizeRepoName(name)
        let visibilityFlag = createPublicGitHubRepo ? "--public" : "--private"

        // Ensure auth is valid (gives clear error early)
        _ = try runInDirectory(projectURL, gh + ["auth", "status"])

        // Create repo and push.
        // If it already exists, gh will error; we catch and try “set remote + push”.
        do {
            // Use a dedicated remote name for GitHub.
            _ = try runInDirectory(projectURL, gh + ["repo", "create", repoName, visibilityFlag, "--source=.", "--remote=github", "--push"])
        } catch {
            // Fallback: if the repo already exists, wire `github` remote + push.
            // We avoid guessing owner/org; `gh repo view <name>` resolves against your authenticated user.
            let sshURL: String
            do {
                sshURL = try runInDirectory(projectURL, gh + ["repo", "view", repoName, "--json", "sshUrl", "-q", ".sshUrl"]) 
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                throw PPError("GitHub repo create failed for '\(repoName)'. Make sure you're logged into GitHub CLI (run: gh auth login) and that the repo name is valid.")
            }

            // Ensure we have a main branch (Git's default can vary).
            _ = try? runInDirectory(projectURL, ["/usr/bin/git", "branch", "-M", "main"])

            // Add github remote if missing (or overwrite if it exists).
            _ = try? runInDirectory(projectURL, ["/usr/bin/git", "remote", "remove", "github"])
            _ = try runInDirectory(projectURL, ["/usr/bin/git", "remote", "add", "github", sshURL])
            _ = try runInDirectory(projectURL, ["/usr/bin/git", "push", "-u", "github", "HEAD"])
        }
    }

    private func sanitizeRepoName(_ name: String) -> String {
        // GitHub repo names can't include spaces. Keep it readable and stable.
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "repo" }

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        var out: [Character] = []
        out.reserveCapacity(trimmed.count)

        var lastWasDash = false
        for ch in trimmed {
            if ch == " " || ch == "\t" || ch == "\n" {
                if !lastWasDash {
                    out.append("-")
                    lastWasDash = true
                }
                continue
            }

            if let scalar = ch.unicodeScalars.first, allowed.contains(scalar) {
                out.append(ch)
                lastWasDash = (ch == "-")
            } else {
                if !lastWasDash {
                    out.append("-")
                    lastWasDash = true
                }
            }
        }

        // Trim leading/trailing separators.
        while out.first == "-" || out.first == "." { out.removeFirst() }
        while out.last == "-" || out.last == "." { out.removeLast() }

        let result = String(out)
            .replacingOccurrences(of: "--", with: "-")
        return result.isEmpty ? "repo" : result
    }

    // MARK: - Open in Xcode

    private func openInXcode(projectURL: URL) throws {
        // The folder name can include spaces, but the Xcode project name is a sanitized type name.
        let xcodeprojName = sanitizeTypeName(projectURL.lastPathComponent)
        let xcodeproj = projectURL.appendingPathComponent("\(xcodeprojName).xcodeproj", isDirectory: true)
        if !FileManager.default.fileExists(atPath: xcodeproj.path) {
            throw PPError("Missing .xcodeproj at \(xcodeproj.lastPathComponent).")
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

    private func resolvedGHCommandPrefix() -> [String] {
        let candidates = [
            "/opt/homebrew/bin/gh",
            "/usr/local/bin/gh",
            "/usr/bin/gh"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return [path]
        }

        // Fallback: PATH resolution via env.
        // We *must* run through /usr/bin/env because Process does not resolve "gh" by itself.
        return ["/usr/bin/env", "gh"]
    }

    private func writeGitignoreIfNeeded(at projectURL: URL) throws {
        let url = projectURL.appendingPathComponent(".gitignore")
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try Self.defaultGitignore.write(to: url, atomically: true, encoding: .utf8)
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

    // MARK: - Xcode Project Template

    /// Raw pbxproj text taken from `ExampleProjectFile.xcodeproj`.
    /// We generate a new project by copying this file and replacing `ExampleProjectFile` with the user’s project name.
    private static let pbxprojTemplate = """
// !$*UTF8*$!
{
    archiveVersion = 1;
    classes = {
    };
    objectVersion = 77;
    objects = {

/* Begin PBXContainerItemProxy section */
        5A63FFDB2F44E19C00885BD6 /* PBXContainerItemProxy */ = {
            isa = PBXContainerItemProxy;
            containerPortal = 5A63FFC12F44E19C00885BD6 /* Project object */;
            proxyType = 1;
            remoteGlobalIDString = 5A63FFC82F44E19C00885BD6;
            remoteInfo = ExampleProjectFile;
        };
        5A63FFE52F44E19C00885BD6 /* PBXContainerItemProxy */ = {
            isa = PBXContainerItemProxy;
            containerPortal = 5A63FFC12F44E19C00885BD6 /* Project object */;
            proxyType = 1;
            remoteGlobalIDString = 5A63FFC82F44E19C00885BD6;
            remoteInfo = ExampleProjectFile;
        };
/* End PBXContainerItemProxy section */

/* Begin PBXFileReference section */
        5A63FFC92F44E19C00885BD6 /* ExampleProjectFile.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = ExampleProjectFile.app; sourceTree = BUILT_PRODUCTS_DIR; };
        5A63FFDA2F44E19C00885BD6 /* ExampleProjectFileTests.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = ExampleProjectFileTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };
        5A63FFE42F44E19C00885BD6 /* ExampleProjectFileUITests.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = ExampleProjectFileUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };
/* End PBXFileReference section */

/* Begin PBXFileSystemSynchronizedBuildFileExceptionSet section */
        5A63FFEC2F44E19C00885BD6 /* Exceptions for "ExampleProjectFile" folder in "ExampleProjectFile" target */ = {
            isa = PBXFileSystemSynchronizedBuildFileExceptionSet;
            membershipExceptions = (
                Info.plist,
            );
            target = 5A63FFC82F44E19C00885BD6 /* ExampleProjectFile */;
        };
/* End PBXFileSystemSynchronizedBuildFileExceptionSet section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
        5A63FFCB2F44E19C00885BD6 /* ExampleProjectFile */ = {
            isa = PBXFileSystemSynchronizedRootGroup;
            exceptions = (
                5A63FFEC2F44E19C00885BD6 /* Exceptions for "ExampleProjectFile" folder in "ExampleProjectFile" target */,
            );
            path = ExampleProjectFile;
            sourceTree = "<group>";
        };
        5A63FFDD2F44E19C00885BD6 /* ExampleProjectFileTests */ = {
            isa = PBXFileSystemSynchronizedRootGroup;
            path = ExampleProjectFileTests;
            sourceTree = "<group>";
        };
        5A63FFE72F44E19C00885BD6 /* ExampleProjectFileUITests */ = {
            isa = PBXFileSystemSynchronizedRootGroup;
            path = ExampleProjectFileUITests;
            sourceTree = "<group>";
        };
/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin PBXFrameworksBuildPhase section */
        5A63FFC62F44E19C00885BD6 /* Frameworks */ = {
            isa = PBXFrameworksBuildPhase;
            buildActionMask = 2147483647;
            files = (
            );
            runOnlyForDeploymentPostprocessing = 0;
        };
        5A63FFD72F44E19C00885BD6 /* Frameworks */ = {
            isa = PBXFrameworksBuildPhase;
            buildActionMask = 2147483647;
            files = (
            );
            runOnlyForDeploymentPostprocessing = 0;
        };
        5A63FFE12F44E19C00885BD6 /* Frameworks */ = {
            isa = PBXFrameworksBuildPhase;
            buildActionMask = 2147483647;
            files = (
            );
            runOnlyForDeploymentPostprocessing = 0;
        };
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
        5A63FFC02F44E19C00885BD6 = {
            isa = PBXGroup;
            children = (
                5A63FFCB2F44E19C00885BD6 /* ExampleProjectFile */,
                5A63FFDD2F44E19C00885BD6 /* ExampleProjectFileTests */,
                5A63FFE72F44E19C00885BD6 /* ExampleProjectFileUITests */,
                5A63FFCA2F44E19C00885BD6 /* Products */,
            );
            sourceTree = "<group>";
        };
        5A63FFCA2F44E19C00885BD6 /* Products */ = {
            isa = PBXGroup;
            children = (
                5A63FFC92F44E19C00885BD6 /* ExampleProjectFile.app */,
                5A63FFDA2F44E19C00885BD6 /* ExampleProjectFileTests.xctest */,
                5A63FFE42F44E19C00885BD6 /* ExampleProjectFileUITests.xctest */,
            );
            name = Products;
            sourceTree = "<group>";
        };
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
        5A63FFC82F44E19C00885BD6 /* ExampleProjectFile */ = {
            isa = PBXNativeTarget;
            buildConfigurationList = 5A63FFED2F44E19C00885BD6 /* Build configuration list for PBXNativeTarget "ExampleProjectFile" */;
            buildPhases = (
                5A63FFC52F44E19C00885BD6 /* Sources */,
                5A63FFC62F44E19C00885BD6 /* Frameworks */,
                5A63FFC72F44E19C00885BD6 /* Resources */,
            );
            buildRules = (
            );
            dependencies = (
            );
            fileSystemSynchronizedGroups = (
                5A63FFCB2F44E19C00885BD6 /* ExampleProjectFile */,
            );
            name = ExampleProjectFile;
            packageProductDependencies = (
            );
            productName = ExampleProjectFile;
            productReference = 5A63FFC92F44E19C00885BD6 /* ExampleProjectFile.app */;
            productType = "com.apple.product-type.application";
        };
        5A63FFD92F44E19C00885BD6 /* ExampleProjectFileTests */ = {
            isa = PBXNativeTarget;
            buildConfigurationList = 5A63FFF02F44E19C00885BD6 /* Build configuration list for PBXNativeTarget "ExampleProjectFileTests" */;
            buildPhases = (
                5A63FFD62F44E19C00885BD6 /* Sources */,
                5A63FFD72F44E19C00885BD6 /* Frameworks */,
                5A63FFD82F44E19C00885BD6 /* Resources */,
            );
            buildRules = (
            );
            dependencies = (
                5A63FFDC2F44E19C00885BD6 /* PBXTargetDependency */,
            );
            fileSystemSynchronizedGroups = (
                5A63FFDD2F44E19C00885BD6 /* ExampleProjectFileTests */,
            );
            name = ExampleProjectFileTests;
            packageProductDependencies = (
            );
            productName = ExampleProjectFileTests;
            productReference = 5A63FFDA2F44E19C00885BD6 /* ExampleProjectFileTests.xctest */;
            productType = "com.apple.product-type.bundle.unit-test";
        };
        5A63FFE32F44E19C00885BD6 /* ExampleProjectFileUITests */ = {
            isa = PBXNativeTarget;
            buildConfigurationList = 5A63FFF32F44E19C00885BD6 /* Build configuration list for PBXNativeTarget "ExampleProjectFileUITests" */;
            buildPhases = (
                5A63FFE02F44E19C00885BD6 /* Sources */,
                5A63FFE12F44E19C00885BD6 /* Frameworks */,
                5A63FFE22F44E19C00885BD6 /* Resources */,
            );
            buildRules = (
            );
            dependencies = (
                5A63FFE62F44E19C00885BD6 /* PBXTargetDependency */,
            );
            fileSystemSynchronizedGroups = (
                5A63FFE72F44E19C00885BD6 /* ExampleProjectFileUITests */,
            );
            name = ExampleProjectFileUITests;
            packageProductDependencies = (
            );
            productName = ExampleProjectFileUITests;
            productReference = 5A63FFE42F44E19C00885BD6 /* ExampleProjectFileUITests.xctest */;
            productType = "com.apple.product-type.bundle.ui-testing";
        };
/* End PBXNativeTarget section */

/* Begin PBXProject section */
        5A63FFC12F44E19C00885BD6 /* Project object */ = {
            isa = PBXProject;
            attributes = {
                BuildIndependentTargetsInParallel = 1;
                LastUpgradeCheck = 1630;
                TargetAttributes = {
                    5A63FFC82F44E19C00885BD6 = {
                        CreatedOnToolsVersion = 16.3;
                        DevelopmentTeam = H7LG8SK72M;
                    };
                    5A63FFD92F44E19C00885BD6 = {
                        CreatedOnToolsVersion = 16.3;
                        TestTargetID = 5A63FFC82F44E19C00885BD6;
                    };
                    5A63FFE32F44E19C00885BD6 = {
                        CreatedOnToolsVersion = 16.3;
                        TestTargetID = 5A63FFC82F44E19C00885BD6;
                    };
                };
            };
            buildConfigurationList = 5A63FFC42F44E19C00885BD6 /* Build configuration list for PBXProject "ExampleProjectFile" */;
            compatibilityVersion = "Xcode 14.0";
            developmentRegion = en;
            hasScannedForEncodings = 0;
            knownRegions = (
                en,
                Base,
            );
            mainGroup = 5A63FFC02F44E19C00885BD6;
            productRefGroup = 5A63FFCA2F44E19C00885BD6 /* Products */;
            projectDirPath = "";
            projectRoot = "";
            targets = (
                5A63FFC82F44E19C00885BD6 /* ExampleProjectFile */,
                5A63FFD92F44E19C00885BD6 /* ExampleProjectFileTests */,
                5A63FFE32F44E19C00885BD6 /* ExampleProjectFileUITests */,
            );
        };
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
        5A63FFC72F44E19C00885BD6 /* Resources */ = {
            isa = PBXResourcesBuildPhase;
            buildActionMask = 2147483647;
            files = (
            );
            runOnlyForDeploymentPostprocessing = 0;
        };
        5A63FFD82F44E19C00885BD6 /* Resources */ = {
            isa = PBXResourcesBuildPhase;
            buildActionMask = 2147483647;
            files = (
            );
            runOnlyForDeploymentPostprocessing = 0;
        };
        5A63FFE22F44E19C00885BD6 /* Resources */ = {
            isa = PBXResourcesBuildPhase;
            buildActionMask = 2147483647;
            files = (
            );
            runOnlyForDeploymentPostprocessing = 0;
        };
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
        5A63FFC52F44E19C00885BD6 /* Sources */ = {
            isa = PBXSourcesBuildPhase;
            buildActionMask = 2147483647;
            files = (
            );
            runOnlyForDeploymentPostprocessing = 0;
        };
        5A63FFD62F44E19C00885BD6 /* Sources */ = {
            isa = PBXSourcesBuildPhase;
            buildActionMask = 2147483647;
            files = (
            );
            runOnlyForDeploymentPostprocessing = 0;
        };
        5A63FFE02F44E19C00885BD6 /* Sources */ = {
            isa = PBXSourcesBuildPhase;
            buildActionMask = 2147483647;
            files = (
            );
            runOnlyForDeploymentPostprocessing = 0;
        };
/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
        5A63FFDC2F44E19C00885BD6 /* PBXTargetDependency */ = {
            isa = PBXTargetDependency;
            target = 5A63FFC82F44E19C00885BD6 /* ExampleProjectFile */;
            targetProxy = 5A63FFDB2F44E19C00885BD6 /* PBXContainerItemProxy */;
        };
        5A63FFE62F44E19C00885BD6 /* PBXTargetDependency */ = {
            isa = PBXTargetDependency;
            target = 5A63FFC82F44E19C00885BD6 /* ExampleProjectFile */;
            targetProxy = 5A63FFE52F44E19C00885BD6 /* PBXContainerItemProxy */;
        };
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
        5A63FFEE2F44E19C00885BD6 /* Debug */ = {
            isa = XCBuildConfiguration;
            buildSettings = {
                ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
                ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
                CODE_SIGN_ENTITLEMENTS = ExampleProjectFile/ExampleProjectFile.entitlements;
                CODE_SIGN_STYLE = Automatic;
                CURRENT_PROJECT_VERSION = 1;
                DEVELOPMENT_TEAM = H7LG8SK72M;
                ENABLE_APP_SANDBOX = YES;
                ENABLE_HARDENED_RUNTIME = YES;
                ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES;
                ENABLE_PREVIEWS = YES;
                GENERATE_INFOPLIST_FILE = YES;
                INFOPLIST_FILE = ExampleProjectFile/Info.plist;
                INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
                INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
                INFOPLIST_KEY_UILaunchScreen_Generation = YES;
                INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
                INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
                IPHONEOS_DEPLOYMENT_TARGET = 26.0;
                LD_RUNPATH_SEARCH_PATHS = (
                    "$(inherited)",
                    "@executable_path/Frameworks",
                );
                MACOSX_DEPLOYMENT_TARGET = 26.0;
                MARKETING_VERSION = 1.0;
                PRODUCT_BUNDLE_IDENTIFIER = dn.ExampleProjectFile;
                PRODUCT_NAME = "$(TARGET_NAME)";
                REGISTER_APP_GROUPS = YES;
                STRING_CATALOG_GENERATE_SYMBOLS = YES;
                SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx";
                SUPPORTS_MACCATALYST = NO;
                SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO;
                SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD = NO;
                SWIFT_APPROACHABLE_CONCURRENCY = YES;
                SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor;
                SWIFT_EMIT_LOC_STRINGS = YES;
                SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES;
                SWIFT_VERSION = 5.0;
                TARGETED_DEVICE_FAMILY = "1,2";
            };
            name = Debug;
        };
        5A63FFEF2F44E19C00885BD6 /* Release */ = {
            isa = XCBuildConfiguration;
            buildSettings = {
                ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
                ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
                CODE_SIGN_ENTITLEMENTS = ExampleProjectFile/ExampleProjectFile.entitlements;
                CODE_SIGN_STYLE = Automatic;
                CURRENT_PROJECT_VERSION = 1;
                DEVELOPMENT_TEAM = H7LG8SK72M;
                ENABLE_APP_SANDBOX = YES;
                ENABLE_HARDENED_RUNTIME = YES;
                ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES;
                ENABLE_PREVIEWS = YES;
                GENERATE_INFOPLIST_FILE = YES;
                INFOPLIST_FILE = ExampleProjectFile/Info.plist;
                INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
                INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
                INFOPLIST_KEY_UILaunchScreen_Generation = YES;
                INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
                INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
                IPHONEOS_DEPLOYMENT_TARGET = 26.0;
                LD_RUNPATH_SEARCH_PATHS = (
                    "$(inherited)",
                    "@executable_path/Frameworks",
                );
                MACOSX_DEPLOYMENT_TARGET = 26.0;
                MARKETING_VERSION = 1.0;
                PRODUCT_BUNDLE_IDENTIFIER = dn.ExampleProjectFile;
                PRODUCT_NAME = "$(TARGET_NAME)";
                REGISTER_APP_GROUPS = YES;
                STRING_CATALOG_GENERATE_SYMBOLS = YES;
                SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx";
                SUPPORTS_MACCATALYST = NO;
                SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO;
                SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD = NO;
                SWIFT_APPROACHABLE_CONCURRENCY = YES;
                SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor;
                SWIFT_EMIT_LOC_STRINGS = YES;
                SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES;
                SWIFT_VERSION = 5.0;
                TARGETED_DEVICE_FAMILY = "1,2";
            };
            name = Release;
        };
        5A63FFF12F44E19C00885BD6 /* Debug */ = {
            isa = XCBuildConfiguration;
            buildSettings = {
                BUNDLE_LOADER = "$(TEST_HOST)";
                CODE_SIGN_STYLE = Automatic;
                CURRENT_PROJECT_VERSION = 1;
                DEVELOPMENT_TEAM = H7LG8SK72M;
                GENERATE_INFOPLIST_FILE = YES;
                INFOPLIST_FILE = ExampleProjectFileTests/Info.plist;
                IPHONEOS_DEPLOYMENT_TARGET = 26.0;
                LD_RUNPATH_SEARCH_PATHS = (
                    "$(inherited)",
                    "@executable_path/Frameworks",
                    "@loader_path/Frameworks",
                );
                MACOSX_DEPLOYMENT_TARGET = 26.0;
                MARKETING_VERSION = 1.0;
                PRODUCT_BUNDLE_IDENTIFIER = dn.ExampleProjectFileTests;
                PRODUCT_NAME = "$(TARGET_NAME)";
                SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx";
                SUPPORTS_MACCATALYST = NO;
                SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO;
                SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD = NO;
                SWIFT_VERSION = 5.0;
                TARGETED_DEVICE_FAMILY = "1,2";
                TEST_HOST = "$(BUILT_PRODUCTS_DIR)/ExampleProjectFile.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/ExampleProjectFile";
            };
            name = Debug;
        };
        5A63FFF22F44E19C00885BD6 /* Release */ = {
            isa = XCBuildConfiguration;
            buildSettings = {
                BUNDLE_LOADER = "$(TEST_HOST)";
                CODE_SIGN_STYLE = Automatic;
                CURRENT_PROJECT_VERSION = 1;
                DEVELOPMENT_TEAM = H7LG8SK72M;
                GENERATE_INFOPLIST_FILE = YES;
                INFOPLIST_FILE = ExampleProjectFileTests/Info.plist;
                IPHONEOS_DEPLOYMENT_TARGET = 26.0;
                LD_RUNPATH_SEARCH_PATHS = (
                    "$(inherited)",
                    "@executable_path/Frameworks",
                    "@loader_path/Frameworks",
                );
                MACOSX_DEPLOYMENT_TARGET = 26.0;
                MARKETING_VERSION = 1.0;
                PRODUCT_BUNDLE_IDENTIFIER = dn.ExampleProjectFileTests;
                PRODUCT_NAME = "$(TARGET_NAME)";
                SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx";
                SUPPORTS_MACCATALYST = NO;
                SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO;
                SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD = NO;
                SWIFT_VERSION = 5.0;
                TARGETED_DEVICE_FAMILY = "1,2";
                TEST_HOST = "$(BUILT_PRODUCTS_DIR)/ExampleProjectFile.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/ExampleProjectFile";
            };
            name = Release;
        };
        5A63FFF42F44E19C00885BD6 /* Debug */ = {
            isa = XCBuildConfiguration;
            buildSettings = {
                CODE_SIGN_STYLE = Automatic;
                CURRENT_PROJECT_VERSION = 1;
                DEVELOPMENT_TEAM = H7LG8SK72M;
                GENERATE_INFOPLIST_FILE = YES;
                INFOPLIST_FILE = ExampleProjectFileUITests/Info.plist;
                IPHONEOS_DEPLOYMENT_TARGET = 26.0;
                LD_RUNPATH_SEARCH_PATHS = (
                    "$(inherited)",
                    "@executable_path/Frameworks",
                    "@loader_path/Frameworks",
                );
                MACOSX_DEPLOYMENT_TARGET = 26.0;
                MARKETING_VERSION = 1.0;
                PRODUCT_BUNDLE_IDENTIFIER = dn.ExampleProjectFileUITests;
                PRODUCT_NAME = "$(TARGET_NAME)";
                SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx";
                SUPPORTS_MACCATALYST = NO;
                SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO;
                SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD = NO;
                SWIFT_VERSION = 5.0;
                TARGETED_DEVICE_FAMILY = "1,2";
                TEST_TARGET_NAME = ExampleProjectFile;
            };
            name = Debug;
        };
        5A63FFF52F44E19C00885BD6 /* Release */ = {
            isa = XCBuildConfiguration;
            buildSettings = {
                CODE_SIGN_STYLE = Automatic;
                CURRENT_PROJECT_VERSION = 1;
                DEVELOPMENT_TEAM = H7LG8SK72M;
                GENERATE_INFOPLIST_FILE = YES;
                INFOPLIST_FILE = ExampleProjectFileUITests/Info.plist;
                IPHONEOS_DEPLOYMENT_TARGET = 26.0;
                LD_RUNPATH_SEARCH_PATHS = (
                    "$(inherited)",
                    "@executable_path/Frameworks",
                    "@loader_path/Frameworks",
                );
                MACOSX_DEPLOYMENT_TARGET = 26.0;
                MARKETING_VERSION = 1.0;
                PRODUCT_BUNDLE_IDENTIFIER = dn.ExampleProjectFileUITests;
                PRODUCT_NAME = "$(TARGET_NAME)";
                SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx";
                SUPPORTS_MACCATALYST = NO;
                SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO;
                SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD = NO;
                SWIFT_VERSION = 5.0;
                TARGETED_DEVICE_FAMILY = "1,2";
                TEST_TARGET_NAME = ExampleProjectFile;
            };
            name = Release;
        };
        5A63FFC22F44E19C00885BD6 /* Debug */ = {
            isa = XCBuildConfiguration;
            buildSettings = {
                CLANG_ANALYZER_LOCALIZABILITY_NONLOCALIZED = YES;
                CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
                CLANG_WARN_SUSPICIOUS_MOVE = YES;
                CLANG_WARN_UNGUARDED_AVAILABILITY = YES;
                CODE_SIGN_STYLE = Automatic;
                DEVELOPMENT_TEAM = H7LG8SK72M;
                ENABLE_USER_SCRIPT_SANDBOXING = YES;
                GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
                GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
                GCC_WARN_UNDECLARED_SELECTOR = YES;
                GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
                GCC_WARN_UNUSED_FUNCTION = YES;
                GCC_WARN_UNUSED_VARIABLE = YES;
                IPHONEOS_DEPLOYMENT_TARGET = 26.0;
                MACOSX_DEPLOYMENT_TARGET = 26.0;
                SWIFT_APPROACHABLE_CONCURRENCY = YES;
                SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor;
            };
            name = Debug;
        };
        5A63FFC32F44E19C00885BD6 /* Release */ = {
            isa = XCBuildConfiguration;
            buildSettings = {
                CLANG_ANALYZER_LOCALIZABILITY_NONLOCALIZED = YES;
                CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
                CLANG_WARN_SUSPICIOUS_MOVE = YES;
                CLANG_WARN_UNGUARDED_AVAILABILITY = YES;
                CODE_SIGN_STYLE = Automatic;
                DEVELOPMENT_TEAM = H7LG8SK72M;
                ENABLE_USER_SCRIPT_SANDBOXING = YES;
                GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
                GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
                GCC_WARN_UNDECLARED_SELECTOR = YES;
                GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
                GCC_WARN_UNUSED_FUNCTION = YES;
                GCC_WARN_UNUSED_VARIABLE = YES;
                IPHONEOS_DEPLOYMENT_TARGET = 26.0;
                MACOSX_DEPLOYMENT_TARGET = 26.0;
                SWIFT_APPROACHABLE_CONCURRENCY = YES;
                SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor;
            };
            name = Release;
        };
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
        5A63FFC42F44E19C00885BD6 /* Build configuration list for PBXProject "ExampleProjectFile" */ = {
            isa = XCConfigurationList;
            buildConfigurations = (
                5A63FFC22F44E19C00885BD6 /* Debug */,
                5A63FFC32F44E19C00885BD6 /* Release */,
            );
            defaultConfigurationIsVisible = 0;
            defaultConfigurationName = Release;
        };
        5A63FFED2F44E19C00885BD6 /* Build configuration list for PBXNativeTarget "ExampleProjectFile" */ = {
            isa = XCConfigurationList;
            buildConfigurations = (
                5A63FFEE2F44E19C00885BD6 /* Debug */,
                5A63FFEF2F44E19C00885BD6 /* Release */,
            );
            defaultConfigurationIsVisible = 0;
            defaultConfigurationName = Release;
        };
        5A63FFF02F44E19C00885BD6 /* Build configuration list for PBXNativeTarget "ExampleProjectFileTests" */ = {
            isa = XCConfigurationList;
            buildConfigurations = (
                5A63FFF12F44E19C00885BD6 /* Debug */,
                5A63FFF22F44E19C00885BD6 /* Release */,
            );
            defaultConfigurationIsVisible = 0;
            defaultConfigurationName = Release;
        };
        5A63FFF32F44E19C00885BD6 /* Build configuration list for PBXNativeTarget "ExampleProjectFileUITests" */ = {
            isa = XCConfigurationList;
            buildConfigurations = (
                5A63FFF42F44E19C00885BD6 /* Debug */,
                5A63FFF52F44E19C00885BD6 /* Release */,
            );
            defaultConfigurationIsVisible = 0;
            defaultConfigurationName = Release;
        };
/* End XCConfigurationList section */
    };
    rootObject = 5A63FFC12F44E19C00885BD6 /* Project object */;
}
"""

    // MARK: - Errors

    private struct PPError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
