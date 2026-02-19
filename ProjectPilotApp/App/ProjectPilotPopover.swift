import AppKit
import SwiftUI

struct ProjectPilotPopover: View {
    @ObservedObject var vm: ProjectPilotViewModel

    @State private var mode: Mode = .basic

    enum Mode: String, CaseIterable, Identifiable {
        case basic = "Basic"
        case advanced = "Advanced"
        case codex = "Codex"

        var id: String { rawValue }
    }

    var body: some View {
        ZStack {
            GlassBackground()

            VStack(alignment: .leading, spacing: 10) {
                header
                modePicker
                if mode != .codex {
                    progressTimeline
                }

                switch mode {
                case .basic:
                    basicSections
                case .advanced:
                    advancedSections
                case .codex:
                    codexSections
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
                .padding(6)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Circle()
                                .strokeBorder(.white.opacity(0.28), lineWidth: 0.8)
                        )
                )

            Text("Project Pilot")
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
                .overlay(
                    Circle()
                        .strokeBorder(.white.opacity(0.45), lineWidth: 0.6)
                )
                .shadow(color: stepColor(for: item.state).opacity(0.35), radius: 4, x: 0, y: 2)
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
            postCreateSection
        }
    }

    private var codexSections: some View {
        section("Balance") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Codex quota")
                            .font(.subheadline.weight(.semibold))
                        if let updatedAt = vm.codexQuotaLastUpdatedAt {
                            Text("Updated \(updatedAt.formatted(date: .omitted, time: .shortened))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 0)

                    Button {
                        vm.refreshCodexQuota()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .controlSize(.small)
                }

                codexUsageCard(
                    title: "5 hour usage limit",
                    usageLimit: vm.codexQuotaSnapshot?.primary
                )

                codexUsageCard(
                    title: "Weekly usage limit",
                    usageLimit: vm.codexQuotaSnapshot?.secondary
                )

                codexCreditsCard(vm.codexQuotaSnapshot?.credits)

                if let message = vm.codexQuotaError {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var projectSection: some View {
        section("Project") {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 10) {
                    Text("Name")
                        .font(.subheadline.weight(.medium))
                        .frame(width: 72, alignment: .leading)

                    TextField("e.g. LoomTools", text: $vm.projectName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 7)

                if let hint = vm.projectNameValidationHint {
                    validationHint(hint, isError: vm.isProjectNameInvalid)
                        .padding(.leading, 82)
                        .padding(.bottom, 6)
                }

                Divider().opacity(0.20)

                HStack(alignment: .center, spacing: 10) {
                    Text("Location")
                        .font(.subheadline.weight(.medium))
                        .frame(width: 72, alignment: .leading)

                    HStack(spacing: 8) {
                        Text(vm.projectRootPathDisplay)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button("Choose…") {
                            vm.chooseProjectRootFolder()
                        }
                        .controlSize(.small)
                        .disabled(vm.isRunning)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 7)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(0.05))
            )
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
            VStack(spacing: 0) {
                toggleSettingRow(
                    title: "Create GitHub repo",
                    subtitle: "Create and push a remote repository after local scaffold succeeds.",
                    isOn: $vm.createGitHubRepo
                )

                Divider().opacity(0.20)

                toggleSettingRow(
                    title: "Public repo",
                    subtitle: "When enabled, the created GitHub repository is public.",
                    isOn: $vm.createPublicGitHubRepo,
                    isDisabled: !vm.createGitHubRepo
                )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(0.05))
            )
        }
    }

    private var templateSection: some View {
        section("Template") {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 10) {
                    Text("Profile")
                        .font(.subheadline.weight(.medium))
                        .frame(width: 72, alignment: .leading)

                    Picker("Profile", selection: $vm.selectedTemplateProfile) {
                        ForEach(ProjectPilotViewModel.TemplateProfile.allCases) { profile in
                            Text(profile.title).tag(profile)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 7)

                Divider().opacity(0.20)

                Text(vm.selectedTemplateProfile.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 7)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(0.05))
            )
        }
    }


    private var postCreateSection: some View {
        section("Post-Create") {
            VStack(spacing: 0) {
                toggleSettingRow(
                    title: "Open in Xcode",
                    subtitle: "Launch the generated project as soon as creation completes.",
                    isOn: $vm.openInXcodeAfterCreate
                )

                Divider().opacity(0.20)

                toggleSettingRow(
                    title: "Open in Codex",
                    subtitle: "Open the new project folder in the Codex app and add it as a workspace.",
                    isOn: $vm.openInCodexAfterCreate
                )

                Divider().opacity(0.20)

                toggleSettingRow(
                    title: "Open CLI",
                    subtitle: "Open Terminal in the new project folder so you can start coding immediately.",
                    isOn: $vm.openInCLIAfterCreate
                )

                Divider().opacity(0.20)

                toggleSettingRow(
                    title: "Open in Finder",
                    subtitle: "Open the project folder in Finder after create.",
                    isOn: $vm.revealInFinderAfterCreate
                )

                Divider().opacity(0.20)

                toggleSettingRow(
                    title: "Open Safari to repo",
                    subtitle: "Open the GitHub project page in Safari when remote setup is available.",
                    isOn: $vm.openGitHubRepoInSafariAfterCreate,
                    isDisabled: !vm.createGitHubRepo && !vm.canRetryGitHub
                )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(0.05))
            )
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
        .liquidGlassCard(cornerRadius: 12, tint: .white.opacity(0.05), shadowOpacity: 0.08)
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
        .liquidGlassCard(cornerRadius: 12, tint: .green.opacity(0.14), shadowOpacity: 0.08)
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
        .liquidGlassCard(cornerRadius: 12, tint: statusColor(status.level).opacity(0.08), shadowOpacity: 0.08)
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

    @ViewBuilder
    private func codexUsageCard(
        title: String,
        usageLimit: ProjectPilotViewModel.CodexQuotaSnapshot.UsageLimit?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if let usageLimit {
                Text("\(Int(usageLimit.remainingPercent.rounded()))% remaining")
                    .font(.title3.weight(.semibold))

                ProgressView(value: usageLimit.remainingPercent, total: 100)
                    .progressViewStyle(.linear)
                    .tint(codexUsageTint(remainingPercent: usageLimit.remainingPercent))

                Text(codexResetText(for: usageLimit.resetAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Waiting for Codex usage data…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .liquidGlassCard(cornerRadius: 12, tint: .white.opacity(0.04), shadowOpacity: 0.08)
    }

    @ViewBuilder
    private func codexCreditsCard(_ credits: ProjectPilotViewModel.CodexQuotaSnapshot.Credits?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Credits remaining")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if let credits {
                Text(codexCreditsText(for: credits))
                    .font(.title3.weight(.semibold))

                if credits.isUnlimited {
                    Text("Your plan has unlimited credits.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if credits.hasCredits {
                    Text("Credits can be used after your plan limits are reached.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No extra credits available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Waiting for Codex credits data…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .liquidGlassCard(cornerRadius: 12, tint: .white.opacity(0.04), shadowOpacity: 0.08)
    }

    private func codexUsageTint(remainingPercent: Double) -> Color {
        switch remainingPercent {
        case ..<10: return .red
        case ..<30: return .orange
        default: return .green
        }
    }

    private func codexResetText(for resetAt: Date?) -> String {
        guard let resetAt else { return "Reset time unavailable" }
        if Calendar.current.isDateInToday(resetAt) {
            return "Resets \(resetAt.formatted(date: .omitted, time: .shortened))"
        }
        return "Resets \(resetAt.formatted(date: .abbreviated, time: .shortened))"
    }

    private func codexCreditsText(for credits: ProjectPilotViewModel.CodexQuotaSnapshot.Credits) -> String {
        if credits.isUnlimited {
            return "Unlimited"
        }
        guard let balance = credits.balance else {
            return credits.hasCredits ? "Available" : "0"
        }
        return balance.formatted(.number.precision(.fractionLength(0...2)))
    }

    private func toggleSettingRow(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        isDisabled: Bool = false
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 10)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.vertical, 7)
        .disabled(isDisabled)
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
        .liquidGlassCard(cornerRadius: 14, tint: .accentColor.opacity(0.05))
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
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)

            LinearGradient(
                colors: [
                    .white.opacity(0.24),
                    .white.opacity(0.06),
                    .clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(.screen)

            RadialGradient(
                colors: [
                    .white.opacity(0.18),
                    .clear
                ],
                center: .topLeading,
                startRadius: 0,
                endRadius: 180
            )
            .offset(x: -40, y: -30)

            RadialGradient(
                colors: [
                    .accentColor.opacity(0.16),
                    .clear
                ],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 220
            )
            .offset(x: 40, y: 40)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.42),
                            .white.opacity(0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct LiquidGlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color
    let shadowOpacity: Double

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(tint)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.30),
                                        .white.opacity(0.10),
                                        .clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .blendMode(.plusLighter)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.44),
                                        .white.opacity(0.08)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: .black.opacity(shadowOpacity), radius: 10, x: 0, y: 5)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

private extension View {
    func liquidGlassCard(
        cornerRadius: CGFloat,
        tint: Color = .white.opacity(0.04),
        shadowOpacity: Double = 0.12
    ) -> some View {
        modifier(
            LiquidGlassCardModifier(
                cornerRadius: cornerRadius,
                tint: tint,
                shadowOpacity: shadowOpacity
            )
        )
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
