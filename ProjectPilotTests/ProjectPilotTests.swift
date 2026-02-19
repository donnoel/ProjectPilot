//
//  ProjectPilotTests.swift
//  ProjectPilotTests
//
//  Created by Don Noel on 2/15/26.
//

import Foundation
import Testing
@testable import ProjectPilot

struct ProjectPilotTests {
    @MainActor
    @Test func projectNameValidationRejectsSymbolOnlyNames() {
        clearProjectPilotDefaults()

        let vm = ProjectPilotViewModel()
        vm.projectName = "!!!"

        #expect(vm.isProjectNameInvalid)
        #expect(vm.projectNameValidationHint == "Use at least one letter or number.")

        vm.projectName = "Project 123"
        #expect(!vm.isProjectNameInvalid)
    }

    @MainActor
    @Test func selectingPresetFromPickerAppliesSettingsImmediately() {
        clearProjectPilotDefaults()

        let vm = ProjectPilotViewModel()
        vm.selectedTemplateProfile = .utilityTool
        vm.selectedPlatforms = [.macOS]
        vm.createGitHubRepo = false
        vm.createPublicGitHubRepo = true

        vm.selectPresetFromPicker("builtin.ios-app")

        #expect(vm.selectedPresetID == "builtin.ios-app")
        #expect(vm.selectedTemplateProfile == .starterApp)
        #expect(vm.selectedPlatforms == [.iOS])
        #expect(vm.createGitHubRepo)
        #expect(!vm.createPublicGitHubRepo)
    }

    @MainActor
    @Test func supportedPlatformsBuildSettingValueMatchesSelectionMatrix() {
        clearProjectPilotDefaults()

        let vm = ProjectPilotViewModel()

        vm.selectedPlatforms = [.iOS]
        #expect(vm.supportedPlatformsBuildSettingValue() == "iphoneos iphonesimulator")

        vm.selectedPlatforms = [.macOS]
        #expect(vm.supportedPlatformsBuildSettingValue() == "macosx")

        vm.selectedPlatforms = [.tvOS]
        #expect(vm.supportedPlatformsBuildSettingValue() == "appletvos appletvsimulator")

        vm.selectedPlatforms = [.iOS, .macOS, .tvOS]
        #expect(vm.supportedPlatformsBuildSettingValue() == "iphoneos iphonesimulator macosx appletvos appletvsimulator")

        vm.selectedPlatforms = []
        #expect(vm.selectedPlatforms == [.macOS])
        #expect(vm.supportedPlatformsBuildSettingValue() == "macosx")
    }

    @MainActor
    @Test func ciDestinationMatchesSelectedPlatforms() {
        #expect(ProjectPilotViewModel.ciDestination(for: [.macOS]) == "platform=macOS")
        #expect(ProjectPilotViewModel.ciDestination(for: [.iOS]) == "platform=iOS Simulator")
        #expect(ProjectPilotViewModel.ciDestination(for: [.tvOS]) == "platform=tvOS Simulator")
        #expect(ProjectPilotViewModel.ciDestination(for: [.iOS, .macOS]) == "platform=macOS")
    }

    @MainActor
    @Test func ciWorkflowTemplateUsesProjectNameAndDestination() {
        let workflow = ProjectPilotViewModel.ciWorkflowTemplate(projectName: "SampleApp",
                                                                platforms: [.iOS])

        #expect(workflow.contains("-project SampleApp.xcodeproj"))
        #expect(workflow.contains("-scheme SampleApp"))
        #expect(workflow.contains("DESTINATION=\"platform=iOS Simulator\""))
    }

    @MainActor
    @Test func openStepStatusMessageMatchesSelections() {
        #expect(ProjectPilotViewModel.openStepStatusMessage(openInXcode: true, openInCodex: true, openInCLI: true) == "Opening in Xcode, Codex, and CLI…")
        #expect(ProjectPilotViewModel.openStepStatusMessage(openInXcode: true, openInCodex: true, openInCLI: false) == "Opening in Xcode and Codex…")
        #expect(ProjectPilotViewModel.openStepStatusMessage(openInXcode: true, openInCodex: false, openInCLI: false) == "Opening in Xcode…")
        #expect(ProjectPilotViewModel.openStepStatusMessage(openInXcode: false, openInCodex: true, openInCLI: false) == "Opening in Codex…")
        #expect(ProjectPilotViewModel.openStepStatusMessage(openInXcode: false, openInCodex: false, openInCLI: true) == "Opening in CLI…")
        #expect(ProjectPilotViewModel.openStepStatusMessage(openInXcode: false, openInCodex: false, openInCLI: false) == nil)
    }

    @Test func codexQuotaSnapshotParsesLatestTokenCountEvent() {
        let olderLine = #"{"timestamp":"2026-02-19T10:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"primary":{"used_percent":70.0,"window_minutes":300,"resets_at":1771500600},"secondary":{"used_percent":97.0,"window_minutes":10080,"resets_at":1772022600},"credits":{"has_credits":false,"unlimited":false,"balance":1}}}}"#
        let latestLine = #"{"timestamp":"2026-02-19T10:05:00.000Z","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"primary":{"used_percent":61.0,"window_minutes":300,"resets_at":1771504200},"secondary":{"used_percent":94.0,"window_minutes":10080,"resets_at":1772026200},"credits":{"has_credits":true,"unlimited":false,"balance":12.5}}}}"#
        let text = olderLine + "\n" + latestLine + "\n"

        let snapshot = ProjectPilotViewModel.codexQuotaSnapshot(fromRolloutJSONLines: text, sourcePath: "/tmp/rollout.jsonl")
        guard let snapshot else {
            Issue.record("Expected quota snapshot from rollout lines.")
            return
        }

        #expect(snapshot.sourcePath == "/tmp/rollout.jsonl")
        #expect(snapshot.primary?.usedPercent == 61.0)
        #expect(snapshot.primary?.remainingPercent == 39.0)
        #expect(snapshot.primary?.windowMinutes == 300)
        #expect(snapshot.primary?.resetAt == Date(timeIntervalSince1970: 1_771_504_200))
        #expect(snapshot.secondary?.remainingPercent == 6.0)
        #expect(snapshot.credits?.hasCredits == true)
        #expect(snapshot.credits?.balance == 12.5)
    }

    @Test func codexQuotaSnapshotClampsOutOfRangePercentages() {
        let line = #"{"timestamp":"2026-02-19T10:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"primary":{"used_percent":123.4,"window_minutes":300,"resets_at":1771500600},"secondary":{"used_percent":-3.0,"window_minutes":10080,"resets_at":1772022600},"credits":{"has_credits":false,"unlimited":true,"balance":null}}}}"#
        let snapshot = ProjectPilotViewModel.codexQuotaSnapshot(fromRolloutJSONLines: line)
        guard let snapshot else {
            Issue.record("Expected quota snapshot from rollout line.")
            return
        }

        #expect(snapshot.primary?.usedPercent == 100.0)
        #expect(snapshot.primary?.remainingPercent == 0.0)
        #expect(snapshot.secondary?.usedPercent == 0.0)
        #expect(snapshot.secondary?.remainingPercent == 100.0)
        #expect(snapshot.credits?.isUnlimited == true)
    }

    @Test func codexQuotaSnapshotReturnsNilWhenTokenCountIsMissing() {
        let line = #"{"timestamp":"2026-02-19T10:00:00.000Z","type":"event_msg","payload":{"type":"status","message":"ok"}}"#
        #expect(ProjectPilotViewModel.codexQuotaSnapshot(fromRolloutJSONLines: line) == nil)
    }

    @MainActor
    private func clearProjectPilotDefaults() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("projectPilot.") {
            defaults.removeObject(forKey: key)
        }
    }

}
