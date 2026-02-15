import SwiftUI

@main
struct ProjectPilotApp: App {
    @StateObject private var vm = ProjectPilotViewModel()

    var body: some Scene {
        MenuBarExtra("ProjectPilot", systemImage: "hammer.fill") {
            ProjectPilotPopover(vm: vm)
                .frame(width: 360)
        }
        .menuBarExtraStyle(.window)
    }
}
