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
    private func clearProjectPilotDefaults() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("projectPilot.") {
            defaults.removeObject(forKey: key)
        }
    }

}
