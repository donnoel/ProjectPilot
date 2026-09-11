import Foundation

nonisolated struct SystemHealthThresholds: Equatable, Sendable {
    let minimumFreeDiskBytes: Int64
    let minimumFreeDiskFraction: Double
    let maximumXcodeAndSimulatorBytes: Int64
    let maximumDockerBytes: Int64
    let maximumBackupAge: TimeInterval

    static let standard = SystemHealthThresholds(
        minimumFreeDiskBytes: 20 * 1_024 * 1_024 * 1_024,
        minimumFreeDiskFraction: 0.10,
        maximumXcodeAndSimulatorBytes: 50 * 1_024 * 1_024 * 1_024,
        maximumDockerBytes: 40 * 1_024 * 1_024 * 1_024,
        maximumBackupAge: 24 * 60 * 60
    )
}

nonisolated struct SystemHealthWarning: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case lowDisk
        case developerStorage
        case dockerStorage
        case backup
        case requiredTool
        case checkFailed
    }

    enum Severity: Equatable, Sendable {
        case warning
        case critical
    }

    let kind: Kind
    let severity: Severity
    let title: String
    let detail: String

    var id: String { "\(kind.rawValue):\(title)" }
}

nonisolated struct SystemHealthSnapshot: Equatable, Sendable {
    let warnings: [SystemHealthWarning]
    let checkedAt: Date
}

nonisolated enum SystemHealthChecker {
    static func check(
        backupStatus: ProjectPilotViewModel.DevelopmentBackupStatus,
        thresholds: SystemHealthThresholds = .standard,
        now: Date = Date()
    ) -> SystemHealthSnapshot {
        var warnings: [SystemHealthWarning] = []
        let fileManager = FileManager.default
        let homeURL = fileManager.homeDirectoryForCurrentUser

        do {
            let values = try homeURL.resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeTotalCapacityKey
            ])
            guard let available = values.volumeAvailableCapacityForImportantUsage,
                  let total = values.volumeTotalCapacity else {
                throw HealthCheckError("macOS did not report available and total disk capacity.")
            }
            if let warning = diskWarning(
                availableBytes: available,
                totalBytes: Int64(total),
                thresholds: thresholds
            ) {
                warnings.append(warning)
            }
        } catch {
            warnings.append(checkFailureWarning(check: "Disk space", error: error))
        }

        let developerPaths = [
            homeURL.appendingPathComponent("Library/Developer/Xcode", isDirectory: true),
            homeURL.appendingPathComponent("Library/Developer/CoreSimulator", isDirectory: true)
        ]
        do {
            let size = try developerPaths.reduce(Int64(0)) { partial, url in
                partial + (try allocatedSize(at: url))
            }
            if let warning = storageWarning(
                kind: .developerStorage,
                title: "Xcode and Simulator storage is large",
                sizeBytes: size,
                limitBytes: thresholds.maximumXcodeAndSimulatorBytes
            ) {
                warnings.append(warning)
            }
        } catch {
            warnings.append(checkFailureWarning(check: "Xcode and Simulator storage", error: error))
        }

        if let dockerExecutable = existingExecutable(named: "docker"),
           dockerIsAvailable(executable: dockerExecutable) {
            do {
                let output = try ProjectPilotViewModel.runProcess(
                    [dockerExecutable, "system", "df", "--format", "{{json .}}"],
                    timeoutSeconds: 15
                )
                let size = try dockerStorageBytes(from: output)
                if let warning = storageWarning(
                    kind: .dockerStorage,
                    title: "Docker storage is large",
                    sizeBytes: size,
                    limitBytes: thresholds.maximumDockerBytes
                ) {
                    warnings.append(warning)
                }
            } catch {
                warnings.append(checkFailureWarning(check: "Docker storage", error: error))
            }
        }

        warnings.append(contentsOf: backupWarnings(
            status: backupStatus,
            now: now,
            thresholds: thresholds
        ))

        for tool in requiredTools where existingExecutable(named: tool.executableName) == nil {
            warnings.append(SystemHealthWarning(
                kind: .requiredTool,
                severity: .critical,
                title: "\(tool.displayName) is unavailable",
                detail: "ProjectPilot requires the \(tool.executableName) command, but it was not found in the standard tool locations."
            ))
        }

        return SystemHealthSnapshot(warnings: warnings, checkedAt: now)
    }

    static func diskWarning(
        availableBytes: Int64,
        totalBytes: Int64,
        thresholds: SystemHealthThresholds
    ) -> SystemHealthWarning? {
        guard totalBytes > 0 else {
            return checkFailureWarning(
                check: "Disk space",
                error: HealthCheckError("macOS reported a total capacity of zero bytes.")
            )
        }
        let fraction = Double(availableBytes) / Double(totalBytes)
        guard availableBytes < thresholds.minimumFreeDiskBytes || fraction < thresholds.minimumFreeDiskFraction else {
            return nil
        }

        let percent = fraction.formatted(.percent.precision(.fractionLength(0)))
        return SystemHealthWarning(
            kind: .lowDisk,
            severity: .critical,
            title: "Disk space is low",
            detail: "\(formattedBytes(availableBytes)) free (\(percent)); warning below \(formattedBytes(thresholds.minimumFreeDiskBytes)) or \(thresholds.minimumFreeDiskFraction.formatted(.percent))."
        )
    }

    static func storageWarning(
        kind: SystemHealthWarning.Kind,
        title: String,
        sizeBytes: Int64,
        limitBytes: Int64
    ) -> SystemHealthWarning? {
        guard sizeBytes > limitBytes else { return nil }
        return SystemHealthWarning(
            kind: kind,
            severity: .warning,
            title: title,
            detail: "Using \(formattedBytes(sizeBytes)); warning threshold is \(formattedBytes(limitBytes))."
        )
    }

    static func backupWarnings(
        status: ProjectPilotViewModel.DevelopmentBackupStatus,
        now: Date,
        thresholds: SystemHealthThresholds
    ) -> [SystemHealthWarning] {
        switch status.state {
        case .inSync:
            guard let checkedAt = status.checkedAt else {
                return [backupWarning(title: "Development backup has not been checked", detail: "Open Backup to check its current state.")]
            }
            let age = now.timeIntervalSince(checkedAt)
            guard age > thresholds.maximumBackupAge else { return [] }
            return [backupWarning(
                title: "Development backup check is stale",
                detail: "Last checked \(formattedAge(age)) ago; warning threshold is \(formattedAge(thresholds.maximumBackupAge))."
            )]
        case .checking, .syncing:
            return []
        case .notChecked:
            return [backupWarning(title: "Development backup has not been checked", detail: "Open Backup to check its current state.")]
        case .outOfSync:
            let changes = status.sourceOnlyCount + status.backupOnlyCount + status.changedCount
            return [backupWarning(
                title: "Development backup is out of date",
                detail: "\(changes) item\(changes == 1 ? "" : "s") differ from the backup. Open Backup to review or update it."
            )]
        case .checkTimedOut:
            return [backupWarning(title: "Development backup check timed out", detail: "Open Backup to retry after iCloud activity settles.")]
        case .sourceMissing:
            return [backupWarning(title: "Development folder is unavailable", detail: "The configured local Development folder could not be found.", severity: .critical)]
        case .backupMissing:
            return [backupWarning(title: "Development backup is missing", detail: "The configured iCloud Development backup folder could not be found.")]
        case .error(let message):
            return [backupWarning(title: "Development backup is unhealthy", detail: message, severity: .critical)]
        }
    }

    static func checkFailureWarning(check: String, error: Error) -> SystemHealthWarning {
        SystemHealthWarning(
            kind: .checkFailed,
            severity: .warning,
            title: "\(check) check unavailable",
            detail: error.localizedDescription
        )
    }

    static func dockerStorageBytes(from output: String) throws -> Int64 {
        var total: Int64 = 0
        for line in output.split(whereSeparator: \.isNewline) {
            guard let data = String(line).data(using: .utf8),
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let size = object["Size"] as? String else {
                throw HealthCheckError("Docker returned an unexpected storage summary.")
            }
            total += try bytes(fromDockerSize: size)
        }
        return total
    }

    static func bytes(fromDockerSize value: String) throws -> Int64 {
        let compact = value.replacingOccurrences(of: " ", with: "")
        let numberText = compact.prefix { $0.isNumber || $0 == "." }
        let unit = compact.dropFirst(numberText.count).uppercased()
        guard let number = Double(numberText) else {
            throw HealthCheckError("Docker returned an unreadable storage size: \(value).")
        }
        let multiplier: Double
        switch unit {
        case "B": multiplier = 1
        case "KB": multiplier = 1_000
        case "MB": multiplier = 1_000_000
        case "GB": multiplier = 1_000_000_000
        case "TB": multiplier = 1_000_000_000_000
        default: throw HealthCheckError("Docker returned an unknown storage unit: \(unit).")
        }
        return Int64(number * multiplier)
    }

    private static func backupWarning(
        title: String,
        detail: String,
        severity: SystemHealthWarning.Severity = .warning
    ) -> SystemHealthWarning {
        SystemHealthWarning(kind: .backup, severity: severity, title: title, detail: detail)
    }

    private static func allocatedSize(at url: URL) throws -> Int64 {
        guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
        let output = try ProjectPilotViewModel.runProcess(
            ["/usr/bin/du", "-sk", url.path],
            timeoutSeconds: 30
        )
        guard let kilobytesText = output.split(whereSeparator: \.isWhitespace).first,
              let kilobytes = Int64(kilobytesText) else {
            throw HealthCheckError("Unable to read storage used at \(url.path).")
        }
        return kilobytes * 1_024
    }

    private static func dockerIsAvailable(executable: String) -> Bool {
        (try? ProjectPilotViewModel.runProcess(
            [executable, "info", "--format", "{{.ServerVersion}}"],
            timeoutSeconds: 5
        )) != nil
    }

    private static func existingExecutable(named name: String) -> String? {
        executableCandidates[name]?.first(where: FileManager.default.isExecutableFile(atPath:))
    }

    private static func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private static func formattedAge(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = interval >= 86_400 ? [.day, .hour] : [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: max(0, interval)) ?? "unknown"
    }

    private static let requiredTools = [
        (displayName: "Git", executableName: "git"),
        (displayName: "GitHub CLI", executableName: "gh"),
        (displayName: "rsync", executableName: "rsync"),
        (displayName: "XcodeGen", executableName: "xcodegen")
    ]

    private static let executableCandidates: [String: [String]] = [
        "git": ["/usr/bin/git"],
        "gh": ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"],
        "rsync": ["/usr/bin/rsync"],
        "xcodegen": ["/opt/homebrew/bin/xcodegen", "/usr/local/bin/xcodegen", "/usr/bin/xcodegen"],
        "docker": ["/usr/local/bin/docker", "/opt/homebrew/bin/docker", "/Applications/Docker.app/Contents/Resources/bin/docker"]
    ]
}

private struct HealthCheckError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
