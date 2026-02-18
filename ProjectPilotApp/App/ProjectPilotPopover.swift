import AppKit
import SwiftUI

struct ProjectPilotPopover: View {
    @ObservedObject var vm: ProjectPilotViewModel

    @State private var mode: Mode = .basic

    enum Mode: String, CaseIterable, Identifiable {
        case basic = "Basic"
        case advanced = "Advanced"

        var id: String { rawValue }
    }

    var body: some View {
        ZStack {
            GlassBackground()

            VStack(alignment: .leading, spacing: 10) {
                header
                modePicker
                progressTimeline

                if mode == .basic {
                    basicSections
                } else {
                    advancedSections
                }

                feedbackSection

                Divider().opacity(0.35)

                actions
                keyboardShortcutsBridge
            }
            .padding(14)
        }
        .frame(width: 520, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "hammer.fill")
                .symbolRenderingMode(.hierarchical)

            Text("ProjectPilot")
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)

            Spacer()
        }
        .padding(.bottom, 2)
    }

    private var modePicker: some View {
        Picker("Mode", selection: $mode) {
            ForEach(Mode.allCases) { item in
                Text(item.rawValue).tag(item)
            }
        }
        .pickerStyle(.segmented)
    }

    private var progressTimeline: some View {
        section("Progress") {
            HStack(spacing: 6) {
                let items = vm.pipelineProgressItems
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    timelineNode(item)
                    if index < items.count - 1 {
                        Capsule()
                            .fill(connectorColor(for: item.state))
                            .frame(width: 14, height: 2)
                    }
                }
            }
        }
    }

    private func timelineNode(_ item: ProjectPilotViewModel.PipelineProgressItem) -> some View {
        VStack(spacing: 3) {
            Circle()
                .fill(stepColor(for: item.state))
                .frame(width: 8, height: 8)
            Text(item.step.title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func stepColor(for state: ProjectPilotViewModel.PipelineStepState) -> Color {
        switch state {
        case .pending: return .gray.opacity(0.5)
        case .inProgress: return .blue
        case .success: return .green
        case .skipped: return .gray
        case .failure: return .red
        }
    }

    private func connectorColor(for state: ProjectPilotViewModel.PipelineStepState) -> Color {
        switch state {
        case .success: return .green.opacity(0.5)
        case .failure: return .red.opacity(0.5)
        case .inProgress: return .blue.opacity(0.4)
        case .pending, .skipped: return .white.opacity(0.18)
        }
    }

    private var basicSections: some View {
        Group {
            projectSection
            platformsSection
            githubSection
        }
    }

    private var advancedSections: some View {
        Group {
            templateSection
            bundleIDsSection
            presetsSection
            postCreateSection
        }
    }

    private var projectSection: some View {
        section("Project") {
            LabeledContent("Name") {
                TextField("e.g. LoomTools", text: $vm.projectName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
            }
            .font(.subheadline)

            if let hint = vm.projectNameValidationHint {
                validationHint(hint, isError: vm.isProjectNameInvalid)
            }

            LabeledContent("Location") {
                HStack(spacing: 8) {
                    Text(vm.projectRootPathDisplay)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 220, alignment: .leading)

                    Button("Choose…") {
                        vm.chooseProjectRootFolder()
                    }
                    .controlSize(.small)
                    .disabled(vm.isRunning)
                }
            }
            .font(.subheadline)
        }
    }

    private var platformsSection: some View {
        section("Platforms") {
            HStack(spacing: 8) {
                platformToggle(.iOS, systemImage: "iphone")
                platformToggle(.macOS, systemImage: "laptopcomputer")
                platformToggle(.tvOS, systemImage: "appletv")
                Spacer(minLength: 0)
            }
        }
    }

    private var githubSection: some View {
        section("GitHub") {
            Toggle(isOn: $vm.createGitHubRepo) {
                Text("Create GitHub repo")
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            Toggle(isOn: $vm.createPublicGitHubRepo) {
                Text("Public repo")
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(!vm.createGitHubRepo)
        }
    }

    private var templateSection: some View {
        section("Template") {
            LabeledContent("Profile") {
                Picker("Profile", selection: $vm.selectedTemplateProfile) {
                    ForEach(ProjectPilotViewModel.TemplateProfile.allCases) { profile in
                        Text(profile.title).tag(profile)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 240)
            }
            .font(.subheadline)

            Text(vm.selectedTemplateProfile.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var bundleIDsSection: some View {
        section("Bundle IDs") {
            LabeledContent("iOS") {
                TextField("com.example.ios", text: $vm.iOSBundleIdentifier)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
            }
            .font(.subheadline)
            if let hint = vm.iOSBundleValidationHint {
                validationHint(hint, isError: vm.isIOSBundleInvalid)
            }

            LabeledContent("macOS") {
                TextField("com.example.macos", text: $vm.macOSBundleIdentifier)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
            }
            .font(.subheadline)
            if let hint = vm.macOSBundleValidationHint {
                validationHint(hint, isError: vm.isMacOSBundleInvalid)
            }

            LabeledContent("tvOS") {
                TextField("com.example.tvos", text: $vm.tvOSBundleIdentifier)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
            }
            .font(.subheadline)
            if let hint = vm.tvOSBundleValidationHint {
                validationHint(hint, isError: vm.isTVOSBundleInvalid)
            }
        }
    }

    private var presetsSection: some View {
        section("Presets") {
            LabeledContent("Preset") {
                Picker(
                    "Preset",
                    selection: Binding(
                        get: { vm.selectedPresetID },
                        set: { vm.selectPresetFromPicker($0) }
                    )
                ) {
                    ForEach(vm.availablePresets) { preset in
                        Text(preset.name).tag(preset.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 240)
            }
            .font(.subheadline)

            HStack(spacing: 8) {
                Button("Apply") {
                    vm.applySelectedPreset()
                }
                .controlSize(.small)
                .disabled(vm.isRunning)

                Button("Delete") {
                    vm.deleteSelectedPreset()
                }
                .controlSize(.small)
                .disabled(vm.isRunning || !vm.canDeleteSelectedPreset)

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                TextField("Save current as preset", text: $vm.newPresetName)
                    .textFieldStyle(.roundedBorder)

                Button("Save") {
                    vm.saveCurrentAsPreset()
                }
                .controlSize(.small)
                .disabled(vm.isRunning || vm.newPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var postCreateSection: some View {
        section("Post-Create") {
            Toggle(isOn: $vm.openInXcodeAfterCreate) {
                Text("Open in Xcode")
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            Toggle(isOn: $vm.revealInFinderAfterCreate) {
                Text("Reveal in Finder")
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            Toggle(isOn: $vm.copyRepoURLAfterCreate) {
                Text("Copy repo URL")
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(!vm.createGitHubRepo && !vm.canRetryGitHub)
        }
    }

    private var feedbackSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let status = vm.statusLine {
                statusPill(status)
            }

            if vm.shouldShowSuccessCard {
                successCard
            }

            if vm.canRetryGitHub {
                HStack(spacing: 8) {
                    Button {
                        vm.retryGitHubSetup()
                    } label: {
                        Label("Retry GitHub", systemImage: "arrow.clockwise")
                    }
                    .controlSize(.small)
                    .disabled(vm.isRunning)
                    .keyboardShortcut("r", modifiers: [.command])

                    Spacer(minLength: 0)
                }
            }

            if vm.shouldShowDetailsPanel {
                detailsPanel
            }
        }
    }

    private var detailsPanel: some View {
        DisclosureGroup(isExpanded: $vm.isDetailsExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                LogView(logs: vm.detailLogs)
                    .frame(maxHeight: 150)

                HStack(spacing: 8) {
                    Button("Copy") {
                        vm.copyDetailsToClipboard()
                    }
                    .controlSize(.small)
                    .disabled(!vm.hasDetailLogs)

                    Button("Clear") {
                        vm.clearDetailLogs()
                    }
                    .controlSize(.small)
                    .disabled(!vm.hasDetailLogs)

                    Spacer(minLength: 0)

                    Text("\(vm.detailLogs.count) entries")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } label: {
            Text("Details")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.thinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var successCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Text("Project Ready")
                    .font(.subheadline.weight(.semibold))
            }

            Text(vm.lastCreatedProjectPathDisplay)
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

            HStack(spacing: 8) {
                Button("Open") {
                    vm.openLastCreatedProjectInXcode()
                }
                .controlSize(.small)

                Button("Finder") {
                    vm.revealLastCreatedProjectInFinder()
                }
                .controlSize(.small)

                Button("Copy path") {
                    vm.copyLastCreatedProjectPath()
                }
                .controlSize(.small)

                Spacer(minLength: 0)
            }
        }
        .padding(10)
        .background(Color.green.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.green.opacity(0.28), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func statusPill(_ status: ProjectPilotViewModel.StatusLine) -> some View {
        HStack(spacing: 8) {
            Circle()
                .frame(width: 7, height: 7)
                .foregroundStyle(statusColor(status.level))

            Text(status.message)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)

            if vm.isRunning {
                ProgressView()
                    .controlSize(.small)
            }

            Button("Clear") {
                vm.clearTransientFeedback()
            }
            .controlSize(.mini)
            .disabled(vm.isRunning)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.thinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func statusColor(_ level: ProjectPilotViewModel.StatusLevel) -> Color {
        switch level {
        case .info: return .blue
        case .success: return .green
        case .error: return .red
        }
    }

    private func validationHint(_ text: String, isError: Bool) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(isError ? .red : .secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                vm.createProjectSkeleton()
            } label: {
                Label("Create", systemImage: "sparkles")
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!vm.canCreateProject)
            .buttonStyle(.borderedProminent)

            Spacer()

            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
    }

    private var keyboardShortcutsBridge: some View {
        VStack(spacing: 0) {
            Button("") {
                vm.retryGitHubSetup()
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(!vm.canRetryGitHub || vm.isRunning)
            .frame(width: 0, height: 0)
            .opacity(0.001)

            Button("") {
                vm.clearTransientFeedback()
            }
            .keyboardShortcut(.cancelAction)
            .disabled(vm.statusLine == nil && !vm.hasDetailLogs)
            .frame(width: 0, height: 0)
            .opacity(0.001)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            content()
        }
        .padding(12)
        .background(.thinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func platformToggle(_ platform: ProjectPilotViewModel.Platform, systemImage: String) -> some View {
        Toggle(isOn: Binding(
            get: { vm.selectedPlatforms.contains(platform) },
            set: { isOn in
                if isOn {
                    vm.selectedPlatforms.insert(platform)
                } else {
                    vm.selectedPlatforms.remove(platform)
                }
                if vm.selectedPlatforms.isEmpty {
                    vm.selectedPlatforms.insert(.macOS)
                }
            }
        )) {
            Label(platform.rawValue, systemImage: systemImage)
        }
        .toggleStyle(.button)
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .tint(vm.selectedPlatforms.contains(platform) ? .accentColor : .gray)
    }
}

private struct GlassBackground: View {
    var body: some View {
        VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
    }
}
