import Foundation

/// 一条写操作日志（MRD 10.2-G：所有写操作本地留痕，可回溯）。
public struct OperationLogEntry: Codable, Sendable, Equatable {
    public var timestamp: Date
    public var repoName: String?
    public var action: String
    public var result: String // success / failure / cancelled
    public var durationMs: Int
    public var detail: String?

    public init(timestamp: Date = Date(), repoName: String?, action: String, result: String, durationMs: Int, detail: String?) {
        self.timestamp = timestamp
        self.repoName = repoName
        self.action = action
        self.result = result
        self.durationMs = durationMs
        self.detail = detail
    }
}

/// 操作日志：JSONL 按日滚动，写入 `logs/ops-yyyy-MM-dd.jsonl`。
public actor OperationLog {
    public static let shared = OperationLog(directory: GSPaths.logsDirectory)

    private let directory: URL
    private let encoder: JSONEncoder
    private let formatter: DateFormatter

    public init(directory: URL) {
        self.directory = directory
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        self.formatter = formatter
    }

    public func record(_ entry: OperationLogEntry) {
        do {
            try GSPaths.ensureDirectory(directory)
            let file = directory
                .appendingPathComponent("ops-\(formatter.string(from: entry.timestamp)).jsonl")
            let data = try encoder.encode(entry)
            var line = data
            line.append(0x0A)
            if FileManager.default.fileExists(atPath: file.path) {
                let handle = try FileHandle(forWritingTo: file)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
            } else {
                try line.write(to: file, options: .atomic)
            }
        } catch {
            // 日志失败不允许影响业务操作本身。
        }
    }

    public func recordSuccess(repoName: String?, action: String, durationMs: Int, detail: String? = nil) {
        record(OperationLogEntry(repoName: repoName, action: action, result: "success", durationMs: durationMs, detail: detail))
    }

    public func recordFailure(repoName: String?, action: String, durationMs: Int, detail: String?) {
        record(OperationLogEntry(repoName: repoName, action: action, result: "failure", durationMs: durationMs, detail: detail))
    }

    public func recentEntries(limit: Int = 200) -> [OperationLogEntry] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))?
            .filter { $0.lastPathComponent.hasPrefix("ops-") && $0.pathExtension == "jsonl" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent } ?? []
        var entries: [OperationLogEntry] = []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for file in files {
            guard let data = try? Data(contentsOf: file) else { continue }
            for lineData in data.split(separator: 0x0A) {
                if let entry = try? decoder.decode(OperationLogEntry.self, from: Data(lineData)) {
                    entries.append(entry)
                }
            }
            if entries.count >= limit { break }
        }
        return Array(entries.prefix(limit))
    }
}
