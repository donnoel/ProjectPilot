import SwiftUI

struct ProjectPilotPopover: View {
    @ObservedObject var vm: ProjectPilotViewModel

    var body: some View {
        VStack(spacing: 10) {
            header

            formContent

            Divider()

            LogView(logs: vm.logs)
                .frame(height: 140)

            Divider()

            actions
        }
        .padding(12)
        // Ensure the content (Form + LogView + buttons) fits without clipping.
        .frame(width: 460, height: 640)
    }

    private var formContent: some View {
        Form {
            Section("Project") {
                TextField("Name (e.g. LoomTools)", text: $vm.projectName)
                    .textFieldStyle(.roundedBorder)

                TextField("Destination", text: $vm.destinationPath)
                    .textFieldStyle(.roundedBorder)
            }

            Section("Platforms") {
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
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(maxHeight: 220)
    }

    private var header: some View {
        HStack {
            Image(systemName: "hammer.fill")
            Text("ProjectPilot")
                .font(.headline)
            Spacer()
            Button("Clear") { vm.clearLogs() }
                .disabled(vm.logs.isEmpty || vm.isRunning)
        }
    }

    private var actions: some View {
        HStack {
            Button("Create") { vm.createProjectSkeleton() }
                .keyboardShortcut(.defaultAction)
                .disabled(vm.isRunning)

            Spacer()

            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
    }
}
