import SwiftUI

@main
struct ProjectPilotApp: App {
    @StateObject private var vm = ProjectPilotViewModel()

    var body: some Scene {
        MenuBarExtra("ProjectPilot", systemImage: "hammer.fill") {
            ProjectPilotPopover(vm: vm)
                // IMPORTANT: match the popover's fixed size so it doesn't crop/offset.
                .frame(width: 460, height: 420, alignment: .topLeading)
        }
        .menuBarExtraStyle(.window)
    }
}
