import ServiceManagement
import SwiftUI

@main
struct ProjectPilotApp: App {
    @NSApplicationDelegateAdaptor(TicksCloudNotificationDelegate.self) private var cloudNotifications
    @StateObject private var ticks = TicksViewModel(automaticallySyncs: true)
    @StateObject private var vm = ProjectPilotViewModel()

    init() {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        do {
            try SMAppService.mainApp.register()
        } catch {}
    }

    var body: some Scene {
        MenuBarExtra("ProjectPilot", systemImage: "hammer.fill") {
            ProjectPilotPopover(vm: vm, ticks: ticks)
                .frame(width: 520, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .menuBarExtraStyle(.window)
    }
}
