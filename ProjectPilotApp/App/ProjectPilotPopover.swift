import SwiftUI

struct ProjectPilotPopover: View {
    @ObservedObject var vm: ProjectPilotViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            projectSection

            platformsSection

            if let status = vm.statusLine {
                statusPill(status)
            }

            Spacer(minLength: 0)

            actions
        }
        .padding(12)
        .frame(width: 460, height: 420, alignment: .topLeading)
    }

    private var projectSection: some View {
        GroupBox {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Name")
                    .font(.headline)
                    .frame(width: 110, alignment: .leading)

                TextField("e.g. LoomTools", text: $vm.projectName)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.vertical, 2)
        } label: {
            Text("Project")
                .font(.headline)
        }
    }

    private var platformsSection: some View {
        GroupBox {
            VStack(spacing: 10) {
                ForEach(ProjectPilotViewModel.Platform.allCases) { platform in
                    Toggle(platform.rawValue, isOn: Binding(
                        get: { vm.selectedPlatforms.contains(platform) },
                        set: { isOn in
                            if isOn { vm.selectedPlatforms.insert(platform) }
                            else { vm.selectedPlatforms.remove(platform) }
                            if vm.selectedPlatforms.isEmpty { vm.selectedPlatforms.insert(.macOS) } // keep at least one
                        }
                    ))
                }
            }
            .toggleStyle(.switch)
            .padding(.vertical, 2)
        } label: {
            Text("Platforms")
                .font(.headline)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "hammer.fill")

            Text("ProjectPilot")
                .font(.headline)
                .lineLimit(1)

            Spacer()

            Button("Clear") { vm.clearStatus() }
                .disabled(vm.statusLine == nil || vm.isRunning)
        }
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
            Button("Create") { vm.createProjectSkeleton() }
                .keyboardShortcut(.defaultAction)
                .disabled(vm.isRunning || vm.projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Spacer()

            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
    }
}
