import AppKit
import SwiftUI

struct ProjectPilotPopover: View {
    @ObservedObject var vm: ProjectPilotViewModel

    var body: some View {
        ZStack {
            GlassBackground()

            VStack(alignment: .leading, spacing: 10) {
                header

                section("Project") {
                    LabeledContent("Name") {
                        TextField("e.g. LoomTools", text: $vm.projectName)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 260)
                    }
                    .font(.subheadline)
                }

                section("Platforms") {
                    HStack(spacing: 8) {
                        platformToggle(.iOS, systemImage: "iphone")
                        platformToggle(.macOS, systemImage: "laptopcomputer")
                        platformToggle(.tvOS, systemImage: "appletv")

                        Spacer(minLength: 0)
                    }
                }

                section("GitHub") {
                    Toggle(isOn: $vm.createPublicGitHubRepo) {
                        Text("Public repo")
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }

                if let status = vm.statusLine {
                    statusPill(status)
                }

                Divider().opacity(0.35)

                actions
            }
            .padding(14)
        }
        .frame(width: 420, alignment: .topLeading)
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
                if isOn { vm.selectedPlatforms.insert(platform) }
                else { vm.selectedPlatforms.remove(platform) }
                if vm.selectedPlatforms.isEmpty { vm.selectedPlatforms.insert(.macOS) } // keep at least one
            }
        )) {
            Label(platform.rawValue, systemImage: systemImage)
        }
        .toggleStyle(.button)
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .tint(vm.selectedPlatforms.contains(platform) ? .accentColor : .gray)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "hammer.fill")
                .symbolRenderingMode(.hierarchical)

            Text("ProjectPilot")
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)

            Spacer()

            Button {
                vm.clearStatus()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .help("Clear status")
            .disabled(vm.statusLine == nil || vm.isRunning)
        }
        .padding(.bottom, 2)
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

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                vm.createProjectSkeleton()
            } label: {
                Label("Create", systemImage: "sparkles")
            }
                .keyboardShortcut(.defaultAction)
                .disabled(vm.isRunning || vm.projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .buttonStyle(.borderedProminent)

            Spacer()

            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
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
