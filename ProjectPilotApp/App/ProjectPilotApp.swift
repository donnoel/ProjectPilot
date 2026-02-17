import ServiceManagement
import SwiftUI

@main
struct ProjectPilotApp: App {
    @StateObject private var vm = ProjectPilotViewModel()

    init() {
        // Auto-launch at login (boot) for a menu bar utility like this.
        // SMAppService.mainApp is the modern, built-in mechanism (no helper app).
        do {
            try SMAppService.mainApp.register()
        } catch {
            // Non-fatal: the app still works.
        }
    }

    var body: some Scene {
        MenuBarExtra("ProjectPilot", systemImage: "hammer.fill") {
            ProjectPilotPopover(vm: vm)
                .frame(width: 420, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .menuBarExtraStyle(.window)
    }
}
