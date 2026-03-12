import Foundation

final class SessionWatcher {
    typealias FileChangeHandler = (URL) -> Void

    private var stream: FSEventStreamRef?
    private var onChange: FileChangeHandler?
    private var retainedSelf: Unmanaged<SessionWatcher>?
    private let projectsPath: String

    init() {
        projectsPath = Constants.projectsDir.path
    }

    func start(onChange: @escaping FileChangeHandler) {
        self.onChange = onChange
        guard FileManager.default.fileExists(atPath: projectsPath) else { return }

        var context = FSEventStreamContext()
        let retained = Unmanaged.passRetained(self)
        retainedSelf = retained
        context.info = retained.toOpaque()

        let paths = [projectsPath] as CFArray
        let flags: FSEventStreamCreateFlags =
            UInt32(kFSEventStreamCreateFlagFileEvents) |
            UInt32(kFSEventStreamCreateFlagUseCFTypes) |
            UInt32(kFSEventStreamCreateFlagNoDefer)

        guard let eventStream = FSEventStreamCreate(
            nil,
            fsEventCallback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            Constants.fsEventLatency,
            flags
        ) else {
            retainedSelf?.release()
            retainedSelf = nil
            return
        }

        stream = eventStream
        FSEventStreamScheduleWithRunLoop(eventStream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        FSEventStreamStart(eventStream)
    }

    func stop() {
        if let stream = stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        retainedSelf?.release()
        retainedSelf = nil
    }

    func findActiveSession() -> (url: URL, projectPath: String)? {
        let fm = FileManager.default
        guard let projectDirs = try? fm.contentsOfDirectory(
            at: Constants.projectsDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return nil }

        var latestFile: URL?
        var latestDate: Date = .distantPast
        var latestProjectDir = ""

        for dir in projectDirs {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }

            guard let files = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: .skipsHiddenFiles
            ) else { continue }

            for file in files where file.pathExtension == "jsonl" {
                guard let attrs = try? fm.attributesOfItem(atPath: file.path),
                      let modDate = attrs[.modificationDate] as? Date else { continue }
                if modDate > latestDate {
                    latestDate = modDate
                    latestFile = file
                    latestProjectDir = dir.lastPathComponent
                }
            }
        }

        guard let file = latestFile else { return nil }
        if Date().timeIntervalSince(latestDate) > 300 {
            return nil
        }
        let projectPath = decodeProjectPath(from: latestProjectDir)
        return (file, projectPath)
    }

    private func decodeProjectPath(from encoded: String) -> String {
        guard encoded.hasPrefix("-") else { return encoded }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let parts = encoded.split(separator: "-", omittingEmptySubsequences: false)
        var path = ""
        var i = 1

        while i < parts.count {
            var found = false
            for end in stride(from: parts.count, through: i + 1, by: -1) {
                let segment = parts[i..<end].joined(separator: "-")
                let candidate = path + "/" + segment
                guard candidate.hasPrefix(home) || home.hasPrefix(candidate) else { continue }

                if end == parts.count {
                    path = candidate
                    i = end
                    found = true
                    break
                }
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: candidate, isDirectory: &isDir), isDir.boolValue {
                    path = candidate
                    i = end
                    found = true
                    break
                }
            }
            if !found {
                path += "/" + String(parts[i])
                i += 1
            }
        }

        return path
    }

    fileprivate func handleEvent(paths: [String]) {
        for path in paths where path.hasSuffix(".jsonl") {
            let url = URL(fileURLWithPath: path)
            DispatchQueue.main.async { [weak self] in
                self?.onChange?(url)
            }
            return
        }
    }
}

private func fsEventCallback(
    streamRef: ConstFSEventStreamRef,
    clientCallBackInfo: UnsafeMutableRawPointer?,
    numEvents: Int,
    eventPaths: UnsafeMutableRawPointer,
    eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let info = clientCallBackInfo else { return }
    let watcher = Unmanaged<SessionWatcher>.fromOpaque(info).takeUnretainedValue()
    guard let cfPaths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }
    watcher.handleEvent(paths: cfPaths)
}
