import Foundation
import GSInfra

/// 单仓门面（actor）：同仓命令串行，跨仓天然并行（TechStack §7.1）。
/// 只读命令不写操作日志；写命令统一经 runWrite 留痕。
public actor GitRepository {
    public let root: URL
    public let name: String
    private let runner: GitProcessRunner
    /// 测试可注入 nil 关闭日志。
    public var operationLogger: OperationLog?

    public init?(path: URL, runner: GitProcessRunner = .shared, operationLogger: OperationLog? = .shared) {
        guard FileManager.default.fileExists(atPath: path.appendingPathComponent(".git").path) else { return nil }
        self.root = path
        self.name = path.lastPathComponent
        self.runner = runner
        self.operationLogger = operationLogger
    }

    // MARK: - 状态

    public func status() async throws -> RepoStatus {
        let raw = try await runner.run(
            directory: root,
            arguments: ["status", "--porcelain=v2", "--branch", "--untracked-files=all", "-z"],
            options: .quick
        )
        let mergeInProgress = (try? await runner.runRaw(directory: root, arguments: ["rev-parse", "-q", "--verify", "MERGE_HEAD"], options: .quick))?
            .succeeded ?? false
        return StatusParser.parse(Data(raw.stdout.utf8), isMergeInProgress: mergeInProgress)
    }

    public func currentSHA() async throws -> String {
        let output = try await runner.run(directory: root, arguments: ["rev-parse", "HEAD"], options: .quick)
        return output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func hasRemote() async throws -> Bool {
        let output = try await runner.run(directory: root, arguments: ["remote"], options: .quick)
        return !output.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - 提交历史

    /// 时间窗口默认近 3 个月（MRD 10.6 超大仓截断策略），--all 覆盖所有分支。
    public func commits(limit: Int, since: Date?, allBranches: Bool = true) async throws -> [CommitInfo] {
        var arguments = ["log", "--no-color", "--date-order"]
        if allBranches { arguments.append("--all") }
        if let since {
            arguments.append("--since=@\(Int(since.timeIntervalSince1970))")
        }
        arguments += ["-n", String(limit), "--pretty=format:\(CommitLogParser.prettyFormat)"]
        let output = try await runner.run(directory: root, arguments: arguments, options: .quick)
        return CommitLogParser.parse(output.stdout)
    }

    public func commitDetail(sha: String) async throws -> [FileDiff] {
        let meta = try await runner.run(directory: root, arguments: ["rev-list", "--parents", "-n", "1", sha], options: .quick)
        let parents = meta.stdout.split(separator: " ").dropFirst()
        let arguments: [String]
        if parents.isEmpty {
            arguments = ["diff-tree", "--root", "--no-color", "-p", sha]
        } else {
            // merge 提交按第一父提交展示改动（P1 再做 combined diff）
            arguments = ["diff", "--no-color", "\(sha)^1", sha]
        }
        let output = try await runner.run(directory: root, arguments: arguments, options: .quick)
        return DiffParser.parse(output.stdout)
    }

    // MARK: - 工作区 diff

    public func worktreeDiff() async throws -> [FileDiff] {
        let output = try await runner.run(directory: root, arguments: ["diff", "--no-color"], options: .quick)
        return DiffParser.parse(output.stdout)
    }

    public func stagedDiff() async throws -> [FileDiff] {
        let output = try await runner.run(directory: root, arguments: ["diff", "--cached", "--no-color"], options: .quick)
        return DiffParser.parse(output.stdout)
    }

    /// 未跟踪文件的伪 diff（直接读文件内容，不走 git diff --no-index）。
    public func untrackedFileDiff(path: String) async throws -> FileDiff? {
        let url = root.appendingPathComponent(path)
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8)
        else { return nil }
        let header = [
            "diff --git a/\(path) b/\(path)",
            "new file mode 100644",
            "--- /dev/null",
            "+++ b/\(path)"
        ]
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map { DiffLine(raw: "+" + String($0)) }
        let hunk = DiffHunk(id: 0, header: "@@ -0,0 +1,\(lines.count) @@ — 未跟踪文件预览", lines: lines)
        return FileDiff(path: path, kind: .added, headerLines: header, hunks: lines.isEmpty ? [] : [hunk])
    }

    // MARK: - 分支 / 远程 / 标签 / stash

    public func localBranches() async throws -> [BranchInfo] {
        let format = "%(refname)%00%(refname:short)%00%(objectname)%00%(objectname:short)%00%(upstream)%00%(upstream:track)%00%(HEAD)%00%(subject)"
        let output = try await runner.run(directory: root, arguments: ["for-each-ref", "--format=\(format)", "refs/heads"], options: .quick)
        return RefParser.parseLocalBranches(output.stdout)
    }

    public func remoteBranches() async throws -> [RemoteBranchInfo] {
        let format = "%(refname)%00%(refname:short)%00%(objectname)%00%(objectname:short)%00%(upstream)%00%(upstream:track)%00%(HEAD)%00%(subject)"
        let output = try await runner.run(directory: root, arguments: ["for-each-ref", "--format=\(format)", "refs/remotes"], options: .quick)
        return RefParser.parseRemoteBranches(output.stdout)
    }

    public func tags() async throws -> [TagInfo] {
        let format = "%(refname)%00%(refname:short)%00%(objectname:short)%00%(creatordate:iso8601)%00%(contents:subject)%00%(objecttype)"
        let output = try await runner.run(directory: root, arguments: ["for-each-ref", "--sort=-creatordate", "--format=\(format)", "refs/tags"], options: .quick)
        return RefParser.parseTags(output.stdout)
    }

    public func stashes() async throws -> [StashInfo] {
        let output = try await runner.run(
            directory: root,
            arguments: ["stash", "list", "--pretty=format:%gd%x1f%ct%x1f%gs%x1e"],
            options: .quick
        )
        return RefParser.parseStashes(output.stdout)
    }

    public func stashDiff(index: Int) async throws -> [FileDiff] {
        let output = try await runner.run(directory: root, arguments: ["stash", "show", "-p", "--no-color", "stash@{\(index)}"], options: .quick)
        return DiffParser.parse(output.stdout)
    }

    // MARK: - 写操作执行器（统一留痕）

    func runWrite(_ arguments: [String], action: String, options: GitExecutionOptions = .quick) async throws -> GitOutput {
        let startedAt = Date()
        do {
            let output = try await runner.run(directory: root, arguments: arguments, options: options)
            await operationLogger?.recordSuccess(
                repoName: name,
                action: action,
                durationMs: Int(Date().timeIntervalSince(startedAt) * 1000),
                detail: arguments.joined(separator: " ")
            )
            return output
        } catch {
            await operationLogger?.recordFailure(
                repoName: name,
                action: action,
                durationMs: Int(Date().timeIntervalSince(startedAt) * 1000),
                detail: "\(arguments.joined(separator: " ")) :: \(String(describing: error))"
            )
            throw error
        }
    }
}
