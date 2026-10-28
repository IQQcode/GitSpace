import Foundation
import GSInfra

/// 仓库条目（工作区配置的一部分，JSON 持久化）。
public struct ManagedRepoConfig: Codable, Sendable, Identifiable, Hashable {
    public var path: String
    public var name: String
    public var id: String { path }

    public init(path: String, name: String? = nil) {
        self.path = path
        self.name = name ?? URL(fileURLWithPath: path).lastPathComponent
    }
}

/// 工作区配置（TechStack §6.2：JSON、可读可导出可手工备份、重启恢复）。
public struct WorkspaceConfig: Codable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var repos: [ManagedRepoConfig]
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, repos: [ManagedRepoConfig], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.repos = repos
        self.createdAt = createdAt
    }
}

/// 工作区配置存储：`~/Library/Application Support/GitSpace/workspaces/workspaces.json`。
public final class WorkspaceStore: Sendable {
    public static let shared = WorkspaceStore()

    private let fileURL: URL

    public init(directory: URL = GSPaths.workspacesDirectory) {
        fileURL = directory.appendingPathComponent("workspaces.json")
    }

    public func loadAll() -> [WorkspaceConfig] {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([WorkspaceConfig].self, from: data)) ?? []
    }

    public func saveAll(_ configs: [WorkspaceConfig]) {
        lock.lock()
        defer { lock.unlock() }
        do {
            try GSPaths.ensureDirectory(fileURL.deletingLastPathComponent())
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(configs)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // 配置写失败不中断会话，下次保存重试。
        }
    }

    private let lock = NSLock()
}
