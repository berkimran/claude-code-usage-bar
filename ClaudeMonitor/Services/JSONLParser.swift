import Foundation

final class JSONLParser {
    private var currentFilePath: URL?
    private var lastOffset: UInt64 = 0
    private var partialLineBuffer: Data = Data()
    private var seenRequestIds: Set<String> = Set()

    private let decoder = JSONDecoder()

    struct ParseResult {
        var lastInputTokens: Int = 0
        var lastOutputTokens: Int = 0
        var lastCacheCreation: Int = 0
        var lastCacheRead: Int = 0
        var totalOutputTokens: Int = 0
        var apiCallCount: Int = 0
        var model: String = ""
    }

    func coldStart(fileURL: URL) -> ParseResult {
        currentFilePath = fileURL
        seenRequestIds.removeAll()
        partialLineBuffer = Data()
        lastOffset = 0

        guard let fileHandle = try? FileHandle(forReadingFrom: fileURL) else {
            return ParseResult()
        }
        defer { try? fileHandle.close() }

        let fileSize = fileHandle.seekToEndOfFile()
        guard fileSize > 0 else { return ParseResult() }

        var result = ParseResult()
        var lastCompletedLine: JSONLLine?

        let maxDirectRead: UInt64 = 10 * 1024 * 1024
        if fileSize <= maxDirectRead {
            fileHandle.seek(toFileOffset: 0)
            let data = fileHandle.readDataToEndOfFile()
            let lines = splitLines(data: data)
            (result, lastCompletedLine) = processAllLines(lines)
            lastOffset = fileSize
        } else {
            lastCompletedLine = backwardScanForLastCompleted(fileHandle: fileHandle, fileSize: fileSize)

            fileHandle.seek(toFileOffset: 0)
            var cumulativeOutput = 0
            var callCount = 0
            var model = ""
            var localSeenIds = Set<String>()

            let chunkSize = 4 * 1024 * 1024
            var buffer = Data()

            while fileHandle.offsetInFile < fileSize {
                let chunk = fileHandle.readData(ofLength: chunkSize)
                if chunk.isEmpty { break }
                buffer.append(chunk)

                if let lastNewline = buffer.lastIndex(of: UInt8(0x0A)) {
                    let processable = buffer[buffer.startIndex...lastNewline]
                    buffer = Data(buffer[buffer.index(after: lastNewline)...])

                    let lineStrings = splitLines(data: Data(processable))
                    for lineStr in lineStrings {
                        guard let lineData = lineStr.data(using: .utf8),
                              let parsed = try? decoder.decode(JSONLLine.self, from: lineData) else { continue }

                        if parsed.type == "assistant",
                           let msg = parsed.message,
                           msg.stopReason != nil,
                           let usage = msg.usage {
                            let reqId = parsed.requestId ?? UUID().uuidString
                            if !localSeenIds.contains(reqId) {
                                localSeenIds.insert(reqId)
                                cumulativeOutput += usage.outputTokens ?? 0
                                callCount += 1
                                if let m = msg.model, !m.isEmpty { model = m }
                            }
                        }
                    }
                }
            }

            if !buffer.isEmpty, let remaining = String(data: buffer, encoding: .utf8) {
                let trimmed = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty,
                   let ld = trimmed.data(using: .utf8),
                   let parsed = try? decoder.decode(JSONLLine.self, from: ld) {
                    if parsed.type == "assistant",
                       let msg = parsed.message,
                       msg.stopReason != nil,
                       let usage = msg.usage {
                        let reqId = parsed.requestId ?? UUID().uuidString
                        if !localSeenIds.contains(reqId) {
                            localSeenIds.insert(reqId)
                            cumulativeOutput += usage.outputTokens ?? 0
                            callCount += 1
                            if let m = msg.model, !m.isEmpty { model = m }
                        }
                    }
                }
            }

            seenRequestIds = localSeenIds
            result.totalOutputTokens = cumulativeOutput
            result.apiCallCount = callCount
            result.model = model
            lastOffset = fileSize
        }

        if let completed = lastCompletedLine, let usage = completed.message?.usage {
            result.lastInputTokens = usage.inputTokens ?? 0
            result.lastOutputTokens = usage.outputTokens ?? 0
            result.lastCacheCreation = usage.cacheCreationInputTokens ?? 0
            result.lastCacheRead = usage.cacheReadInputTokens ?? 0
            if let m = completed.message?.model, !m.isEmpty {
                result.model = m
            }
        }

        return result
    }

    func incrementalUpdate(fileURL: URL) -> ParseResult? {
        guard fileURL == currentFilePath else {
            return coldStart(fileURL: fileURL)
        }

        guard let fileHandle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? fileHandle.close() }

        let fileSize = fileHandle.seekToEndOfFile()
        guard fileSize > lastOffset else {
            if fileSize < lastOffset {
                return coldStart(fileURL: fileURL)
            }
            return nil
        }

        fileHandle.seek(toFileOffset: lastOffset)
        var newData = fileHandle.readDataToEndOfFile()

        if !partialLineBuffer.isEmpty {
            var combined = partialLineBuffer
            combined.append(newData)
            newData = combined
            partialLineBuffer = Data()
        }

        guard let text = String(data: newData, encoding: .utf8) else {
            lastOffset = fileSize
            return nil
        }

        var lines = text.components(separatedBy: "\n")

        if !text.hasSuffix("\n") {
            if let partial = lines.popLast(), !partial.isEmpty {
                partialLineBuffer = Data(partial.utf8)
            }
        }

        var newCalls = 0
        var newOutputTokens = 0
        var latestCompleted: JSONLLine?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8),
                  let parsed = try? decoder.decode(JSONLLine.self, from: data) else { continue }

            if parsed.type == "assistant",
               let msg = parsed.message,
               msg.stopReason != nil,
               let usage = msg.usage {
                let reqId = parsed.requestId ?? UUID().uuidString
                if !seenRequestIds.contains(reqId) {
                    seenRequestIds.insert(reqId)
                    newOutputTokens += usage.outputTokens ?? 0
                    newCalls += 1
                    latestCompleted = parsed
                }
            }
        }

        lastOffset = fileSize - UInt64(partialLineBuffer.count)

        guard let latest = latestCompleted, let usage = latest.message?.usage else {
            if newCalls == 0 { return nil }
            var r = ParseResult()
            r.totalOutputTokens = newOutputTokens
            r.apiCallCount = newCalls
            return r
        }

        var result = ParseResult()
        result.lastInputTokens = usage.inputTokens ?? 0
        result.lastOutputTokens = usage.outputTokens ?? 0
        result.lastCacheCreation = usage.cacheCreationInputTokens ?? 0
        result.lastCacheRead = usage.cacheReadInputTokens ?? 0
        result.totalOutputTokens = newOutputTokens
        result.apiCallCount = newCalls
        if let m = latest.message?.model, !m.isEmpty { result.model = m }

        return result
    }

    func reset() {
        currentFilePath = nil
        lastOffset = 0
        partialLineBuffer = Data()
        seenRequestIds.removeAll()
    }

    private func backwardScanForLastCompleted(fileHandle: FileHandle, fileSize: UInt64) -> JSONLLine? {
        let chunkSize = UInt64(Constants.coldStartChunkSize)
        var offset = fileSize

        while offset > 0 {
            let readSize = min(chunkSize, offset)
            offset -= readSize
            fileHandle.seek(toFileOffset: offset)
            let data = fileHandle.readData(ofLength: Int(readSize))

            guard let text = String(data: data, encoding: .utf8) else { continue }
            let lines = text.components(separatedBy: "\n").reversed()

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty,
                      let lineData = trimmed.data(using: .utf8),
                      let parsed = try? decoder.decode(JSONLLine.self, from: lineData) else { continue }

                if parsed.type == "assistant",
                   parsed.message?.stopReason != nil,
                   parsed.message?.usage != nil {
                    return parsed
                }
            }
        }
        return nil
    }

    private func processAllLines(_ lines: [String]) -> (ParseResult, JSONLLine?) {
        var result = ParseResult()
        var lastCompleted: JSONLLine?
        var localSeenIds = Set<String>()

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8),
                  let parsed = try? decoder.decode(JSONLLine.self, from: data) else { continue }

            if parsed.type == "assistant",
               let msg = parsed.message,
               msg.stopReason != nil,
               let usage = msg.usage {
                let reqId = parsed.requestId ?? UUID().uuidString
                if !localSeenIds.contains(reqId) {
                    localSeenIds.insert(reqId)
                    result.totalOutputTokens += usage.outputTokens ?? 0
                    result.apiCallCount += 1
                    lastCompleted = parsed
                    if let m = msg.model, !m.isEmpty { result.model = m }
                }
            }
        }

        seenRequestIds = localSeenIds
        return (result, lastCompleted)
    }

    private func splitLines(data: Data) -> [String] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return text.components(separatedBy: "\n")
    }
}
