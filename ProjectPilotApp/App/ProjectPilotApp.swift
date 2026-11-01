import ServiceManagement
import SwiftUI

@main
struct ProjectPilotApp: App {
    @NSApplicationDelegateAdaptor(TicksCloudNotificationDelegate.self) private var cloudNotifications
    @StateObject private var ticks = TicksViewModel(automaticallySyncs: true)
    @StateObject private var vm: ProjectPilotViewModel

    init() {
        // StateObject's autoclosure otherwise defers creation until the panel opens.
        let viewModel = ProjectPilotViewModel()
        _vm = StateObject(wrappedValue: viewModel)
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        do {
            try SMAppService.mainApp.register()
        } catch {}
    }

    var body: some Scene {
        // Start backup monitoring at launch, even before the menu-bar panel is opened.
        let viewModel = vm
        return MenuBarExtra("ProjectPilot", systemImage: "hammer.fill") {
            ProjectPilotPopover(vm: viewModel, ticks: ticks)
                .frame(width: 520, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .menuBarExtraStyle(.window)
    }
}
