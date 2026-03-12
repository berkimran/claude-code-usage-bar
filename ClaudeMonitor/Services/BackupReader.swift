import Foundation

final class BackupReader {
    private let backupsDir = Constants.backupsDir

    func readLatestBackup() -> [ProjectMetrics] {
        let fm = FileManager.default
        let dirPath = backupsDir.path

        guard fm.fileExists(atPath: dirPath),
              let entries = try? fm.contentsOfDirectory(atPath: dirPath) else { return [] }

        let backupFiles = entries
            .filter { $0.hasPrefix(".claude.json.backup.") }
            .map { backupsDir.appendingPathComponent($0).standardized }
            .filter { $0.path.hasPrefix(backupsDir.standardized.path) }

        guard let latest = backupFiles.max(by: { a, b in
            extractEpoch(from: a.lastPathComponent) < extractEpoch(from: b.lastPathComponent)
        }) else { return [] }

        return parseBackup(at: latest)
    }

    func readLatestBackupCost(forProject projectPath: String) -> Double? {
        let metrics = readLatestBackup()
        return metrics.first(where: { $0.path == projectPath })?.cost
    }

    private func parseBackup(at url: URL) -> [ProjectMetrics] {
        guard let data = try? Data(contentsOf: url) else { return [] }

        if let config = try? JSONDecoder().decode(BackupConfig.self, from: data),
           let projects = config.projects {
            return projects.compactMap { (path, cfg) -> ProjectMetrics? in
                guard let cost = cfg.lastCost else { return nil }
                return ProjectMetrics(
                    path: path,
                    cost: cost,
                    lastSessionId: cfg.lastSessionId,
                    modelUsage: cfg.lastModelUsage
                )
            }.sorted { $0.cost > $1.cost }
        }

        return []
    }

    private func extractEpoch(from filename: String) -> UInt64 {
        let parts = filename.components(separatedBy: ".")
        guard let last = parts.last, let epoch = UInt64(last) else { return 0 }
        return epoch
    }
}
