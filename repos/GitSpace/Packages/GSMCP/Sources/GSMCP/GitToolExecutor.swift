import Foundation
import GSGitEngine

/// 工具执行体：name/arguments → 面向 Agent 的文本结果。
/// 只做「引擎调用 + 文本排版」，不做安全判断（总开关与 confirm 检查在 MCPServer）。
enum GitToolExecutor {
    static func execute(name: String, arguments: JSONValue, repo: GitRepository) async throws -> String {
        switch name {
        // MARK: 状态
        case "git_status":
            return MCPFormat.status(try await repo.status())
        case "git_current_sha":
            return try await repo.currentSHA()
        case "git_has_remote":
            return try await repo.hasRemote() ? "true（已配置远端）" : "false（未配置远端）"

        // MARK: 历史
        case "git_commits":
            let limit = arguments["limit"]?.intValue ?? 50
            let sinceDays = arguments["since_days"]?.intValue
            let allBranches = arguments["all_branches"]?.boolValue ?? true
            let since = sinceDays.map { Date().addingTimeInterval(TimeInterval(-$0) * 86_400) }
            let commits = try await repo.commits(limit: limit, since: since, allBranches: allBranches)
            guard !commits.isEmpty else { return "（无提交记录）" }
            return MCPFormat.commits(commits)
        case "git_commit_detail":
            let sha = try requiredString("sha", in: arguments)
            let diffs = try await repo.commitDetail(sha: sha)
            return MCPFormat.diffSummary(diffs) + "\n\n" + MCPFormat.diffs(diffs)
        case "git_file_history":
            let path = try requiredString("path", in: arguments)
            let limit = arguments["limit"]?.intValue ?? 200
            return MCPFormat.commits(try await repo.fileHistory(path: path, limit: limit))
        case "git_file_change_at":
            let sha = try requiredString("sha", in: arguments)
            let path = try requiredString("path", in: arguments)
            return MCPFormat.diffs(try await repo.fileChangeAt(sha: sha, path: path))
        case "git_show_file":
            let rev = try requiredString("rev", in: arguments)
            let path = try requiredString("path", in: arguments)
            return try await repo.showFileContent(rev: rev, path: path)
        case "git_refs_containing":
            let sha = try requiredString("sha", in: arguments)
            return MCPFormat.refsContaining(try await repo.refsContaining(sha: sha))
        case "git_commit_template":
            if let template = try await repo.commitTemplate() { return template }
            return "（未配置 commit.template）"

        // MARK: diff
        case "git_worktree_diff":
            return MCPFormat.diffs(try await repo.worktreeDiff())
        case "git_staged_diff":
            return MCPFormat.diffs(try await repo.stagedDiff())
        case "git_untracked_file_diff":
            let path = try requiredString("path", in: arguments)
            if let diff = try await repo.untrackedFileDiff(path: path) {
                return MCPFormat.diffs([diff])
            }
            return "（文件不存在或不可读：\(path)）"
        case "git_diff_against_revision":
            let rev = try requiredString("rev", in: arguments)
            let path = try requiredString("path", in: arguments)
            return MCPFormat.diffs(try await repo.diffAgainstRevision(rev: rev, path: path))

        // MARK: 分支 / tag / stash
        case "git_local_branches":
            return MCPFormat.branches(try await repo.localBranches())
        case "git_remote_branches":
            return MCPFormat.remoteBranches(try await repo.remoteBranches())
        case "git_tags":
            return MCPFormat.tags(try await repo.tags())
        case "git_stashes":
            return MCPFormat.stashes(try await repo.stashes())
        case "git_stash_diff":
            let index = try requiredInt("index", in: arguments)
            return MCPFormat.diffs(try await repo.stashDiff(index: index))
        case "git_blame":
            let path = try requiredString("path", in: arguments)
            let rev = arguments["rev"]?.stringValue
            return MCPFormat.blame(try await repo.blame(rev: rev, path: path))

        // MARK: 冲突读取
        case "git_conflict_stage_contents":
            let path = try requiredString("path", in: arguments)
            let contents = try await repo.conflictStageContents(path: path)
            var lines: [String] = []
            lines.append("=== base（stage 1）===")
            lines.append(contents.base ?? "（不存在）")
            lines.append("=== ours（stage 2，当前分支）===")
            lines.append(contents.ours ?? "（不存在）")
            lines.append("=== theirs（stage 3，对方分支）===")
            lines.append(contents.theirs ?? "（不存在）")
            return lines.joined(separator: "\n")

        // MARK: 写：暂存与提交
        case "git_stage":
            try await repo.stageFiles(try requiredStringArray("paths", in: arguments))
            return "已暂存。当前状态：\n" + MCPFormat.status(try await repo.status())
        case "git_unstage":
            try await repo.unstageFiles(try requiredStringArray("paths", in: arguments))
            return "已取消暂存。当前状态：\n" + MCPFormat.status(try await repo.status())
        case "git_commit":
            let message = try requiredString("message", in: arguments)
            let amend = arguments["amend"]?.boolValue ?? false
            let sha = try await repo.commit(message: message, amend: amend)
            return "提交完成：\(sha)"
        case "git_commit_merge":
            let sha = try await repo.commitMerge()
            return "合并收尾提交完成：\(sha)"

        // MARK: 写：丢弃与恢复
        case "git_discard":
            let scopeName = try requiredString("scope", in: arguments)
            let path = try requiredString("path", in: arguments)
            let scope: GitRepository.DiscardScope
            switch scopeName {
            case "worktree": scope = .worktree(path: path)
            case "stagedAndWorktree": scope = .stagedAndWorktree(path: path)
            case "untracked": scope = .untracked(path: path)
            default: throw MCPServerError.missingParameter("scope（worktree / stagedAndWorktree / untracked）")
            }
            try await repo.discard(scope)
            return "已丢弃：\(path)（scope=\(scopeName)）"
        case "git_stash_snapshot":
            let sha = try await repo.stashCreate(message: arguments["message"]?.stringValue)
            return sha.map { "快照已创建：\($0)" } ?? "（无可快照内容：工作区干净或仅未跟踪改动）"
        case "git_restore_from_snapshot":
            let sha = try requiredString("sha", in: arguments)
            let paths = try requiredStringArray("paths", in: arguments)
            try await repo.restoreFromSnapshot(sha: sha, paths: paths)
            return "已从快照 \(sha) 恢复 \(paths.count) 个文件"
        case "git_restore_file":
            let rev = try requiredString("rev", in: arguments)
            let path = try requiredString("path", in: arguments)
            try await repo.restoreFile(rev: rev, path: path)
            return "已把 \(path) 恢复到 \(rev) 版本"

        // MARK: 写：stash
        case "git_stash_push":
            try await repo.stashPush(message: arguments["message"]?.stringValue)
            return "已存入 stash。当前列表：\n" + MCPFormat.stashes(try await repo.stashes())
        case "git_stash_restore":
            let index = try requiredInt("index", in: arguments)
            let mode = arguments["mode"]?.stringValue == "apply"
                ? GitRepository.StashRestoreMode.apply
                : GitRepository.StashRestoreMode.pop
            try await repo.stashRestore(index: index, mode: mode)
            return "已恢复 stash@{\(index)}（mode=\(mode.rawValue)）"
        case "git_stash_drop":
            let index = try requiredInt("index", in: arguments)
            try await repo.stashDrop(index: index)
            return "已删除 stash@{\(index)}"

        // MARK: 写：分支
        case "git_create_branch":
            let name = try requiredString("name", in: arguments)
            try await repo.createBranch(name: name, from: arguments["from"]?.stringValue)
            return "分支已创建：\(name)"
        case "git_switch_branch":
            let name = try requiredString("name", in: arguments)
            try await repo.switchBranch(name: name)
            return "已切换到 \(name)"
        case "git_delete_branch":
            let name = try requiredString("name", in: arguments)
            try await repo.deleteBranch(name: name, force: arguments["force"]?.boolValue ?? false)
            return "分支已删除：\(name)"
        case "git_rename_branch":
            let old = try requiredString("old", in: arguments)
            let new = try requiredString("new", in: arguments)
            try await repo.renameBranch(oldName: old, newName: new)
            return "分支已重命名：\(old) → \(new)"
        case "git_checkout_remote_branch":
            let name = try requiredString("name", in: arguments)
            let remotes = try await repo.remoteBranches()
            guard let target = remotes.first(where: { $0.name == name }) else {
                throw GitError.missingBranch(name: name)
            }
            try await repo.checkoutRemoteBranch(target)
            return "已检出远程分支 \(name) 为本地分支并建立跟踪"
        case "git_checkout_commit":
            let sha = try requiredString("sha", in: arguments)
            try await repo.checkoutDetached(sha: sha)
            return "已检出 \(sha)（detached HEAD；git_bisect_reset 不适用，请用 git_switch_branch 回到分支）"

        // MARK: 写：合并与冲突
        case "git_merge":
            let ref = try requiredString("ref", in: arguments)
            let style = MCPMergeStyle(arguments["style"]?.stringValue)
            let outcome = try await repo.merge(ref: ref, style: style, message: arguments["message"]?.stringValue)
            return MCPFormat.outcome(outcome, verb: "合并")
        case "git_resolve_conflict":
            let path = try requiredString("path", in: arguments)
            let resolution = MCPConflictResolution(try requiredString("resolution", in: arguments))
            try await repo.resolveConflict(path: path, resolution: resolution)
            return "已按 \(resolution.rawValue) 处理冲突文件 \(path)（标记已解决请调 git_mark_conflict_resolved）"
        case "git_mark_conflict_resolved":
            let path = try requiredString("path", in: arguments)
            try await repo.markConflictResolved(path: path)
            return "已标记 \(path) 解决"
        case "git_abort_merge":
            try await repo.abortMerge()
            return "合并已中止，工作区回到合并前"
        case "git_abort_pick":
            try await repo.abortPick()
            return "cherry-pick / revert 已中止，工作区回到操作前"

        // MARK: 写：同步
        case "git_fetch":
            try await repo.fetchAll()
            return "fetch 完成"
        case "git_pull":
            let mode = arguments["mode"]?.stringValue == "merge"
                ? PullMode.merge
                : PullMode.fastForwardOnly
            try await repo.pull(mode: mode)
            return "pull 完成（mode=\(mode.rawValue)）\n" + MCPFormat.status(try await repo.status())
        case "git_push":
            try await repo.push()
            return "push 完成"
        case "git_push_tag":
            let name = try requiredString("name", in: arguments)
            try await repo.pushTag(name: name, remote: arguments["remote"]?.stringValue ?? "origin")
            return "tag \(name) 已推送"
        case "git_delete_remote_tag":
            let name = try requiredString("name", in: arguments)
            try await repo.deleteRemoteTag(name: name, remote: arguments["remote"]?.stringValue ?? "origin")
            return "远端 tag \(name) 已删除"
        case "git_create_tag":
            let name = try requiredString("name", in: arguments)
            try await repo.createTag(name: name, message: arguments["message"]?.stringValue, at: arguments["at"]?.stringValue)
            return "tag 已创建：\(name)"
        case "git_delete_tag":
            let name = try requiredString("name", in: arguments)
            try await repo.deleteTag(name: name)
            return "tag 已删除：\(name)"

        // MARK: 写：bisect
        case "git_bisect_start":
            let output = try await repo.bisectStart(bad: arguments["bad"]?.stringValue, good: arguments["good"]?.stringValue)
            return "二分已开始。git 输出：\n\(output.isEmpty ? "（无）" : output)\n提示：逐步用 git_bisect_good / git_bisect_bad 标记，git_bisect_log 查看进度。"
        case "git_bisect_good":
            return try await repo.bisectMark(.good, rev: arguments["rev"]?.stringValue)
        case "git_bisect_bad":
            return try await repo.bisectMark(.bad, rev: arguments["rev"]?.stringValue)
        case "git_bisect_skip":
            return try await repo.bisectMark(.skip, rev: arguments["rev"]?.stringValue)
        case "git_bisect_reset":
            try await repo.bisectReset()
            return "二分已结束，回到开始前的 HEAD"

        // MARK: 写：cherry-pick / revert
        case "git_cherry_pick":
            let sha = try requiredString("sha", in: arguments)
            let outcome = try await repo.cherryPick(sha: sha, noCommit: arguments["no_commit"]?.boolValue ?? false)
            return MCPFormat.outcome(outcome, verb: "cherry-pick")
        case "git_revert":
            let sha = try requiredString("sha", in: arguments)
            let outcome = try await repo.revert(sha: sha, noCommit: arguments["no_commit"]?.boolValue ?? false)
            return MCPFormat.outcome(outcome, verb: "revert")

        // MARK: 读：bisect 状态
        case "git_bisect_log":
            return try await repo.bisectLog()

        default:
            throw MCPServerError.missingParameter("未知工具 \(name)（Registry 与 Executor 不同步）")
        }
    }

    // MARK: - 参数提取

    private static func requiredString(_ key: String, in arguments: JSONValue) throws -> String {
        guard let value = arguments[key]?.stringValue, !value.isEmpty else {
            throw MCPServerError.missingParameter(key)
        }
        return value
    }

    private static func requiredInt(_ key: String, in arguments: JSONValue) throws -> Int {
        guard let value = arguments[key]?.intValue else {
            throw MCPServerError.missingParameter(key)
        }
        return value
    }

    private static func requiredStringArray(_ key: String, in arguments: JSONValue) throws -> [String] {
        guard let values = arguments[key]?.arrayValue?.compactMap(\.stringValue), !values.isEmpty else {
            throw MCPServerError.missingParameter("\(key)（字符串数组）")
        }
        return values
    }
}

private func MCPMergeStyle(_ raw: String?) -> MergeStyle {
    switch raw {
    case "ff-only": return .fastForwardOnly
    case "no-ff": return .noFastForward
    default: return .auto
    }
}

private func MCPConflictResolution(_ raw: String) -> ConflictResolution {
    switch raw {
    case "ours": return .ours
    case "theirs": return .theirs
    default: return .mergeMarkers
    }
}

// MARK: - 文本排版（面向 Agent 的可读输出）

enum MCPFormat {
    static func status(_ status: RepoStatus) -> String {
        var lines: [String] = []
        if let branch = status.branch {
            lines.append("分支：\(branch)\(status.detached ? "（detached）" : "")")
        } else if status.detached {
            lines.append("HEAD：detached 状态")
        }
        if status.isMergeInProgress { lines.append("⚠ 合并进行中（存在 MERGE_HEAD），请处理冲突后 git_commit_merge，或 git_abort_merge") }
        if let upstream = status.upstream, status.ahead > 0 || status.behind > 0 {
            lines.append("上游：\(upstream)（ahead \(status.ahead) / behind \(status.behind)）")
        } else if let upstream = status.upstream {
            lines.append("上游：\(upstream)（已同步）")
        }
        if !status.staged.isEmpty {
            lines.append("已暂存：")
            lines.append(contentsOf: status.staged.map { "  \($0.indexKind?.rawValue ?? "?") \($0.path)" })
        }
        if !status.unstaged.isEmpty {
            lines.append("未暂存：")
            lines.append(contentsOf: status.unstaged.map { "  \($0.worktreeKind?.rawValue ?? "?") \($0.path)" })
        }
        if !status.untracked.isEmpty {
            lines.append("未跟踪：")
            lines.append(contentsOf: status.untracked.map { "  ? \($0.path)" })
        }
        if !status.unmerged.isEmpty {
            lines.append("冲突（未解决）：")
            lines.append(contentsOf: status.unmerged.map { "  \($0.code) \($0.path)" })
        }
        if status.isClean { lines.append("工作区干净") }
        return lines.joined(separator: "\n")
    }

    static func commits(_ commits: [CommitInfo]) -> String {
        guard !commits.isEmpty else { return "（无提交记录）" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return commits.map { commit in
            let date = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(commit.authorTimestamp)))
            let mergeTag = commit.isMerge ? " (merge)" : ""
            return "\(commit.shortSHA)  \(date)  \(commit.authorName)  \(commit.subject)\(mergeTag)"
        }.joined(separator: "\n")
    }

    static func diffSummary(_ diffs: [FileDiff]) -> String {
        guard !diffs.isEmpty else { return "（无文件改动）" }
        let lines = diffs.map { "\($0.kind.rawValue) \($0.path) (+\($0.additions) -\($0.deletions))" }
        return "改动文件：\n" + lines.joined(separator: "\n")
    }

    static func diffs(_ diffs: [FileDiff]) -> String {
        guard !diffs.isEmpty else { return "（无改动）" }
        return diffs.compactMap { diff in
            guard let patch = diff.fullPatch() else { return nil }
            return String(decoding: patch, as: UTF8.self)
        }.joined(separator: "\n")
    }

    static func branches(_ branches: [BranchInfo]) -> String {
        guard !branches.isEmpty else { return "（无本地分支）" }
        return branches.map { branch in
            var parts = [branch.isCurrent ? "* \(branch.name)" : "  \(branch.name)"]
            parts.append(branch.headSHA.prefix(7).description)
            if branch.ahead > 0 || branch.behind > 0 { parts.append("↑\(branch.ahead) ↓\(branch.behind)") }
            if let upstream = branch.upstream { parts.append("→ \(upstream)") }
            parts.append(branch.subject)
            return parts.joined(separator: "  ")
        }.joined(separator: "\n")
    }

    static func remoteBranches(_ branches: [RemoteBranchInfo]) -> String {
        guard !branches.isEmpty else { return "（无远程分支）" }
        return branches.map { "\($0.name)  \($0.headSHA.prefix(7))  \($0.subject)" }.joined(separator: "\n")
    }

    static func tags(_ tags: [TagInfo]) -> String {
        guard !tags.isEmpty else { return "（无 tag）" }
        return tags.map { "\($0.name)  \($0.shortSHA)  \($0.dateText)  \($0.isAnnotated ? "annotated" : "lightweight")  \($0.subject)" }.joined(separator: "\n")
    }

    static func stashes(_ stashes: [StashInfo]) -> String {
        guard !stashes.isEmpty else { return "（stash 为空）" }
        return stashes.map { "stash@{\($0.index)}  \($0.message)" }.joined(separator: "\n")
    }

    static func blame(_ result: BlameResult) -> String {
        guard !result.lines.isEmpty else { return "（无可 blame 内容）" }
        return result.lines.map { line in
            "\(String(line.sha.prefix(7)))  L\(line.lineNumber)  \(line.content)"
        }.joined(separator: "\n")
    }

    static func refsContaining(_ refs: ContainsRefs) -> String {
        var lines: [String] = []
        if !refs.localBranches.isEmpty { lines.append("本地分支：\(refs.localBranches.joined(separator: ", "))") }
        if !refs.remoteBranches.isEmpty { lines.append("远程分支：\(refs.remoteBranches.joined(separator: ", "))") }
        if !refs.tags.isEmpty { lines.append("tag：\(refs.tags.joined(separator: ", "))") }
        if lines.isEmpty { return "（未被任何分支 / tag 包含）" }
        return lines.joined(separator: "\n")
    }

    static func outcome(_ outcome: MergeOutcome, verb: String) -> String {
        switch outcome {
        case .fastForward:
            return "\(verb)完成（fast-forward）"
        case .merged(let newSHA):
            return "\(verb)完成，当前 HEAD：\(newSHA)"
        case .upToDate:
            return "已是最新的，无需\(verb)"
        case .conflicts(let entries):
            let list = entries.map { "  \($0.code) \($0.path)" }.joined(separator: "\n")
            return """
            \(verb)产生冲突，待处理：
            \(list)
            处理方式：git_resolve_conflict 选边 / 人工编辑后 git_mark_conflict_resolved，全部解决后 git_commit_merge；或 git_abort_\(verb == "合并" ? "merge" : "pick") 中止。
            """
        }
    }
}