import Foundation

// MARK: - bisect 二分查找（Story-1031-mcp：Agent 常用读写工作流）

/// `git bisect good|bad|skip` 标记。
public enum BisectMark: String, Sendable {
    case good
    case bad
    case skip
}

extension GitRepository {
    /// 开始二分查找。前置检查：工作区必须干净——bisect 会来回 checkout，
    /// 脏区可能中途失败产生半完成状态（对齐 MRD 10.2-G「崩溃后不处于半完成状态」）。
    @discardableResult
    public func bisectStart(bad: String?, good: String?) async throws -> String {
        let status = try await status()
        if !status.isClean {
            throw GitError.uncommittedChanges(message: "工作区有未提交改动，二分查找前请先 stash 或提交")
        }
        var arguments = ["bisect", "start"]
        if let bad, !bad.isEmpty { arguments.append(bad) }
        if let good, !good.isEmpty { arguments.append(good) }
        let output = try await runWrite(arguments, action: "bisect.start")
        return output.stdout
    }

    /// 标记好/坏/跳过，返回 `git bisect log` 原文（含剩余范围；定位完成时含
    /// 「# first bad commit: [sha]」结论行，调用方可直接解析）。
    @discardableResult
    public func bisectMark(_ mark: BisectMark, rev: String? = nil) async throws -> String {
        var arguments = ["bisect", mark.rawValue]
        if let rev, !rev.isEmpty { arguments.append(rev) }
        try await runWrite(arguments, action: "bisect.mark")
        return try await bisectLog()
    }

    /// 结束二分，回到开始前的 HEAD。
    public func bisectReset() async throws {
        try await runWrite(["bisect", "reset"], action: "bisect.reset")
    }

    /// 二分过程日志（读操作，未在二分中时 git 报错原样抛出）。
    public func bisectLog() async throws -> String {
        let output = try await runner.run(directory: root, arguments: ["bisect", "log"], options: .quick)
        return output.stdout
    }
}

// MARK: - cherry-pick / revert（Story-1031-mcp）

extension GitRepository {
    /// 摘取一个提交到当前分支。冲突时返回 `.conflicts` 并进入既有冲突流程
    /// （resolveConflict / markConflictResolved → commitMerge，或 abortPick）。
    @discardableResult
    public func cherryPick(sha: String, noCommit: Bool = false) async throws -> MergeOutcome {
        try await pick(arguments: ["cherry-pick"] + (noCommit ? ["-n"] : []) + [sha], action: "cherry-pick")
    }

    /// 生成反向提交撤销一个提交（不重写历史）。冲突时返回 `.conflicts`。
    @discardableResult
    public func revert(sha: String, noCommit: Bool = false) async throws -> MergeOutcome {
        try await pick(arguments: ["revert", "--no-edit"] + (noCommit ? ["-n"] : []) + [sha], action: "revert")
    }

    /// 中止进行中的 cherry-pick / revert（经 rev-parse --git-dir 定位真实 gitdir，
    /// 兼容 worktree / submodule 场景）。
    public func abortPick() async throws {
        let gitDirOutput = try await runner.run(directory: root, arguments: ["rev-parse", "--git-dir"], options: .quick)
        let gitDirName = gitDirOutput.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let gitDir = gitDirName.hasPrefix("/")
            ? URL(fileURLWithPath: gitDirName)
            : root.appendingPathComponent(gitDirName)
        let fs = FileManager.default
        if fs.fileExists(atPath: gitDir.appendingPathComponent("CHERRY_PICK_HEAD").path) {
            try await runWrite(["cherry-pick", "--abort"], action: "cherry-pick.abort")
        } else if fs.fileExists(atPath: gitDir.appendingPathComponent("REVERT_HEAD").path) {
            try await runWrite(["revert", "--abort"], action: "revert.abort")
        } else {
            throw GitError.failed(exitCode: 0, stderr: "当前没有进行中的 cherry-pick / revert")
        }
    }

    /// cherry-pick / revert 共用执行与结果判定（判定口径与 merge 一致：冲突返回 .conflicts）。
    /// 无 unmerged 路径的 conflict 报错（如「pick is now empty」）原样抛出，不伪装成冲突清单。
    private func pick(arguments: [String], action: String) async throws -> MergeOutcome {
        do {
            _ = try await runWrite(arguments, action: action)
            return .merged(newSHA: try await currentSHA())
        } catch let error as GitError {
            if case .conflict = error {
                let status = try await status()
                guard !status.unmerged.isEmpty else { throw error }
                return .conflicts(status.unmerged)
            }
            throw error
        }
    }
}
