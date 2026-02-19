import Combine
import Foundation
import AppKit

@MainActor
final class ProjectPilotViewModel: ObservableObject {
    enum Platform: String, CaseIterable, Identifiable, Codable {
        case iOS, macOS, tvOS
        var id: String { rawValue }

        var folderName: String { rawValue }
    }

    enum TemplateProfile: String, CaseIterable, Identifiable, Codable {
        case starterApp
        case dashboardApp
        case utilityTool

        var id: String { rawValue }

        var title: String {
            switch self {
            case .starterApp: return "Starter App"
            case .dashboardApp: return "Dashboard App"
            case .utilityTool: return "Utility Tool"
            }
        }

        var description: String {
            switch self {
            case .starterApp: return "Clean SwiftUI starter with basic project structure."
            case .dashboardApp: return "Navigation-based starter with overview and tasks sections."
            case .utilityTool: return "Compact utility-style starter aimed at productivity tools."
            }
        }
    }

    struct CreationPreset: Identifiable, Codable, Hashable {
        let id: String
        var name: String
        var templateProfile: TemplateProfile
        var platforms: Set<Platform>
        var iOSBundleIdentifier: String
        var macOSBundleIdentifier: String
        var tvOSBundleIdentifier: String
        var createGitHubRepo: Bool
        var createPublicGitHubRepo: Bool
    }

    enum PipelineStep: String, CaseIterable, Identifiable {
        case folder
        case xcodeproj
        case git
        case github
        case open

        var id: String { rawValue }

        var title: String {
            switch self {
            case .folder: return "Folder"
            case .xcodeproj: return "Xcodeproj"
            case .git: return "Git"
            case .github: return "GitHub"
            case .open: return "Open"
            }
        }
    }

    enum PipelineStepState: Equatable {
        case pending
        case inProgress
        case success
        case skipped
        case failure
    }

    struct PipelineProgressItem: Identifiable, Equatable {
        let step: PipelineStep
        let state: PipelineStepState
        var id: PipelineStep { step }
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

    struct CodexQuotaSnapshot: Equatable {
        struct UsageLimit: Equatable {
            let usedPercent: Double
            let remainingPercent: Double
            let windowMinutes: Int
            let resetAt: Date?
        }

        struct Credits: Equatable {
            let hasCredits: Bool
            let isUnlimited: Bool
            let balance: Double?
        }

        let primary: UsageLimit?
        let secondary: UsageLimit?
        let credits: Credits?
        let sourcePath: String
    }

    @Published var projectName: String = ""
    @Published var selectedPlatforms: Set<Platform> = [.iOS] {
        didSet {
            if selectedPlatforms.isEmpty {
                selectedPlatforms = [.macOS]
            }
            persistSelectedPlatforms()
        }
    }

    // Platform-specific settings (applied into the generated Xcode project).
    @Published var iOSBundleIdentifier: String = "" { didSet { persistBundleIdentifiers() } }
    @Published var macOSBundleIdentifier: String = "" { didSet { persistBundleIdentifiers() } }
    @Published var tvOSBundleIdentifier: String = "" { didSet { persistBundleIdentifiers() } }

    @Published var selectedTemplateProfile: TemplateProfile = .starterApp {
        didSet { persistTemplateProfile() }
    }

    @Published var statusLine: StatusLine? = nil
    @Published var isRunning: Bool = false

    /// If enabled, create and push a remote GitHub repository. If disabled, keep setup local only.
    @Published var createGitHubRepo: Bool = true { didSet { persistGitHubSettings() } }

    /// If enabled, `gh repo create` will create a public repository. Default is private.
    @Published var createPublicGitHubRepo: Bool = false { didSet { persistGitHubSettings() } }

    /// Root directory where new projects are created.
    @Published var projectRootURL: URL = ProjectPilotViewModel.defaultProjectRootURL() {
        didSet { persistProjectRootURL() }
    }

    /// Post-create checklist options.
    @Published var openInXcodeAfterCreate: Bool = true { didSet { persistPostCreateSettings() } }
    @Published var openInCodexAfterCreate: Bool = false { didSet { persistPostCreateSettings() } }
    @Published var openInCLIAfterCreate: Bool = false { didSet { persistPostCreateSettings() } }
    @Published var revealInFinderAfterCreate: Bool = false { didSet { persistPostCreateSettings() } }
    @Published var openGitHubRepoInSafariAfterCreate: Bool = false { didSet { persistPostCreateSettings() } }

    @Published private(set) var lastCreatedGitHubRepoURL: String? = nil

    @Published private(set) var customPresets: [CreationPreset] = [] {
        didSet { persistCustomPresets() }
    }
    @Published var selectedPresetID: String = ProjectPilotViewModel.defaultPresetID {
        didSet { persistSelectedPresetID() }
    }
    @Published var newPresetName: String = ""

    @Published private(set) var pendingGitHubRetryName: String? = nil
    @Published private(set) var pendingGitHubRetryPath: String? = nil

    @Published var isDetailsExpanded: Bool = false
    @Published private(set) var detailLogs: [LogEvent] = []
    @Published private(set) var hasFailureDetails: Bool = false
    @Published private(set) var pipelineStepStates: [PipelineStep: PipelineStepState] = ProjectPilotViewModel.defaultPipelineStepStates()
    @Published private(set) var lastCreatedProjectURL: URL? = nil
    @Published private(set) var codexQuotaSnapshot: CodexQuotaSnapshot? = nil
    @Published private(set) var codexQuotaLastUpdatedAt: Date? = nil
    @Published private(set) var codexQuotaError: String? = nil

    private let codexQuotaReader: CodexQuotaReader
    private var codexQuotaPollingTask: Task<Void, Never>? = nil

    var canRetryGitHub: Bool {
        pendingGitHubRetryName != nil && pendingGitHubRetryPath != nil
    }

    var pipelineProgressItems: [PipelineProgressItem] {
        PipelineStep.allCases.map { step in
            PipelineProgressItem(step: step, state: pipelineStepStates[step] ?? .pending)
        }
    }

    var shouldShowDetailsPanel: Bool {
        hasFailureDetails || isDetailsExpanded || statusLine?.level == .error
    }

    var hasDetailLogs: Bool {
        !detailLogs.isEmpty
    }

    var shouldShowSuccessCard: Bool {
        lastCreatedProjectURL != nil
    }

    var lastCreatedProjectPathDisplay: String {
        guard let url = lastCreatedProjectURL else { return "" }
        return (url.path as NSString).abbreviatingWithTildeInPath
    }

    var canCreateProject: Bool {
        !isRunning && !hasValidationErrors && !sanitizedProjectName.isEmpty
    }

    var projectNameValidationHint: String? {
        let trimmed = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Project name is required."
        }
        if !containsAlphanumeric(trimmed) {
            return "Use at least one letter or number."
        }

        let typeName = sanitizeTypeName(trimmed)
        if !isValidSwiftTypeName(typeName) {
            return "Start with a letter so generated Swift type names are valid."
        }

        if sanitizedProjectName != trimmed {
            return "Unsupported characters will be replaced automatically."
        }

        return nil
    }

    var isProjectNameInvalid: Bool {
        let trimmed = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        guard containsAlphanumeric(trimmed) else { return true }
        return !isValidSwiftTypeName(sanitizeTypeName(trimmed))
    }

    var iOSBundleValidationHint: String? {
        bundleValidationHint(value: iOSBundleIdentifier, platform: .iOS)
    }

    var macOSBundleValidationHint: String? {
        bundleValidationHint(value: macOSBundleIdentifier, platform: .macOS)
    }

    var tvOSBundleValidationHint: String? {
        bundleValidationHint(value: tvOSBundleIdentifier, platform: .tvOS)
    }

    var isIOSBundleInvalid: Bool {
        selectedPlatforms.contains(.iOS) && isBundleIdentifierInvalid(iOSBundleIdentifier)
    }

    var isMacOSBundleInvalid: Bool {
        selectedPlatforms.contains(.macOS) && isBundleIdentifierInvalid(macOSBundleIdentifier)
    }

    var isTVOSBundleInvalid: Bool {
        selectedPlatforms.contains(.tvOS) && isBundleIdentifierInvalid(tvOSBundleIdentifier)
    }

    var hasValidationErrors: Bool {
        isProjectNameInvalid
    }

    var availablePresets: [CreationPreset] {
        Self.builtInPresets + customPresets
    }

    var canDeleteSelectedPreset: Bool {
        selectedPresetID.hasPrefix(Self.customPresetPrefix)
    }

    init(codexQuotaReader: CodexQuotaReader = CodexQuotaReader()) {
        self.codexQuotaReader = codexQuotaReader
        loadPersistedSettings()
        startCodexQuotaPolling()
    }

    deinit {
        codexQuotaPollingTask?.cancel()
    }

    func createProjectSkeleton() {
        guard !isRunning else { return }
        Task { await createProjectSkeletonAsync() }
    }

    func clearStatus() {
        statusLine = nil
    }

    func clearTransientFeedback() {
        clearStatus()
        clearDetailLogs()
        resetPipelineStepStates()
    }

    func copyDetailsToClipboard() {
        guard !detailLogs.isEmpty else { return }
        let text = detailLogs.map { event in
            "[\(event.level.rawValue.uppercased())] \(event.message)"
        }.joined(separator: "\n")
        copyToClipboard(text)
        setStatus(.success, "Copied details.")
    }

    func clearDetailLogs() {
        detailLogs.removeAll()
        isDetailsExpanded = false
        hasFailureDetails = false
    }

    func refreshCodexQuota() {
        Task { await refreshCodexQuotaAsync() }
    }

    func openLastCreatedProjectInXcode() {
        guard let projectURL = lastCreatedProjectURL else { return }
        do {
            try openInXcode(projectURL: projectURL)
        } catch {
            setStatus(.error, error.localizedDescription)
        }
    }

    func revealLastCreatedProjectInFinder() {
        guard let projectURL = lastCreatedProjectURL else { return }
        do {
            try revealInFinder(projectURL: projectURL)
        } catch {
            setStatus(.error, error.localizedDescription)
        }
    }

    func copyLastCreatedProjectPath() {
        guard let projectURL = lastCreatedProjectURL else { return }
        copyToClipboard(projectURL.path)
        setStatus(.success, "Copied project path.")
    }

    func selectPresetFromPicker(_ presetID: String) {
        selectedPresetID = presetID
        applySelectedPreset(showStatus: false)
    }

    func applySelectedPreset(showStatus: Bool = true) {
        guard let preset = preset(withID: selectedPresetID) else {
            setStatus(.error, "Choose a valid preset before applying.")
            return
        }
        applyPreset(preset)
        if showStatus {
            setStatus(.success, "Applied preset: \(preset.name)")
        }
    }

    func saveCurrentAsPreset() {
        let name = newPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            setStatus(.error, "Enter a preset name before saving.")
            return
        }

        if let existingIndex = customPresets.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            customPresets[existingIndex] = currentPreset(id: customPresets[existingIndex].id, name: name)
            selectedPresetID = customPresets[existingIndex].id
            setStatus(.success, "Updated preset: \(name)")
        } else {
            let id = Self.customPresetPrefix + UUID().uuidString.lowercased()
            let preset = currentPreset(id: id, name: name)
            customPresets.append(preset)
            customPresets.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            selectedPresetID = id
            setStatus(.success, "Saved preset: \(name)")
        }

        newPresetName = ""
    }

    func deleteSelectedPreset() {
        guard canDeleteSelectedPreset else {
            setStatus(.error, "Built-in presets cannot be deleted.")
            return
        }

        guard let index = customPresets.firstIndex(where: { $0.id == selectedPresetID }) else { return }
        let removed = customPresets.remove(at: index)
        selectedPresetID = Self.defaultPresetID
        setStatus(.success, "Deleted preset: \(removed.name)")
    }

    func retryGitHubSetup() {
        guard !isRunning else { return }
        guard let name = pendingGitHubRetryName,
              let path = pendingGitHubRetryPath else {
            setStatus(.error, "No pending GitHub step to retry.")
            return
        }

        Task {
            await retryGitHubSetupAsync(name: name,
                                        projectURL: URL(fileURLWithPath: path, isDirectory: true))
        }
    }

    // MARK: - Codex Quota

    private func startCodexQuotaPolling() {
        codexQuotaPollingTask?.cancel()
        codexQuotaPollingTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshCodexQuotaAsync()

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(Self.codexQuotaPollIntervalSeconds))
                } catch {
                    break
                }
                await self.refreshCodexQuotaAsync()
            }
        }
    }

    private func refreshCodexQuotaAsync() async {
        do {
            let snapshot = try await codexQuotaReader.readLatestQuotaSnapshot()
            codexQuotaSnapshot = snapshot
            codexQuotaLastUpdatedAt = Date()
            codexQuotaError = nil
        } catch let error as CodexQuotaReader.ReadError {
            codexQuotaError = error.localizedDescription
        } catch {
            codexQuotaError = "Unable to read Codex quota from local session data."
        }
    }

    // MARK: - Pipeline

    private func createProjectSkeletonAsync() async {
        let name = sanitizedProjectName
        if let validationError = firstValidationErrorMessage {
            setStatus(.error, validationError)
            return
        }

        let templateProfile = selectedTemplateProfile

        let rootURL = projectRootURL.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            setStatus(.error, "Project location is missing. Choose an existing folder.")
            return
        }

        let projectURL = rootURL.appendingPathComponent(name, isDirectory: true)

        isRunning = true
        defer { isRunning = false }

        do {
            clearDetailLogs()
            resetPipelineStepStates()
            appendDetailLog(.info, "Starting scaffold for \(name)")
            hasFailureDetails = false

            clearPendingGitHubRetry()
            lastCreatedGitHubRepoURL = nil

            try runPipelineStep(.folder, statusMessage: "Creating folder…") {
                try createFolder(projectURL)
            }

            try runPipelineStep(.xcodeproj, statusMessage: "Generating Xcode project…") {
                let typeName = sanitizeTypeName(name)
                try createXcodeProjectFromTemplate(projectName: typeName,
                                                   at: projectURL,
                                                   templateProfile: templateProfile)
            }

            try runPipelineStep(.git, statusMessage: "Initializing git…") {
                // Git ignore (before first commit).
                try writeGitignoreIfNeeded(at: projectURL)

                // Ensure the local default branch is `main`.
                // (`git init -b main` is supported on modern Git; we still defensively rename below.)
                _ = try runInDirectory(projectURL, ["/usr/bin/git", "init", "-b", "main"])
                _ = try? runInDirectory(projectURL, ["/usr/bin/git", "branch", "-M", "main"])
                _ = try runInDirectory(projectURL, ["/usr/bin/git", "add", "-A"])
                _ = try? runInDirectory(projectURL, ["/usr/bin/git", "commit", "-m", "Initial commit"])
            }

            var gitHubErrorMessage: String? = nil
            var repoURLForChecklist: String? = nil

            if createGitHubRepo {
                do {
                    try runPipelineStep(.github, statusMessage: "Creating GitHub repo…") {
                        repoURLForChecklist = try setupGitHubRepo(name: name, projectURL: projectURL)
                    }
                    lastCreatedGitHubRepoURL = repoURLForChecklist
                } catch {
                    setPendingGitHubRetry(name: name, projectURL: projectURL)
                    gitHubErrorMessage = "GitHub step failed: \(error.localizedDescription)"
                    appendDetailLog(.error, gitHubErrorMessage ?? "GitHub step failed.")
                }
            } else {
                setPipelineStep(.github, to: .skipped)
                appendDetailLog(.info, "Skipping GitHub repo step.")
            }

            if let openStatusMessage = Self.openStepStatusMessage(openInXcode: openInXcodeAfterCreate,
                                                                  openInCodex: openInCodexAfterCreate,
                                                                  openInCLI: openInCLIAfterCreate) {
                try runPipelineStep(.open, statusMessage: openStatusMessage) {
                    if openInXcodeAfterCreate {
                        try openInXcode(projectURL: projectURL)
                    }
                    if openInCodexAfterCreate {
                        try openInCodex(projectURL: projectURL)
                    }
                    if openInCLIAfterCreate {
                        try openInCLI(projectURL: projectURL)
                    }
                }
            } else {
                setPipelineStep(.open, to: .skipped)
            }

            if revealInFinderAfterCreate {
                try revealInFinder(projectURL: projectURL)
            }
            if openGitHubRepoInSafariAfterCreate, let repoURL = repoURLForChecklist, !repoURL.isEmpty {
                try openGitHubRepoInSafari(repoURL)
            }

            if let gitHubErrorMessage {
                setStatus(.error, "\(gitHubErrorMessage) Use Retry GitHub to continue.")
                return
            }

            lastCreatedProjectURL = projectURL
            resetCreateFormFields()
            setStatus(.success, "Done ✅")
            appendDetailLog(.success, "Project created at \(projectURL.path)")
            try? await Task.sleep(nanoseconds: 700_000_000)
            clearStatus()
        } catch {
            appendDetailLog(.error, error.localizedDescription)
            setStatus(.error, error.localizedDescription)
        }
    }

    private func createFolder(_ url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            throw PPError("Folder already exists: \(url.lastPathComponent)")
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func resetCreateFormFields() {
        projectName = ""
        iOSBundleIdentifier = ""
        macOSBundleIdentifier = ""
        tvOSBundleIdentifier = ""
        newPresetName = ""
    }

    // MARK: - Project location

    var projectRootPathDisplay: String {
        (projectRootURL.path as NSString).abbreviatingWithTildeInPath
    }

    func chooseProjectRootFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = projectRootURL
        panel.message = "Choose where new projects should be created."
        panel.prompt = "Choose"
        let app = NSApplication.shared
        app.activate(ignoringOtherApps: true)

        if let targetWindow = app.keyWindow ?? app.windows.first(where: { $0.isVisible }) {
            panel.beginSheetModal(for: targetWindow) { response in
                guard response == .OK, let selectedURL = panel.url else { return }
                self.projectRootURL = selectedURL.standardizedFileURL
            }
            return
        }

        panel.level = .popUpMenu
        if panel.runModal() == .OK, let selectedURL = panel.url {
            projectRootURL = selectedURL.standardizedFileURL
        }
    }

    private func retryGitHubSetupAsync(name: String, projectURL: URL) async {
        isRunning = true
        defer { isRunning = false }

        var failureContext = "GitHub retry"
        do {
            hasFailureDetails = false
            try runPipelineStep(.github, statusMessage: "Retrying GitHub repo setup…") {
                lastCreatedGitHubRepoURL = try setupGitHubRepo(name: name, projectURL: projectURL)
            }
            clearPendingGitHubRetry()

            if openGitHubRepoInSafariAfterCreate, let repoURL = lastCreatedGitHubRepoURL, !repoURL.isEmpty {
                failureContext = "Opening Safari"
                try openGitHubRepoInSafari(repoURL)
            }

            appendDetailLog(.success, "GitHub retry succeeded.")
            setStatus(.success, "GitHub setup completed.")
            try? await Task.sleep(nanoseconds: 900_000_000)
            clearStatus()
        } catch {
            if failureContext == "GitHub retry" {
                appendDetailLog(.error, "GitHub retry failed: \(error.localizedDescription)")
                setStatus(.error, "GitHub retry failed: \(error.localizedDescription)")
            } else {
                appendDetailLog(.error, "\(failureContext) failed: \(error.localizedDescription)")
                setStatus(.error, "\(failureContext) failed: \(error.localizedDescription)")
            }
        }
    }

    private func setPendingGitHubRetry(name: String, projectURL: URL) {
        pendingGitHubRetryName = name
        pendingGitHubRetryPath = projectURL.path
    }

    private func clearPendingGitHubRetry() {
        pendingGitHubRetryName = nil
        pendingGitHubRetryPath = nil
    }

    private func copyToClipboard(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }

    private var firstValidationErrorMessage: String? {
        if isProjectNameInvalid {
            return projectNameValidationHint ?? "Enter a valid project name."
        }
        return nil
    }

    private func setPipelineStep(_ step: PipelineStep, to state: PipelineStepState) {
        pipelineStepStates[step] = state
    }

    private func resetPipelineStepStates() {
        pipelineStepStates = Self.defaultPipelineStepStates()
    }

    private func runPipelineStep(_ step: PipelineStep,
                                 statusMessage: String,
                                 action: () throws -> Void) throws {
        setPipelineStep(step, to: .inProgress)
        setStatus(.info, statusMessage)

        do {
            try action()
            setPipelineStep(step, to: .success)
        } catch {
            setPipelineStep(step, to: .failure)
            throw error
        }
    }

    private func appendDetailLog(_ level: LogEvent.Level, _ message: String) {
        let compact = compactLogMessage(message)
        guard !compact.isEmpty else { return }
        detailLogs.append(LogEvent(level: level, message: compact))
        if detailLogs.count > 220 {
            detailLogs.removeFirst(detailLogs.count - 220)
        }
    }

    private func compactLogMessage(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let maxLength = 1200
        if trimmed.count <= maxLength {
            return trimmed
        }
        let end = trimmed.index(trimmed.startIndex, offsetBy: maxLength)
        return String(trimmed[..<end]) + "\n…(truncated)…"
    }

    private func isValidSwiftTypeName(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        guard let first = value.unicodeScalars.first else { return false }
        let validFirst = CharacterSet.letters.union(CharacterSet(charactersIn: "_"))
        guard validFirst.contains(first) else { return false }

        let validRest = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        return value.unicodeScalars.allSatisfy { validRest.contains($0) }
    }

    private func containsAlphanumeric(_ value: String) -> Bool {
        value.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
    }

    private func bundleValidationHint(value: String, platform: Platform) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if selectedPlatforms.contains(platform) {
                return "Blank uses default: dn.<project-name>."
            }
            return nil
        }

        if isBundleIdentifierInvalid(trimmed) {
            return "Use reverse-DNS format, e.g. com.example.app."
        }

        return nil
    }

    private func isBundleIdentifierInvalid(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let pattern = "^[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)+$"
        let range = NSRange(location: 0, length: trimmed.utf16.count)
        let regex = try? NSRegularExpression(pattern: pattern)
        return regex?.firstMatch(in: trimmed, range: range) == nil
    }

    // MARK: - Xcode Project Generation (Template .xcodeproj)

    /// Generates a multi-platform SwiftUI project whose **Xcode project settings** match the provided
    /// `ExampleProjectFile.xcodeproj` template.
    ///
    /// Notes:
    /// - This template uses Xcode's *file system synchronized groups* (PBXFileSystemSynchronizedRootGroup),
    ///   so we don't need to enumerate every Swift file in the pbxproj.
    /// - The only intended customization is the **project name**.
    private func createXcodeProjectFromTemplate(projectName: String,
                                                at projectURL: URL,
                                                templateProfile: TemplateProfile) throws {
        // Folder layout expected by the template.
        let appFolderURL = projectURL.appendingPathComponent(projectName, isDirectory: true)
        let unitTestsURL = projectURL.appendingPathComponent("\(projectName)Tests", isDirectory: true)
        let uiTestsURL = projectURL.appendingPathComponent("\(projectName)UITests", isDirectory: true)

        try FileManager.default.createDirectory(at: appFolderURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: unitTestsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: uiTestsURL, withIntermediateDirectories: true)

        // Project README
        try writeIfMissing(url: projectURL.appendingPathComponent("README.md"),
                           contents: readmeTemplate(projectName: projectName, templateProfile: templateProfile))
        try writeIfMissing(url: projectURL.appendingPathComponent("AGENTS.md"),
                           contents: agentsTemplate())
        try writeIfMissing(url: projectURL.appendingPathComponent("AGENTS.project.md"),
                           contents: projectAgentsTemplate(projectName: projectName))
        try writeCIWorkflowIfNeeded(projectName: projectName, at: projectURL)

        // App sources
        try writeIfMissing(url: appFolderURL.appendingPathComponent("\(projectName)App.swift"),
                           contents: multiplatformAppTemplate(projectName: projectName))
        try writeIfMissing(url: appFolderURL.appendingPathComponent("ContentView.swift"),
                           contents: contentTemplate(for: templateProfile, projectName: projectName))
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

    func supportedPlatformsBuildSettingValue() -> String {
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

        return platforms.joined(separator: " ")
    }

    static func ciDestination(for platforms: Set<Platform>) -> String {
        if platforms.contains(.macOS) {
            return "platform=macOS"
        }
        if platforms.contains(.iOS) {
            return "platform=iOS Simulator"
        }
        return "platform=tvOS Simulator"
    }

    static func openStepStatusMessage(openInXcode: Bool, openInCodex: Bool, openInCLI: Bool) -> String? {
        var targets: [String] = []
        if openInXcode { targets.append("Xcode") }
        if openInCodex { targets.append("Codex") }
        if openInCLI { targets.append("CLI") }

        guard !targets.isEmpty else { return nil }
        if targets.count == 1 {
            return "Opening in \(targets[0])…"
        }
        if targets.count == 2 {
            return "Opening in \(targets[0]) and \(targets[1])…"
        }
        return "Opening in \(targets[0]), \(targets[1]), and \(targets[2])…"
    }

    nonisolated static func codexQuotaSnapshot(fromRolloutJSONLines text: String, sourcePath: String = "") -> CodexQuotaSnapshot? {
        for rawLine in text.split(whereSeparator: \.isNewline).reversed() {
            let line = String(rawLine)
            guard line.contains("\"token_count\""), line.contains("\"rate_limits\"") else { continue }
            guard let data = line.data(using: .utf8),
                  let rawJSON = try? JSONSerialization.jsonObject(with: data),
                  let event = rawJSON as? [String: Any],
                  (event["type"] as? String) == "event_msg",
                  let payload = event["payload"] as? [String: Any],
                  (payload["type"] as? String) == "token_count",
                  let rateLimits = payload["rate_limits"] as? [String: Any] else {
                continue
            }

            return CodexQuotaSnapshot(
                primary: codexUsageLimit(from: rateLimits["primary"] as? [String: Any]),
                secondary: codexUsageLimit(from: rateLimits["secondary"] as? [String: Any]),
                credits: codexCredits(from: rateLimits["credits"] as? [String: Any]),
                sourcePath: sourcePath
            )
        }

        return nil
    }

    nonisolated private static func codexUsageLimit(from usageWindow: [String: Any]?) -> CodexQuotaSnapshot.UsageLimit? {
        guard let usageWindow else { return nil }
        let usedPercent = clampedPercentage(codexDouble(from: usageWindow["used_percent"]) ?? 0)
        let remainingPercent = clampedPercentage(100 - usedPercent)
        let windowMinutes = max(0, codexInt(from: usageWindow["window_minutes"]) ?? 0)
        let resetAt = codexDouble(from: usageWindow["resets_at"]).map { Date(timeIntervalSince1970: $0) }
        return CodexQuotaSnapshot.UsageLimit(
            usedPercent: usedPercent,
            remainingPercent: remainingPercent,
            windowMinutes: windowMinutes,
            resetAt: resetAt
        )
    }

    nonisolated private static func codexCredits(from credits: [String: Any]?) -> CodexQuotaSnapshot.Credits? {
        guard let credits else { return nil }
        return CodexQuotaSnapshot.Credits(
            hasCredits: codexBool(from: credits["has_credits"]) ?? false,
            isUnlimited: codexBool(from: credits["unlimited"]) ?? false,
            balance: codexDouble(from: credits["balance"])
        )
    }

    nonisolated private static func clampedPercentage(_ value: Double) -> Double {
        min(100, max(0, value))
    }

    nonisolated private static func codexDouble(from value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let string = value as? String {
            return Double(string)
        }
        return nil
    }

    nonisolated private static func codexInt(from value: Any?) -> Int? {
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let string = value as? String {
            return Int(string)
        }
        return nil
    }

    nonisolated private static func codexBool(from value: Any?) -> Bool? {
        if let bool = value as? Bool {
            return bool
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        if let string = value as? String {
            switch string.lowercased() {
            case "true", "1": return true
            case "false", "0": return false
            default: return nil
            }
        }
        return nil
    }

    private func applySupportedPlatforms(to pbxproj: String) -> String {
        let joined = supportedPlatformsBuildSettingValue()
        return pbxproj.replacingOccurrences(of: "SUPPORTED_PLATFORMS = \"iphoneos iphonesimulator macosx\";",
                                            with: "SUPPORTED_PLATFORMS = \"\(joined)\";")
    }

    private func applyBundleIdentifiers(projectName: String, to pbxproj: String) -> String {
        let base = defaultBundleIdentifier(projectName: projectName)
        let tests = "\(base)Tests"
        let uiTests = "\(base)UITests"
        let baseSettingValue = quotedPbxprojBuildSettingValue(base)
        let testsSettingValue = quotedPbxprojBuildSettingValue(tests)
        let uiTestsSettingValue = quotedPbxprojBuildSettingValue(uiTests)

        var updated = pbxproj

        // First, replace template defaults.
        updated = updated.replacingOccurrences(of: "PRODUCT_BUNDLE_IDENTIFIER = dn.\(projectName);",
                                              with: "PRODUCT_BUNDLE_IDENTIFIER = \(baseSettingValue);")
        updated = updated.replacingOccurrences(of: "PRODUCT_BUNDLE_IDENTIFIER = dn.\(projectName)Tests;",
                                              with: "PRODUCT_BUNDLE_IDENTIFIER = \(testsSettingValue);")
        updated = updated.replacingOccurrences(of: "PRODUCT_BUNDLE_IDENTIFIER = dn.\(projectName)UITests;",
                                              with: "PRODUCT_BUNDLE_IDENTIFIER = \(uiTestsSettingValue);")

        return updated
    }

    private func defaultBundleIdentifier(projectName: String) -> String {
        "dn.\(sanitizeBundleComponent(projectName.lowercased()))"
    }

    private func quotedPbxprojBuildSettingValue(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func writeIfMissing(url: URL, contents: String) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func writeCIWorkflowIfNeeded(projectName: String, at projectURL: URL) throws {
        let workflowDirectoryURL = projectURL
            .appendingPathComponent(".github", isDirectory: true)
            .appendingPathComponent("workflows", isDirectory: true)
        try FileManager.default.createDirectory(at: workflowDirectoryURL, withIntermediateDirectories: true)
        let workflowURL = workflowDirectoryURL.appendingPathComponent("ci.yml")
        try writeIfMissing(url: workflowURL,
                           contents: Self.ciWorkflowTemplate(projectName: projectName,
                                                             platforms: selectedPlatforms))
    }

    static func ciWorkflowTemplate(projectName: String, platforms: Set<Platform>) -> String {
        let destination = ciDestination(for: platforms)
        return """
name: CI

on:
  push:
    branches:
      - main
  pull_request:

jobs:
  build-and-test:
    runs-on: macos-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Resolve test destination
        id: destination
        run: |
          DESTINATION="\(destination)"

          if [[ "$DESTINATION" == "platform=macOS" ]]; then
            echo "value=$DESTINATION" >> "$GITHUB_OUTPUT"
            exit 0
          fi

          if [[ "$DESTINATION" == "platform=iOS Simulator" ]]; then
            DEVICE_ID=$(xcrun simctl list devices available | awk -F '[()]' '/iPhone|iPad/ { print $2; exit }')
          else
            DEVICE_ID=$(xcrun simctl list devices available | awk -F '[()]' '/Apple TV/ { print $2; exit }')
          fi

          if [[ -z "$DEVICE_ID" ]]; then
            echo "No compatible simulator found for $DESTINATION."
            exit 1
          fi

          echo "value=id=$DEVICE_ID" >> "$GITHUB_OUTPUT"

      - name: Build and test
        run: |
          xcodebuild \\
            -project \(projectName).xcodeproj \\
            -scheme \(projectName) \\
            -destination '${{ steps.destination.outputs.value }}' \\
            CODE_SIGNING_ALLOWED=NO \\
            clean test
"""
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

    private func contentTemplate(for templateProfile: TemplateProfile, projectName: String) -> String {
        switch templateProfile {
        case .starterApp:
            return starterContentViewTemplate()
        case .dashboardApp:
            return dashboardContentViewTemplate(projectName: projectName)
        case .utilityTool:
            return utilityToolContentViewTemplate()
        }
    }

    private func starterContentViewTemplate() -> String {
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

    private func dashboardContentViewTemplate(projectName: String) -> String {
        """
import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationSplitView {
            List {
                Label("Overview", systemImage: "rectangle.grid.2x2")
                Label("Tasks", systemImage: "checklist")
                Label("Notes", systemImage: "note.text")
            }
            .navigationTitle("Sections")
        } detail: {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(projectName)")
                    .font(.title2.weight(.semibold))
                Text("Dashboard template is ready for your first feature.")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(20)
        }
    }
}

#Preview {
    ContentView()
}
"""
    }

    private func utilityToolContentViewTemplate() -> String {
        """
import SwiftUI

struct ContentView: View {
    @State private var input: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Utility Tool")
                .font(.title3.weight(.semibold))

            TextField("Paste value...", text: $input)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Run") {}
                Spacer()
                Text("Ready")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(minWidth: 360)
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

    private func readmeTemplate(projectName: String, templateProfile: TemplateProfile) -> String {
        """
# \(projectName)

<p align="center">
  <img src="https://img.shields.io/badge/SwiftUI-app-orange?logo=swift">
  <img src="https://img.shields.io/badge/Platform-multiplatform-blue">
</p>

## Overview
\(projectName) is a SwiftUI app scaffold created by **ProjectPilot**. This README is intentionally minimal and will grow as the project evolves.

- Template profile: **\(templateProfile.title)**

## Requirements
- macOS with Xcode installed
- Swift / SwiftUI

## Getting Started
1. Open `\(projectName).xcodeproj`
2. Select a destination (Mac, iPhone Simulator, etc.)
3. Build and Run

## Project Structure
```text
\(projectName)/
├── \(projectName)/
├── \(projectName)Tests/
└── \(projectName)UITests/
```

## Roadmap
- [ ] Define app goals and core flows
- [ ] Add real UI and data model
- [ ] Add tests for key behaviors

## Credits
Created with **ProjectPilot**.
"""
    }

    private func agentsTemplate() -> String {
        """
# AGENTS.md

This repo is an Apple-platform app codebase. You are an engineering agent (Codex) collaborating with the human. Your job is to make small, correct, testable changes with a clean build at every step.

## Hard requirements (do not violate)
- **No build warnings.** Treat warnings as errors in practice.
- **No large rewrites.** Prefer small, surgical diffs.
- **Apple-native only.** No third-party libraries unless explicitly requested.
- **SwiftUI + MVVM.** Keep UI declarative; isolate logic in view models/services.
- **Concurrency correctness.** Avoid broad `@MainActor` on data models / filesystem / networking types. Use actors/services for isolation.
- **File persistence must be safe.** Use atomic writes where appropriate.
- **Privacy-first.** No unexpected network calls.
- **Preserve core behavior contracts.** Do not regress existing user-visible flows without explicitly calling it out.

## Workflow
1. Read existing code and architecture before editing.
2. Propose a minimal plan in 2-5 bullets.
3. Implement the smallest viable patch.
4. Ensure build passes with **zero warnings**.
5. If tests exist or are touched, run them. Add tests for non-trivial logic.
6. If behavior changed, update docs (`README.md` / `AGENTS.project.md`) in the same patch.

## Code style
- Keep types small and focused.
- Prefer `Foundation` + `OSLog`/structured status over ad-hoc prints.
- Use actors/services for mutable shared state that should not run on the main thread.
- Prefer `@MainActor` only for UI/view models that must touch SwiftUI state.
- Avoid global singletons (unless explicitly designed).
- Keep command execution wrappers deterministic and easy to retry.

## Deliverables for each change
- Mention which files were modified and why.
- Provide a short commit message suggestion.
- Mention any user-visible behavior changes explicitly.

## What not to do
- Don't introduce new dependencies.
- Don't "fix" code by disabling concurrency checks.
- Don't add `@MainActor` broadly to silence warnings.
- Don't change public behavior without stating it.
- Don't hide failures; surface actionable status and retry paths.
- Don't replace plain-language setup guidance with unnecessary jargon.

If something is ambiguous, default to the simplest solution that preserves correctness and forward progress.
"""
    }

    private func projectAgentsTemplate(projectName: String) -> String {
        """
# AGENTS.project.md

# \(projectName) Project Guide for Agents

## Product intent
Describe what this app is for in plain language.
Suggested structure:
- Who the app serves
- The main problem it solves
- The success criteria

## Current product phase (scaffold)
This file is expected to evolve over time.
Update this section as soon as implementation starts.

Starter checklist:
1) Define MVP scope
2) Define architecture boundaries
3) Define reliability and UX goals
4) Define testing priorities

## Architecture snapshot (current)
Capture the current technical shape as it becomes real:
- app entry and navigation model
- core view models/services
- data flow and persistence

## Concurrency rules (important)
Keep rules explicit for this project as they become known.
- keep UI state on the main actor
- keep IO/network work off the main actor
- avoid broad isolation as a shortcut

## Behavior invariants (do not regress)
List critical product contracts once identified.
Examples:
- setup flows
- creation/sync pipelines
- data safety guarantees

## UX rules
Document UX guarantees (copy tone, interactions, failure handling, keyboard flows).

## Coding conventions
Project-specific style or patterns that go beyond AGENTS.md.

## Build/run notes
- target platforms
- warning policy
- local run/test setup notes

## Near-term priorities
Keep this list short and current.

## Output expectations per patch
Provide:
- Summary of change
- Files modified
- Any migration considerations
- Commit message suggestion
"""
    }
    // MARK: - GitHub

    private func setupGitHubRepo(name: String, projectURL: URL) throws -> String? {
        let gh = resolvedGHCommandPrefix()
        let repoName = sanitizeRepoName(name)
        let visibilityFlag = createPublicGitHubRepo ? "--public" : "--private"
        let remoteBranchName = "github"

        // Ensure auth is valid (gives clear error early)
        _ = try runInDirectory(projectURL, gh + ["auth", "status"])

        // Create repo and push.
        // If it already exists, gh will error; we catch and try “set remote + push”.
        do {
            // Use a dedicated remote name for GitHub.
            _ = try runInDirectory(projectURL, gh + ["repo", "create", repoName, visibilityFlag, "--source=.", "--remote=github"])
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
        }

        // Local branch stays "main", remote branch is "github".
        _ = try runInDirectory(projectURL, ["/usr/bin/git", "branch", "-M", "main"])
        _ = try runInDirectory(projectURL, ["/usr/bin/git", "push", "-u", "github", "HEAD:\(remoteBranchName)"])
        _ = try runInDirectory(projectURL, gh + ["repo", "edit", repoName, "--default-branch", remoteBranchName])

        let remoteMainHead = try runInDirectory(
            projectURL,
            ["/usr/bin/git", "ls-remote", "--heads", "github", "refs/heads/main"]
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        if !remoteMainHead.isEmpty {
            do {
                _ = try runInDirectory(projectURL, ["/usr/bin/git", "push", "github", "--delete", "main"])
            } catch {
                throw PPError(
                    "Created remote branch '\(remoteBranchName)' but could not remove remote 'main'. " +
                    "Update default branch to '\(remoteBranchName)' and retry. Details: \(error.localizedDescription)"
                )
            }
        }

        return resolveGitHubRepoURL(repoName: repoName, gh: gh, projectURL: projectURL)
    }

    private func resolveGitHubRepoURL(repoName: String, gh: [String], projectURL: URL) -> String? {
        let out = try? runInDirectory(projectURL, gh + ["repo", "view", repoName, "--json", "url", "-q", ".url"])
        let trimmed = out?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
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

    private func openInCodex(projectURL: URL) throws {
        guard FileManager.default.fileExists(atPath: projectURL.path) else {
            throw PPError("Missing project folder at \(projectURL.lastPathComponent).")
        }
        _ = try run([ "/usr/bin/open", "-b", Self.codexBundleIdentifier, projectURL.path ])
    }

    private func openInCLI(projectURL: URL) throws {
        guard FileManager.default.fileExists(atPath: projectURL.path) else {
            throw PPError("Missing project folder at \(projectURL.lastPathComponent).")
        }
        _ = try run([ "/usr/bin/open", "-a", "Terminal", projectURL.path ])
    }

    private func revealInFinder(projectURL: URL) throws {
        _ = try run(["/usr/bin/open", "-R", projectURL.path])
    }

    private func openGitHubRepoInSafari(_ repoURL: String) throws {
        guard let parsedURL = URL(string: repoURL),
              let scheme = parsedURL.scheme,
              !scheme.isEmpty else {
            throw PPError("Invalid GitHub URL: \(repoURL)")
        }
        _ = try run(["/usr/bin/open", "-a", "Safari", parsedURL.absoluteString])
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
        appendDetailLog(.info, "$ " + ([exe] + args).joined(separator: " "))

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
        let outTrimmed = outStr.trimmingCharacters(in: .whitespacesAndNewlines)
        let errTrimmed = errStr.trimmingCharacters(in: .whitespacesAndNewlines)

        if process.terminationStatus != 0 {
            if !errTrimmed.isEmpty {
                appendDetailLog(.error, errTrimmed)
            }
            if !outTrimmed.isEmpty {
                appendDetailLog(.error, outTrimmed)
            }
            let msg = errTrimmed
            throw PPError(msg.isEmpty ? "Command failed: \(exe) \(args.joined(separator: " "))" : msg)
        }

        if !outTrimmed.isEmpty {
            appendDetailLog(.info, outTrimmed)
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
        if level == .error {
            hasFailureDetails = true
            isDetailsExpanded = true
        }
        statusLine = StatusLine(level: level, message: message)
    }

    // MARK: - Presets

    private func preset(withID id: String) -> CreationPreset? {
        availablePresets.first(where: { $0.id == id })
    }

    private func applyPreset(_ preset: CreationPreset) {
        selectedTemplateProfile = preset.templateProfile
        selectedPlatforms = preset.platforms.isEmpty ? [.macOS] : preset.platforms
        iOSBundleIdentifier = preset.iOSBundleIdentifier
        macOSBundleIdentifier = preset.macOSBundleIdentifier
        tvOSBundleIdentifier = preset.tvOSBundleIdentifier
        createGitHubRepo = preset.createGitHubRepo
        createPublicGitHubRepo = preset.createPublicGitHubRepo
    }

    private func currentPreset(id: String, name: String) -> CreationPreset {
        CreationPreset(
            id: id,
            name: name,
            templateProfile: selectedTemplateProfile,
            platforms: selectedPlatforms,
            iOSBundleIdentifier: iOSBundleIdentifier,
            macOSBundleIdentifier: macOSBundleIdentifier,
            tvOSBundleIdentifier: tvOSBundleIdentifier,
            createGitHubRepo: createGitHubRepo,
            createPublicGitHubRepo: createPublicGitHubRepo
        )
    }

    private func resolveSelectedPresetIDAfterLoad() {
        if preset(withID: selectedPresetID) != nil {
            return
        }
        selectedPresetID = Self.defaultPresetID
    }

    // MARK: - Persistence

    private func loadPersistedSettings() {
        let defaults = UserDefaults.standard

        if let rootPath = defaults.string(forKey: Self.StorageKey.projectRootPath) {
            projectRootURL = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL
        }

        if let values = defaults.array(forKey: Self.StorageKey.selectedPlatforms) as? [String] {
            let parsed = Set(values.compactMap(Platform.init(rawValue:)))
            if !parsed.isEmpty {
                selectedPlatforms = parsed
            }
        }

        clearLegacyPersistedBundleIdentifiers(defaults: defaults)

        if let rawProfile = defaults.string(forKey: Self.StorageKey.templateProfile),
           let profile = TemplateProfile(rawValue: rawProfile) {
            selectedTemplateProfile = profile
        }

        if defaults.object(forKey: Self.StorageKey.createGitHubRepo) != nil {
            createGitHubRepo = defaults.bool(forKey: Self.StorageKey.createGitHubRepo)
        }
        if defaults.object(forKey: Self.StorageKey.createPublicGitHubRepo) != nil {
            createPublicGitHubRepo = defaults.bool(forKey: Self.StorageKey.createPublicGitHubRepo)
        }

        if defaults.object(forKey: Self.StorageKey.openInXcodeAfterCreate) != nil {
            openInXcodeAfterCreate = defaults.bool(forKey: Self.StorageKey.openInXcodeAfterCreate)
        }
        if defaults.object(forKey: Self.StorageKey.openInCodexAfterCreate) != nil {
            openInCodexAfterCreate = defaults.bool(forKey: Self.StorageKey.openInCodexAfterCreate)
        }
        if defaults.object(forKey: Self.StorageKey.openInCLIAfterCreate) != nil {
            openInCLIAfterCreate = defaults.bool(forKey: Self.StorageKey.openInCLIAfterCreate)
        }
        if defaults.object(forKey: Self.StorageKey.revealInFinderAfterCreate) != nil {
            revealInFinderAfterCreate = defaults.bool(forKey: Self.StorageKey.revealInFinderAfterCreate)
        }
        if defaults.object(forKey: Self.StorageKey.openGitHubRepoInSafariAfterCreate) != nil {
            openGitHubRepoInSafariAfterCreate = defaults.bool(forKey: Self.StorageKey.openGitHubRepoInSafariAfterCreate)
        }

        if let data = defaults.data(forKey: Self.StorageKey.customPresets),
           let decoded = try? JSONDecoder().decode([CreationPreset].self, from: data) {
            customPresets = decoded
        }

        if let presetID = defaults.string(forKey: Self.StorageKey.selectedPresetID) {
            selectedPresetID = presetID
        }

        resolveSelectedPresetIDAfterLoad()
    }

    private func persistProjectRootURL() {
        UserDefaults.standard.set(projectRootURL.path, forKey: Self.StorageKey.projectRootPath)
    }

    private func persistSelectedPlatforms() {
        let values = selectedPlatforms.map(\.rawValue).sorted()
        UserDefaults.standard.set(values, forKey: Self.StorageKey.selectedPlatforms)
    }

    private func persistBundleIdentifiers() {
        // Bundle IDs are per-scaffold inputs and intentionally not persisted globally.
    }

    private func clearLegacyPersistedBundleIdentifiers(defaults: UserDefaults) {
        defaults.removeObject(forKey: Self.StorageKey.iOSBundleIdentifier)
        defaults.removeObject(forKey: Self.StorageKey.macOSBundleIdentifier)
        defaults.removeObject(forKey: Self.StorageKey.tvOSBundleIdentifier)
    }

    private func persistTemplateProfile() {
        UserDefaults.standard.set(selectedTemplateProfile.rawValue, forKey: Self.StorageKey.templateProfile)
    }

    private func persistGitHubSettings() {
        let defaults = UserDefaults.standard
        defaults.set(createGitHubRepo, forKey: Self.StorageKey.createGitHubRepo)
        defaults.set(createPublicGitHubRepo, forKey: Self.StorageKey.createPublicGitHubRepo)
    }

    private func persistPostCreateSettings() {
        let defaults = UserDefaults.standard
        defaults.set(openInXcodeAfterCreate, forKey: Self.StorageKey.openInXcodeAfterCreate)
        defaults.set(openInCodexAfterCreate, forKey: Self.StorageKey.openInCodexAfterCreate)
        defaults.set(openInCLIAfterCreate, forKey: Self.StorageKey.openInCLIAfterCreate)
        defaults.set(revealInFinderAfterCreate, forKey: Self.StorageKey.revealInFinderAfterCreate)
        defaults.set(openGitHubRepoInSafariAfterCreate, forKey: Self.StorageKey.openGitHubRepoInSafariAfterCreate)
    }

    private func persistCustomPresets() {
        if let data = try? JSONEncoder().encode(customPresets) {
            UserDefaults.standard.set(data, forKey: Self.StorageKey.customPresets)
        }
    }

    private func persistSelectedPresetID() {
        UserDefaults.standard.set(selectedPresetID, forKey: Self.StorageKey.selectedPresetID)
    }

    // MARK: - Defaults

    private enum StorageKey {
        static let projectRootPath = "projectPilot.projectRootPath"
        static let selectedPlatforms = "projectPilot.selectedPlatforms"
        static let iOSBundleIdentifier = "projectPilot.iOSBundleIdentifier"
        static let macOSBundleIdentifier = "projectPilot.macOSBundleIdentifier"
        static let tvOSBundleIdentifier = "projectPilot.tvOSBundleIdentifier"
        static let templateProfile = "projectPilot.templateProfile"
        static let createGitHubRepo = "projectPilot.createGitHubRepo"
        static let createPublicGitHubRepo = "projectPilot.createPublicGitHubRepo"
        static let openInXcodeAfterCreate = "projectPilot.openInXcodeAfterCreate"
        static let openInCodexAfterCreate = "projectPilot.openInCodexAfterCreate"
        static let openInCLIAfterCreate = "projectPilot.openInCLIAfterCreate"
        static let revealInFinderAfterCreate = "projectPilot.revealInFinderAfterCreate"
        static let openGitHubRepoInSafariAfterCreate = "projectPilot.openGitHubRepoInSafariAfterCreate"
        static let customPresets = "projectPilot.customPresets"
        static let selectedPresetID = "projectPilot.selectedPresetID"
    }

    private static let codexBundleIdentifier = "com.openai.codex"
    private static let codexQuotaPollIntervalSeconds: Double = 10

    private static func defaultPipelineStepStates() -> [PipelineStep: PipelineStepState] {
        var states: [PipelineStep: PipelineStepState] = [:]
        PipelineStep.allCases.forEach { states[$0] = .pending }
        return states
    }

    private static let customPresetPrefix = "custom."
    private static let defaultPresetID = "builtin.ios-app"

    private static let builtInPresets: [CreationPreset] = [
        CreationPreset(
            id: "builtin.ios-app",
            name: "iOS App",
            templateProfile: .starterApp,
            platforms: [.iOS],
            iOSBundleIdentifier: "",
            macOSBundleIdentifier: "",
            tvOSBundleIdentifier: "",
            createGitHubRepo: true,
            createPublicGitHubRepo: false
        ),
        CreationPreset(
            id: "builtin.macos-tool",
            name: "macOS Tool",
            templateProfile: .utilityTool,
            platforms: [.macOS],
            iOSBundleIdentifier: "",
            macOSBundleIdentifier: "",
            tvOSBundleIdentifier: "",
            createGitHubRepo: true,
            createPublicGitHubRepo: false
        ),
        CreationPreset(
            id: "builtin.multiplatform-dashboard",
            name: "Multiplatform Dashboard",
            templateProfile: .dashboardApp,
            platforms: [.iOS, .macOS, .tvOS],
            iOSBundleIdentifier: "",
            macOSBundleIdentifier: "",
            tvOSBundleIdentifier: "",
            createGitHubRepo: true,
            createPublicGitHubRepo: false
        ),
    ]

    private static func defaultProjectRootURL() -> URL {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let development = home.appendingPathComponent("Development", isDirectory: true)

        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: development.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return development
        }

        return home
    }

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
                ENABLE_APP_INTENTS_METADATA_GENERATION = NO;
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
                ENABLE_APP_INTENTS_METADATA_GENERATION = NO;
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
                ENABLE_APP_INTENTS_METADATA_GENERATION = NO;
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
                ENABLE_APP_INTENTS_METADATA_GENERATION = NO;
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
                ENABLE_APP_INTENTS_METADATA_GENERATION = NO;
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
                ENABLE_APP_INTENTS_METADATA_GENERATION = NO;
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

actor CodexQuotaReader {
    enum ReadError: LocalizedError {
        case sessionsDirectoryMissing
        case noRolloutFiles
        case noQuotaData
        case unreadableRolloutFile

        var errorDescription: String? {
            switch self {
            case .sessionsDirectoryMissing:
                return "Codex sessions folder not found at ~/.codex/sessions."
            case .noRolloutFiles:
                return "No Codex usage data found yet."
            case .noQuotaData:
                return "No Codex quota update found yet. Send a Codex message first."
            case .unreadableRolloutFile:
                return "Unable to read Codex usage data."
            }
        }
    }

    private let fileManager: FileManager
    private let sessionsRootURL: URL

    private var cachedRolloutURL: URL? = nil
    private var cachedRolloutModificationDate: Date? = nil
    private var cachedSnapshot: ProjectPilotViewModel.CodexQuotaSnapshot? = nil

    init(fileManager: FileManager = .default, sessionsRootURL: URL? = nil) {
        self.fileManager = fileManager
        self.sessionsRootURL = sessionsRootURL ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
    }

    func readLatestQuotaSnapshot() throws -> ProjectPilotViewModel.CodexQuotaSnapshot {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sessionsRootURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ReadError.sessionsDirectoryMissing
        }

        guard let (rolloutURL, modificationDate) = latestRolloutFile() else {
            throw ReadError.noRolloutFiles
        }

        if rolloutURL == cachedRolloutURL,
           modificationDate == cachedRolloutModificationDate,
           let cachedSnapshot {
            return cachedSnapshot
        }

        let rolloutTail = try readTail(of: rolloutURL, maxBytes: 128 * 1024)
        guard let snapshot = ProjectPilotViewModel.codexQuotaSnapshot(fromRolloutJSONLines: rolloutTail,
                                                                      sourcePath: rolloutURL.path) else {
            throw ReadError.noQuotaData
        }

        cachedRolloutURL = rolloutURL
        cachedRolloutModificationDate = modificationDate
        cachedSnapshot = snapshot
        return snapshot
    }

    private func latestRolloutFile() -> (URL, Date)? {
        guard let enumerator = fileManager.enumerator(
            at: sessionsRootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var bestMatch: (url: URL, modifiedAt: Date)? = nil

        for case let fileURL as URL in enumerator {
            guard fileURL.lastPathComponent.hasPrefix("rollout-"),
                  fileURL.pathExtension == "jsonl" else {
                continue
            }

            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                  values.isRegularFile == true else {
                continue
            }

            let modifiedAt = values.contentModificationDate ?? .distantPast
            if let currentBest = bestMatch {
                if modifiedAt > currentBest.modifiedAt {
                    bestMatch = (fileURL, modifiedAt)
                }
            } else {
                bestMatch = (fileURL, modifiedAt)
            }
        }

        guard let bestMatch else { return nil }
        return (bestMatch.url, bestMatch.modifiedAt)
    }

    private func readTail(of fileURL: URL, maxBytes: Int) throws -> String {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: fileURL)
        } catch {
            throw ReadError.unreadableRolloutFile
        }

        defer { try? handle.close() }

        let fileSize: UInt64
        do {
            fileSize = try handle.seekToEnd()
        } catch {
            throw ReadError.unreadableRolloutFile
        }

        let startOffset = fileSize > UInt64(maxBytes) ? fileSize - UInt64(maxBytes) : 0

        do {
            try handle.seek(toOffset: startOffset)
        } catch {
            throw ReadError.unreadableRolloutFile
        }

        let data = handle.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else {
            throw ReadError.unreadableRolloutFile
        }
        return text
    }
}
