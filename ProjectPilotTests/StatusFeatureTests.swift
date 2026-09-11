import Foundation
import Testing
@testable import ProjectPilot

struct StatusFeatureTests {
    @Test func ciIgnoresSuccessfulRunForOlderCommit() {
        let runs = [
            ProjectPilotViewModel.GitHubWorkflowRun(
                headSHA: "older",
                status: "completed",
                conclusion: "success",
                url: "https://example.com/older",
                createdAt: Date()
            )
        ]

        let result = ProjectPilotViewModel.interpretCIStatus(
            currentCommitSHA: "current",
            hasConfiguredWorkflows: true,
            runs: runs
        )

        #expect(result.state == .noRunForCurrentCommit)
        #expect(result.runURL == nil)
    }

    @Test func ciInterpretsMatchingRunStatesAndLinks() {
        let passing = ProjectPilotViewModel.GitHubWorkflowRun(
            headSHA: "current",
            status: "completed",
            conclusion: "success",
            url: "https://example.com/passing",
            createdAt: Date()
        )
        let running = ProjectPilotViewModel.GitHubWorkflowRun(
            headSHA: "current",
            status: "in_progress",
            conclusion: nil,
            url: "https://example.com/running",
            createdAt: Date().addingTimeInterval(1)
        )
        let failed = ProjectPilotViewModel.GitHubWorkflowRun(
            headSHA: "current",
            status: "completed",
            conclusion: "failure",
            url: "https://example.com/failed",
            createdAt: Date()
        )

        let passingResult = ProjectPilotViewModel.interpretCIStatus(
            currentCommitSHA: "current",
            hasConfiguredWorkflows: true,
            runs: [passing]
        )
        #expect(passingResult.state == .passing)
        #expect(passingResult.runURL == passing.url)

        let runningResult = ProjectPilotViewModel.interpretCIStatus(
            currentCommitSHA: "current",
            hasConfiguredWorkflows: true,
            runs: [passing, running]
        )
        #expect(runningResult.state == .running)
        #expect(runningResult.runURL == running.url)

        let failedResult = ProjectPilotViewModel.interpretCIStatus(
            currentCommitSHA: "current",
            hasConfiguredWorkflows: true,
            runs: [passing, failed]
        )
        #expect(failedResult.state == .failed)
        #expect(failedResult.runURL == failed.url)

        let noCIResult = ProjectPilotViewModel.interpretCIStatus(
            currentCommitSHA: "current",
            hasConfiguredWorkflows: false,
            runs: [passing]
        )
        #expect(noCIResult.state == .noCIConfigured)
    }

    @Test func ciParsingFailsClosedWhenRunIdentityIsMissing() {
        let malformedJSON = #"[{"status":"completed","conclusion":"success"}]"#

        #expect(throws: (any Error).self) {
            try ProjectPilotViewModel.parseGitHubWorkflowRuns(fromJSON: malformedJSON)
        }
    }

    @Test func healthThresholdsReportOnlyValuesPastLimits() {
        let gibibyte: Int64 = 1_024 * 1_024 * 1_024
        let thresholds = SystemHealthThresholds(
            minimumFreeDiskBytes: 20 * gibibyte,
            minimumFreeDiskFraction: 0.10,
            maximumXcodeAndSimulatorBytes: 50 * gibibyte,
            maximumDockerBytes: 40 * gibibyte,
            maximumBackupAge: 86_400
        )

        #expect(SystemHealthChecker.diskWarning(
            availableBytes: 30 * gibibyte,
            totalBytes: 200 * gibibyte,
            thresholds: thresholds
        ) == nil)
        #expect(SystemHealthChecker.diskWarning(
            availableBytes: 19 * gibibyte,
            totalBytes: 200 * gibibyte,
            thresholds: thresholds
        )?.kind == .lowDisk)
        #expect(SystemHealthChecker.diskWarning(
            availableBytes: 25 * gibibyte,
            totalBytes: 500 * gibibyte,
            thresholds: thresholds
        )?.kind == .lowDisk)
        #expect(SystemHealthChecker.storageWarning(
            kind: .developerStorage,
            title: "Developer storage",
            sizeBytes: 50 * gibibyte,
            limitBytes: thresholds.maximumXcodeAndSimulatorBytes
        ) == nil)
        #expect(SystemHealthChecker.storageWarning(
            kind: .dockerStorage,
            title: "Docker storage",
            sizeBytes: 41 * gibibyte,
            limitBytes: thresholds.maximumDockerBytes
        )?.kind == .dockerStorage)
    }

    @Test func healthReportsStaleAndUnhealthyBackupStates() {
        let now = Date(timeIntervalSince1970: 200_000)
        let staleStatus = backupStatus(
            state: .inSync,
            checkedAt: now.addingTimeInterval(-90_000)
        )
        let staleWarnings = SystemHealthChecker.backupWarnings(
            status: staleStatus,
            now: now,
            thresholds: .standard
        )
        #expect(staleWarnings.count == 1)
        #expect(staleWarnings[0].title.contains("stale"))

        let unhealthyStatus = backupStatus(
            state: .error("iCloud Drive is unavailable."),
            checkedAt: now
        )
        let unhealthyWarnings = SystemHealthChecker.backupWarnings(
            status: unhealthyStatus,
            now: now,
            thresholds: .standard
        )
        #expect(unhealthyWarnings.count == 1)
        #expect(unhealthyWarnings[0].severity == .critical)
        #expect(unhealthyWarnings[0].detail == "iCloud Drive is unavailable.")
    }

    @Test func healthCheckFailureProducesActionableWarning() {
        let error = NSError(domain: "StatusFeatureTests", code: 7, userInfo: [
            NSLocalizedDescriptionKey: "Permission denied."
        ])
        let warning = SystemHealthChecker.checkFailureWarning(check: "Disk space", error: error)

        #expect(warning.kind == .checkFailed)
        #expect(warning.title == "Disk space check unavailable")
        #expect(warning.detail == "Permission denied.")
    }

    @Test func systemHealthTabSelectionRoundTripsAndFallsBackSafely() {
        let rawValue = ProjectPilotPopover.Mode.systemHealth.rawValue

        #expect(ProjectPilotPopover.Mode.persistedValue(for: rawValue) == .systemHealth)
        #expect(ProjectPilotPopover.Mode.persistedValue(for: "Removed Tab") == .ticks)
    }

    private func backupStatus(
        state: ProjectPilotViewModel.DevelopmentBackupStatus.State,
        checkedAt: Date?
    ) -> ProjectPilotViewModel.DevelopmentBackupStatus {
        ProjectPilotViewModel.DevelopmentBackupStatus(
            state: state,
            sourcePath: "~/Development",
            backupPath: "~/Library/Mobile Documents/com~apple~CloudDocs/Development",
            sourceOnlyCount: 0,
            backupOnlyCount: 0,
            changedCount: 0,
            checkedAt: checkedAt
        )
    }
}
