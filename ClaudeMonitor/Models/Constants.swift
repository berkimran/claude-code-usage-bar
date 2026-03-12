import Foundation

enum Constants {
    static let claudeDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude")
    static let projectsDir = claudeDir.appendingPathComponent("projects")
    static let backupsDir = claudeDir.appendingPathComponent("backups")

    static let defaultContextWindow = 200_000
    static let extendedContextWindow = 1_000_000

    static let defaultPollingInterval: TimeInterval = 60.0   // API call every 60s
    static let fsEventLatency: CFTimeInterval = 0.5
    static let coldStartChunkSize = 64 * 1024

    // Color thresholds (percentage)
    static let greenMax = 60.0
    static let yellowMax = 80.0
    static let orangeMax = 90.0
}
