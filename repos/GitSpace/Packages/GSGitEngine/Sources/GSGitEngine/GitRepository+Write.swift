import Foundation

// MARK: - 暂存与提交（MRD 10.2-C）

extension GitRepository {
    public func stageFiles(_ paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        try await runWrite(["add", "--"] + paths, action: "stage")
    }

    public func unstageFiles(_ paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        try await runWrite(["restore", "--staged", "--"] + paths, action: "unstage")
    }

    /// 块级暂存：`git diff` 拆块重组 → `git apply --cached`（TechStack §5.3，与 add -p 等价）。
    public func stageHunks(of file: FileDiff, hunkIDs: Set<Int>) async throws {
        guard let patch = file.patch(selectingHunkIDs: hunkIDs) else { return }
        var options = GitExecutionOptions(timeoutSeconds: 30)
        options.stdin = patch
        try await runWrite(["apply", "--cached", "--whitespace=nowarn", "-"], action: "stage.hunks", options: options)
    }

    /// 块级取消暂存：cached diff 拆块 → `git apply --cached --reverse`。
    public func unstageHunks(of file: FileDiff, hunkIDs: Set<Int>) async throws {
        guard let patch = file.patch(selectingHunkIDs: hunkIDs) else { return }
        var options = GitExecutionOptions(timeoutSeconds: 30)
        options.stdin = patch
        try await runWrite(["apply", "--cached", "--reverse", "--whitespace=nowarn", "-"], action: "unstage.hunks", options: options)
    }

    public enum DiscardScope: Sendable, Equatable {
        /// 仅工作区改动（tracked）
        case worktree(path: String)
        /// 暂存 + 工作区一起回到 HEAD
        case stagedAndWorktree(path: String)
        /// 删除未跟踪文件（UI 层二次确认）
        case untracked(path: String)
    }

    public func discard(_ scope: DiscardScope) async throws {
        switch scope {
        case .worktree(let path):
            try await runWrite(["restore", "--worktree", "--", path], action: "discard.worktree")
        case .stagedAndWorktree(let path):
            try await runWrite(["restore", "--source=HEAD", "--staged", "--worktree", "--", path], action: "discard.all")
        case .untracked(let path):
            try FileManager.default.removeItem(at: root.appendingPathComponent(path))
            await operationLogger?.recordSuccess(repoName: name, action: "discard.untracked", durationMs: 0, detail: path)
        }
    }

    /// 提交。钩子失败时抛 hookFailed 且原始输出完整带出（不吞错、不产生提交）。
    @discardableResult
    public func commit(message: String, amend: Bool) async throws -> String {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitError.nothingToCommit
        }
        let status = try await status()
        if status.unmerged.isEmpty && status.staged.isEmpty {
            throw GitError.nothingToCommit
        }
        var arguments = ["commit", "-m", message]
        if amend { arguments.append("--amend") }
        try await runWrite(arguments, action: amend ? "commit.amend" : "commit")
        return try await currentSHA()
    }

    /// 合并进行中（MERGE_HEAD 存在）时收尾提交。
    @discardableResult
    public func commitMerge() async throws -> String {
        try await runWrite(["commit", "--no-edit"], action: "merge.commit")
        return try await currentSHA()
    }
}

// MARK: - 同步（MRD 10.2-B）

extension GitRepository {
    public func fetchAll() async throws {
        try await runWrite(["fetch", "--all", "--prune"], action: "fetch", options: .network)
    }

    /// pull 双模式：默认 ff-only（安全）；merge 模式冲突时进入冲突流程。
    public func pull(mode: PullMode) async throws {
        let arguments: [String] = mode == .fastForwardOnly
            ? ["pull", "--ff-only"]
            : ["pull", "--no-rebase", "--no-edit"]
        try await runWrite(arguments, action: "pull.\(mode.rawValue)", options: .network)
    }

    /// 仅推送已配置上游的当前分支；非快进被拒不自动合并；永不 force。
    public func push() async throws {
        try await runWrite(["push"], action: "push", options: .network)
    }

    public func pushTag(name: String) async throws {
        try await runWrite(["push", "origin", name], action: "tag.push", options: .network)
    }
}

// MARK: - 分支（MRD 10.2-D）

extension GitRepository {
    public func createBranch(name: String, from startPoint: String?) async throws {
        var arguments = ["switch", "-c", name]
        if let startPoint, !startPoint.isEmpty { arguments.append(startPoint) }
        try await runWrite(arguments, action: "branch.create")
    }

    /// 切换前预检：工作区脏则抛 uncommittedChanges，由 UI 引导 stash 或取消（MRD 10.4-11）。
    public func switchBranch(name: String) async throws {
        let status = try await status()
        if !status.isClean {
            throw GitError.uncommittedChanges(message: "工作区有未提交改动，切换分支前请先 stash 或提交")
        }
        try await runWrite(["switch", name], action: "branch.switch")
    }

    /// force = true 时删除未合并分支，UI 层必须强确认。
    public func deleteBranch(name: String, force: Bool) async throws {
        try await runWrite(["branch", force ? "-D" : "-d", name], action: "branch.delete")
    }

    public func renameBranch(oldName: String, newName: String) async throws {
        try await runWrite(["branch", "-m", oldName, newName], action: "branch.rename")
    }

    /// 检出远程分支为本地分支并建立 upstream（git switch --track 的 DWIM 语义）。
    public func checkoutRemoteBranch(_ remote: RemoteBranchInfo) async throws {
        let status = try await status()
        if !status.isClean {
            throw GitError.uncommittedChanges(message: "工作区有未提交改动，检出远程分支前请先 stash 或提交")
        }
        let locals = try await localBranches()
        if locals.contains(where: { $0.name == remote.branchName }) {
            try await runWrite(["switch", remote.branchName], action: "branch.checkoutRemote")
        } else {
            try await runWrite(["switch", "--track", remote.name], action: "branch.checkoutRemote")
        }
    }
}

// MARK: - 合并与冲突（MRD 10.2-E）

extension GitRepository {
    @discardableResult
    public func merge(ref: String, style: MergeStyle = .auto) async throws -> MergeOutcome {
        var arguments = ["merge", "--no-edit"]
        switch style {
        case .fastForwardOnly: arguments.append("--ff-only")
        case .noFastForward: arguments.append("--no-ff")
        case .auto: break
        }
        arguments.append(ref)

        do {
            let output = try await runWrite(arguments, action: "merge")
            if output.stdout.contains("Fast-forward") { return .fastForward }
            if output.stdout.contains("Already up to date") { return .upToDate }
            return .merged(newSHA: try await currentSHA())
        } catch let error as GitError {
            if case .conflict = error {
                let status = try await status()
                return .conflicts(status.unmerged)
            }
            throw error
        }
    }

    /// 冲突选边：与 `git checkout --ours / --theirs` 结果一致（MRD 10.4-12）。
    public func resolveConflict(path: String, resolution: ConflictResolution) async throws {
        let flag: String
        switch resolution {
        case .ours: flag = "--ours"
        case .theirs: flag = "--theirs"
        case .mergeMarkers: flag = "--conflict=merge"
        }
        try await runWrite(["checkout", flag, "--", path], action: "conflict.\(resolution.rawValue)")
    }

    public func markConflictResolved(path: String) async throws {
        try await runWrite(["add", "--", path], action: "conflict.resolve")
    }

    /// 中止合并：工作区回到合并前（git merge --abort 语义）。
    public func abortMerge() async throws {
        try await runWrite(["merge", "--abort"], action: "merge.abort")
    }
}

// MARK: - stash 与 tag（MRD 10.2-F）

extension GitRepository {
    public func stashPush(message: String?) async throws {
        let status = try await status()
        if status.isClean { throw GitError.nothingToCommit }
        var arguments = ["stash", "push"]
        if let message, !message.isEmpty { arguments += ["-m", message] }
        try await runWrite(arguments, action: "stash.push")
    }

    public enum StashRestoreMode: String, Sendable {
        case pop   // 恢复并删除
        case apply // 恢复保留
    }

    public func stashRestore(index: Int, mode: StashRestoreMode) async throws {
        try await runWrite(["stash", mode == .pop ? "pop" : "apply", "stash@{\(index)}"], action: "stash.\(mode.rawValue)")
    }

    public func stashDrop(index: Int) async throws {
        try await runWrite(["stash", "drop", "stash@{\(index)}"], action: "stash.drop")
    }

    public func createTag(name: String, message: String?) async throws {
        let arguments: [String]
        if let message, !message.isEmpty {
            arguments = ["tag", "-a", name, "-m", message]
        } else {
            arguments = ["tag", name]
        }
        try await runWrite(arguments, action: "tag.create")
    }

    public func deleteTag(name: String) async throws {
        try await runWrite(["tag", "-d", name], action: "tag.delete")
    }
}
