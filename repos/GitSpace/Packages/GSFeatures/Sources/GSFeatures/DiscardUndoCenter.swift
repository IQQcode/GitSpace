import Foundation
import CryptoKit
import GSGitEngine
import GSIndex
import GSInfra

/// 丢弃撤销中心（EP04-F01）：
/// 丢弃前 `git stash create` 快照（不改动工作区与任何 ref）；未跟踪文件先备份再移入废纸篓；
/// 撤销时校验文件未被再次修改（丢弃后内容哈希比对），会话内 + 24 小时有效。
@MainActor
@Observable
public final class DiscardUndoCenter {
    /// 保留窗口（MRD §17.2 待定项：快照可能被 git gc 回收，超出后拒绝撤销）。
    static let validityInterval: TimeInterval = 24 * 60 * 60

    struct Record {
        let repoID: String
        let snapshotSHA: String?
        /// 未跟踪备份：< 工作区内路径, 备份文件 URL >
        let untrackedBackups: [String: URL]
        /// 丢弃完成时的内容哈希（撤销前校验是否被再次修改）。
        let postDiscardHashes: [String: String]
        let date: Date
    }

    /// 每仓保留最近一次丢弃记录。
    private var records: [String: Record] = [:]

    public init() {}

    // MARK: 丢弃入口（调用方必须先完成二次确认，MRD 10.2-G）

    /// 按文件丢弃（worktree / stagedAndWorktree / untracked）。
    public func discardFiles(repo: ManagedRepo, scopes: [GitRepository.DiscardScope]) async throws {
        guard let engine = repo.engine, !scopes.isEmpty else { return }
        let snapshot = try await engine.stashCreate(message: "GitSpace 丢弃快照 \(Self.timestampText())")
        var backups: [String: URL] = [:]
        for case .untracked(let path) in scopes {
            if let url = try backupUntracked(repo: repo, path: path) {
                backups[path] = url
            }
        }
        for scope in scopes {
            try await engine.discard(scope)
        }
        let hashes = try await collectHashes(repo: repo, scopes: scopes)
        records[repo.id] = Record(
            repoID: repo.id,
            snapshotSHA: snapshot,
            untrackedBackups: backups,
            postDiscardHashes: hashes,
            date: Date()
        )
    }

    /// 块级丢弃：选中 hunk 反向应用到工作区，同样走快照与撤销链路。
    public func discardHunks(repo: ManagedRepo, file: FileDiff, hunkIDs: Set<Int>) async throws {
        guard let engine = repo.engine else { return }
        let snapshot = try await engine.stashCreate(message: "GitSpace 丢弃快照 \(Self.timestampText())")
        try await engine.discardHunks(of: file, hunkIDs: hunkIDs)
        let affected = [file.path]
        let hashes = try await collectHashes(repo: repo, paths: affected)
        records[repo.id] = Record(
            repoID: repo.id,
            snapshotSHA: snapshot,
            untrackedBackups: [:],
            postDiscardHashes: hashes,
            date: Date()
        )
    }

    /// 「丢弃全部改动」：工作区改动回到 HEAD（有暂存的一起回到 HEAD）+ 未跟踪移入废纸篓。
    public func discardAll(repo: ManagedRepo) async throws {
        guard let engine = repo.engine, let status = repo.status else { return }
        var scopes: [GitRepository.DiscardScope] = []
        for entry in status.unstaged {
            scopes.append(entry.indexKind != nil ? .stagedAndWorktree(path: entry.path) : .worktree(path: entry.path))
        }
        for entry in status.untracked {
            scopes.append(.untracked(path: entry.path))
        }
        try await discardFiles(repo: repo, scopes: scopes)
    }

    // MARK: 撤销

    public func canUndo(repoID: String) -> Bool {
        guard let record = records[repoID] else { return false }
        return Date().timeIntervalSince(record.date) <= Self.validityInterval
    }

    /// 撤销最近一次丢弃。返回提示文案（含拒绝原因）。
    public func undo(repo: ManagedRepo) async -> String {
        guard let engine = repo.engine, let record = records[repo.id], canUndo(repoID: repo.id) else {
            return "没有可撤销的丢弃"
        }
        guard let snapshot = record.snapshotSHA else {
            return "该次丢弃没有可用快照（可能只有未跟踪文件），请从废纸篓手动恢复"
        }
        var restored = 0
        var rejected: [String] = []
        for (path, hash) in record.postDiscardHashes {
            // 撤销前校验：文件被再次修改则拒绝覆盖（EP04-F01 状态表）
            guard await currentHash(repo: repo, path: path) == hash else {
                rejected.append(path)
                continue
            }
            do {
                try await engine.restoreFromSnapshot(sha: snapshot, paths: [path])
                restored += 1
            } catch {
                rejected.append(path)
            }
        }
        // 未跟踪文件从备份还原（路径又被占用则拒绝）
        for (path, backup) in record.untrackedBackups {
            let target = repo.config.fileURL(path)
            guard !FileManager.default.fileExists(atPath: target.path) else {
                rejected.append(path)
                continue
            }
            do {
                try FileManager.default.createDirectory(
                    at: target.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try FileManager.default.copyItem(at: backup, to: target)
                restored += 1
            } catch {
                rejected.append(path)
            }
        }
        if restored == 0 && rejected.isEmpty {
            return "没有可恢复的文件"
        }
        if !rejected.isEmpty {
            return "已恢复 \(restored) 个文件；\(rejected.count) 个文件已被再次修改，未覆盖（快照 \(snapshot.prefix(7))）"
        }
        return "已恢复 \(restored) 个文件到丢弃前状态"
    }

    // MARK: 内部

    private func backupUntracked(repo: ManagedRepo, path: String) throws -> URL? {
        let source = repo.config.fileURL(path)
        guard FileManager.default.fileExists(atPath: source.path) else { return nil }
        let dir = try GSPaths.ensureDirectory(
            GSPaths.appSupportRoot.appendingPathComponent("discards", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        let target = dir.appendingPathComponent((path as NSString).lastPathComponent)
        try FileManager.default.copyItem(at: source, to: target)
        return target
    }

    /// 丢弃后的内容哈希（撤销校验基准）。
    private func collectHashes(repo: ManagedRepo, scopes: [GitRepository.DiscardScope]) async throws -> [String: String] {
        let tracked = scopes.compactMap { scope -> String? in
            switch scope {
            case .worktree(let path), .stagedAndWorktree(let path): return path
            case .untracked: return nil
            }
        }
        return try await collectHashes(repo: repo, paths: tracked)
    }

    private func collectHashes(repo: ManagedRepo, paths: [String]) async throws -> [String: String] {
        var hashes: [String: String] = [:]
        for path in paths {
            hashes[path] = await currentHash(repo: repo, path: path)
        }
        return hashes
    }

    private func currentHash(repo: ManagedRepo, path: String) async -> String? {
        let url = repo.config.fileURL(path)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return Self.hash(of: data)
    }

    static func hash(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func timestampText() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }
}

extension ManagedRepoConfig {
    /// 展开用户目录后的绝对路径。
    public var expandedPath: String {
        (path as NSString).expandingTildeInPath
    }

    /// 仓库内相对路径对应的文件 URL。
    public func fileURL(_ relative: String) -> URL {
        URL(fileURLWithPath: expandedPath).appendingPathComponent(relative)
    }
}
