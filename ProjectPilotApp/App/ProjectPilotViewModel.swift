import Foundation
import Combine

@MainActor
final class ProjectPilotViewModel: ObservableObject {
    enum Platform: String, CaseIterable, Identifiable {
        case iOS, macOS, tvOS
        var id: String { rawValue }
    }

    struct LogEvent: Identifiable, Equatable {
        enum Level { case info, error, success }
        let id = UUID()
        let date = Date()
        let level: Level
        let message: String
    }

    @Published var projectName: String = ""
    @Published var destinationPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Development"
    }()

    @Published var selectedPlatforms: Set<Platform> = [.macOS]
    @Published var logs: [LogEvent] = []

    @Published var isRunning: Bool = false

    func createProjectSkeleton() {
        guard !isRunning else { return }

        let trimmed = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            log(.error, "Please enter a project name.")
            return
        }

        isRunning = true
        defer { isRunning = false }

        let destURL = URL(fileURLWithPath: destinationPath, isDirectory: true)
        let projectURL = destURL.appendingPathComponent(trimmed, isDirectory: true)

        do {
            log(.info, "Creating folder: \(projectURL.path)")
            try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

            let markerURL = projectURL.appendingPathComponent("ProjectPilot.created", isDirectory: false)
            let contents = """
            Project: \(trimmed)
            Platforms: \(selectedPlatforms.map(\.rawValue).sorted().joined(separator: ", "))
            Created: \(ISO8601DateFormatter().string(from: Date()))
            """
            try contents.data(using: .utf8)?.write(to: markerURL, options: .atomic)

            log(.success, "Created skeleton at \(projectURL.path)")
        } catch {
            log(.error, "Failed: \(error.localizedDescription)")
        }
    }

    func log(_ level: LogEvent.Level, _ message: String) {
        logs.append(LogEvent(level: level, message: message))
    }

    func clearLogs() {
        logs.removeAll()
    }
}
