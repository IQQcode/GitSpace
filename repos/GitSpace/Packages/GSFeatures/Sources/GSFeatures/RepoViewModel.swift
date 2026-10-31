import Foundation
import Observation
import GSGitEngine

/// 当前仓工作视图：改动/暂存/提交、分支、合并冲突、stash、tag（MRD 10.2-C/D/E/F）。
@MainActor
@Observable
public final class RepoViewModel {
    public enum DiffSide: String, CaseIterable {
        case unstaged
        case staged
    }

    public private(set) var repo: ManagedRepo?
    public private(set) var status: RepoStatus?
    public private(set) var unstagedEntries: [ChangeEntry] = []
    public private(set) var untrackedEntries: [ChangeEntry] = []
    public private(set) var stagedEntries: [ChangeEntry] = []
    public private(set) var unstagedFiles: [FileDiff] = []
    public private(set) var stagedFiles: [FileDiff] = []
    public private(set) var untrackedFiles: [FileDiff] = []
    public private(set) var branches: [BranchInfo] = []
    public private(set) var remoteBranches: [RemoteBranchInfo] = []
    public private(set) var stashes: [StashInfo] = []
    public private(set) var tags: [TagInfo] = []

    public var selectedSide: DiffSide = .unstaged
    public var selectedPath: String?
    /// 提交标题（第一行，EP04-F02）。
    public var messageTitle: String = ""
    /// 提交正文（EP04-F02）。
    public var messageBody: String = ""
    public var amend = false
    public var mergeRefInput: String = ""
    public var mergeNoFF = false
    /// 合并信息输入（EP07-F01：快进时由 git 忽略）。
    public var mergeMessageInput: String = ""
    /// 提交信息辅助（EP04-F02）：本仓最近提交标题 + commit.template。
    public private(set) var recentSubjects: [String] = []
    public private(set) var commitTemplateText: String?
    public var isBusy = false
    public private(set) var lastErrorText: String?
    public private(set) var hookOutput: String?
    public private(set) var lastMergeOutcomeText: String?

    public init() {}

    /// 标题 + 正文合成完整提交信息（commit(message:) 入参）。
    public var composedMessage: String {
        let title = messageTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = messageBody.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.isEmpty { return title }
        return title + "\n\n" + body
    }

    /// 标题长度提示（EP04-F02：>50 变色，>72 警告；不阻止提交）。
    public var titleLengthState: TitleLengthState {
        let count = messageTitle.count
        if count > 72 { return .overLimit(count) }
        if count > 50 { return .overRecommended(count) }
        return .normal(count)
    }

    public enum TitleLengthState: Equatable {
        case normal(Int)
        case overRecommended(Int)
        case overLimit(Int)
    }

    // MARK: - 派生

    public var unmergedEntries: [UnmergedEntry] { status?.unmerged ?? [] }
    public var isMergeInProgress: Bool { status?.isMergeInProgress ?? false }
    public var isDetached: Bool { status?.detached ?? false }
    public var currentBranch: String? { status?.branch }

    public var allWorkingEntries: [ChangeEntry] { unstagedEntries + untrackedEntries }

    public var canCommit: Bool {
        guard let status else { return false }
        if status.isMergeInProgress { return status.unmerged.isEmpty }
        return !status.staged.isEmpty
    }

    public var canCommitMerge: Bool {
        guard let status, status.isMergeInProgress else { return false }
        return status.unmerged.isEmpty
    }

    public var selectedFile: FileDiff? {
        guard let selectedPath else { return nil }
        switch selectedSide {
        case .unstaged:
            return unstagedFiles.first { $0.path == selectedPath }
                ?? untrackedFiles.first { $0.path == selectedPath }
        case .staged:
            return stagedFiles.first { $0.path == selectedPath }
        }
    }

    public func select(path: String, side: DiffSide) {
        selectedPath = path
        selectedSide = side
    }

    // MARK: - 绑定与刷新

    public func bind(to newRepo: ManagedRepo?) async {
        guard repo?.id != newRepo?.id else { return }
        repo = newRepo
        selectedPath = nil
        messageTitle = ""
        messageBody = ""
        amend = false
        mergeRefInput = ""
        mergeMessageInput = ""
        lastErrorText = nil
        hookOutput = nil
        lastMergeOutcomeText = nil
        recentSubjects = []
        commitTemplateText = nil
        await refresh()
        await loadCommitAssist()
    }

    /// 提交信息辅助（EP04-F02）：历史标题、commit.template、未成功草稿恢复。
    public func loadCommitAssist() async {
        guard let repo, let engine = repo.engine, messageTitle.isEmpty else { return }
        async let subjectsTask = try? engine.recentCommitSubjects(limit: 20)
        async let templateTask = try? engine.commitTemplate()
        recentSubjects = (await subjectsTask) ?? []
        let template = await templateTask ?? nil
        // 恢复未成功草稿，其次模板
        let draftKey = repo.id
        if let draft = draftProvider?(draftKey), !draft.isEmpty {
            applyMessageText(draft)
        } else if let template, messageBody.isEmpty {
            applyMessageText(template)
        }
        commitTemplateText = template
    }

    /// 草稿存取由 AppModel 提供（会话级，跨仓库切换保留）。
    public var draftProvider: ((String) -> String?)?

    /// 历史下拉选中：第一行进标题，其余进正文。
    public func applyMessageText(_ text: String) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        messageTitle = lines.first ?? ""
        messageBody = lines.dropFirst().joined(separator: "\n")
    }

    /// 提交成功后清空输入与草稿。
    public func clearCommitInputs(draftStore: ((String, String?) -> Void)?) {
        messageTitle = ""
        messageBody = ""
        if let repo { draftStore?(repo.id, nil) }
    }

    public func refresh() async {
        guard let repo, let engine = repo.engine else {
            status = nil
            unstagedEntries = []
            untrackedEntries = []
            stagedEntries = []
            unstagedFiles = []
            stagedFiles = []
            untrackedFiles = []
            branches = []
            remoteBranches = []
            stashes = []
            tags = []
            return
        }
        async let statusTask = engine.status()
        async let unstagedDiffTask = engine.worktreeDiff()
        async let stagedDiffTask = engine.stagedDiff()
        async let branchesTask = try? engine.localBranches()
        async let remoteBranchesTask = try? engine.remoteBranches()
        async let stashesTask = try? engine.stashes()
        async let tagsTask = try? engine.tags()

        let newStatus = try? await statusTask
        status = newStatus ?? status
        let unstagedDiff = (try? await unstagedDiffTask) ?? []
        let stagedDiff = (try? await stagedDiffTask) ?? []
        branches = (await branchesTask) ?? []
        remoteBranches = (await remoteBranchesTask) ?? []
        stashes = (await stashesTask) ?? []
        tags = (await tagsTask) ?? []

        stagedEntries = newStatus?.staged ?? []
        unstagedEntries = newStatus?.unstaged ?? []
        untrackedEntries = newStatus?.untracked ?? []
        stagedFiles = stagedDiff
        // worktreeDiff 天然只含"有工作区改动"的文件（含已暂存后又有新改动的文件）
        unstagedFiles = unstagedDiff

        // 未跟踪文件生成预览 diff
        var previews: [FileDiff] = []
        for entry in untrackedEntries {
            if let preview = try? await engine.untrackedFileDiff(path: entry.path) {
                previews.append(preview)
            }
        }
        untrackedFiles = previews

        if selectedPath != nil, selectedFile == nil {
            self.selectedPath = nil
        }
    }

    private func currentFileExists() -> Bool {
        selectedFile != nil
    }

    // MARK: - 暂存（文件级 + 块级）

    public func stageFiles(_ paths: [String]) async throws {
        guard let engine = repo?.engine, !paths.isEmpty else { return }
        try await engine.stageFiles(paths)
        await refresh()
    }

    public func unstageFiles(_ paths: [String]) async throws {
        guard let engine = repo?.engine, !paths.isEmpty else { return }
        try await engine.unstageFiles(paths)
        await refresh()
    }

    public func stageAll() async throws {
        try await stageFiles(allWorkingEntries.map(\.path))
    }

    public func stageHunks(of file: FileDiff, hunkIDs: Set<Int>) async throws {
        guard let engine = repo?.engine else { return }
        try await engine.stageHunks(of: file, hunkIDs: hunkIDs)
        await refresh()
    }

    public func unstageHunks(of file: FileDiff, hunkIDs: Set<Int>) async throws {
        guard let engine = repo?.engine else { return }
        try await engine.unstageHunks(of: file, hunkIDs: hunkIDs)
        await refresh()
    }

    public enum DiscardKind: String, Sendable {
        case worktree
        case stagedAndWorktree
        case untracked
    }

    /// 丢弃改动：调用方必须先走二次确认（MRD 10.2-G）。
    public func discard(path: String, kind: DiscardKind) async throws {
        guard let engine = repo?.engine else { return }
        switch kind {
        case .worktree: try await engine.discard(.worktree(path: path))
        case .stagedAndWorktree: try await engine.discard(.stagedAndWorktree(path: path))
        case .untracked: try await engine.discard(.untracked(path: path))
        }
        await refresh()
    }

    // MARK: - 提交

    /// 草稿写入由 AppModel 提供（会话级，跨仓库切换保留）。
    public var draftStore: ((String, String?) -> Void)?

    public func commit() async throws -> String {
        guard let repo, let engine = repo.engine else {
            throw GitError.notARepository(path: repo?.config.path ?? "")
        }
        isBusy = true
        lastErrorText = nil
        hookOutput = nil
        defer { isBusy = false }
        do {
            let sha: String
            if isMergeInProgress {
                sha = try await engine.commitMerge()
            } else {
                sha = try await engine.commit(message: composedMessage, amend: amend)
                messageTitle = ""
                messageBody = ""
                amend = false
                draftStore?(repo.id, nil)
            }
            await refresh()
            return sha
        } catch let error as GitError {
            lastErrorText = GitPresenter.text(for: error)
            if case .hookFailed(let output) = error {
                hookOutput = output
            }
            // 钩子失败 / 提交被取消：信息保留到草稿，下次打开恢复（MRD 10.6、EP04-F02）
            draftStore?(repo.id, composedMessage)
            await refresh()
            throw error
        }
    }

    // MARK: - 分支

    public func createBranch(name: String, from startPoint: String?) async throws {
        guard let engine = repo?.engine else { return }
        try await engine.createBranch(name: name, from: startPoint)
        await refresh()
    }

    public enum SwitchBlocker: Error, Equatable {
        case dirtyWorkspace
    }

    /// 切换：脏工作区返回 blocker，由 UI 提供 stash 后切换 / 取消 两条路（MRD 10.6 状态表）。
    public func switchBranch(name: String) async throws {
        guard let engine = repo?.engine else { return }
        do {
            try await engine.switchBranch(name: name)
        } catch let error as GitError {
            if case .uncommittedChanges = error {
                throw SwitchBlocker.dirtyWorkspace
            }
            throw error
        }
        await refresh()
    }

    public func stashThenSwitchBranch(name: String) async throws {
        guard let engine = repo?.engine else { return }
        try await engine.stashPush(message: "GitSpace: 切换分支自动暂存")
        try await engine.switchBranch(name: name)
        await refresh()
    }

    public func deleteBranch(name: String, force: Bool) async throws {
        guard let engine = repo?.engine else { return }
        try await engine.deleteBranch(name: name, force: force)
        await refresh()
    }

    public func renameBranch(oldName: String, newName: String) async throws {
        guard let engine = repo?.engine else { return }
        try await engine.renameBranch(oldName: oldName, newName: newName)
        await refresh()
    }

    public func checkoutRemoteBranch(_ remote: RemoteBranchInfo) async throws {
        guard let engine = repo?.engine else { return }
        try await engine.checkoutRemoteBranch(remote)
        await refresh()
    }

    // MARK: - 合并与冲突

    public func merge(ref: String) async throws -> MergeOutcome {
        guard let engine = repo?.engine else {
            throw GitError.notARepository(path: repo?.config.path ?? "")
        }
        isBusy = true
        defer { isBusy = false }
        let message = mergeMessageInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let outcome = try await engine.merge(
            ref: ref,
            style: mergeNoFF ? .noFastForward : .auto,
            message: message.isEmpty ? nil : message
        )
        switch outcome {
        case .fastForward: lastMergeOutcomeText = "已快进合并 \(ref)"
        case .merged: lastMergeOutcomeText = "已合并 \(ref)（生成合并提交）"
        case .upToDate: lastMergeOutcomeText = "已是最新，无需合并"
        case .conflicts(let entries): lastMergeOutcomeText = "合并冲突：\(entries.count) 个文件待解决"
        }
        if case .conflicts = outcome {
            // 冲突时保留输入待重试；成功则清空
        } else {
            mergeMessageInput = ""
        }
        await refresh()
        return outcome
    }

    public func resolveConflict(path: String, resolution: ConflictResolution) async throws {
        guard let engine = repo?.engine else { return }
        try await engine.resolveConflict(path: path, resolution: resolution)
        await refresh()
    }

    public func markConflictResolved(path: String) async throws {
        guard let engine = repo?.engine else { return }
        try await engine.markConflictResolved(path: path)
        await refresh()
    }

    /// 冲突文件三路 stage 内容（EP07-F02 外部工具 / EP07-F03 两者都保留）。
    public func conflictStageContents(path: String) async throws -> (base: String?, ours: String?, theirs: String?) {
        guard let engine = repo?.engine else { return (nil, nil, nil) }
        return try await engine.conflictStageContents(path: path)
    }

    /// 读取工作区文件内容（冲突预览用）。
    public func readFile(path: String) -> String? {
        guard let repo else { return nil }
        let url = URL(fileURLWithPath: repo.config.expandedPath).appendingPathComponent(path)
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// 写入用户确认的解决内容并标记已解决（EP07-F03：确认后才 git add）。
    public func writeResolvedContent(path: String, content: String) async throws {
        guard let repo else { return }
        let url = URL(fileURLWithPath: repo.config.expandedPath).appendingPathComponent(path)
        try content.write(to: url, atomically: true, encoding: .utf8)
        try await markConflictResolved(path: path)
    }

    public func abortMerge() async throws {
        guard let engine = repo?.engine else { return }
        try await engine.abortMerge()
        lastMergeOutcomeText = "已中止合并，工作区回到合并前"
        await refresh()
    }

    // MARK: - stash / tag

    public func stashSave(message: String?) async throws {
        guard let engine = repo?.engine else { return }
        try await engine.stashPush(message: message)
        await refresh()
    }

    public func stashRestore(index: Int, pop: Bool) async throws {
        guard let engine = repo?.engine else { return }
        try await engine.stashRestore(index: index, mode: pop ? .pop : .apply)
        await refresh()
    }

    public func stashDrop(index: Int) async throws {
        guard let engine = repo?.engine else { return }
        try await engine.stashDrop(index: index)
        await refresh()
    }

    public func stashDiff(index: Int) async throws -> [FileDiff] {
        guard let engine = repo?.engine else { return [] }
        return try await engine.stashDiff(index: index)
    }

    public func createTag(name: String, message: String?) async throws {
        guard let engine = repo?.engine else { return }
        try await engine.createTag(name: name, message: message)
        await refresh()
    }

    public func deleteTag(name: String) async throws {
        guard let engine = repo?.engine else { return }
        try await engine.deleteTag(name: name)
        await refresh()
    }

    /// 推送 tag 到远端（EP07-F05）。
    public func pushTag(name: String, remote: String = "origin") async throws {
        guard let engine = repo?.engine else { return }
        try await engine.pushTag(name: name, remote: remote)
    }

    /// 删除远端 tag（EP07-F05，UI 层二次确认）。
    public func deleteRemoteTag(name: String, remote: String = "origin") async throws {
        guard let engine = repo?.engine else { return }
        try await engine.deleteRemoteTag(name: name, remote: remote)
    }

    /// 检出到指定提交（detached，EP02-F03，UI 层二次确认）。
    public func checkoutDetached(sha: String) async throws {
        guard let engine = repo?.engine else { return }
        do {
            try await engine.checkoutDetached(sha: sha)
        } catch let error as GitError {
            if case .uncommittedChanges = error {
                throw SwitchBlocker.dirtyWorkspace
            }
            throw error
        }
        await refresh()
    }

    // MARK: - 历史只读（EP03-F03/F04、EP02-F04）

    public func blame(rev: String?, path: String) async throws -> BlameResult {
        guard let engine = repo?.engine else { return BlameResult(lines: [], commits: [:]) }
        return try await engine.blame(rev: rev, path: path)
    }

    public func fileHistory(path: String) async throws -> [CommitInfo] {
        guard let engine = repo?.engine else { return [] }
        return try await engine.fileHistory(path: path)
    }

    public func fileChangeAt(sha: String, path: String) async throws -> [FileDiff] {
        guard let engine = repo?.engine else { return [] }
        return try await engine.fileChangeAt(sha: sha, path: path)
    }

    public func diffAgainstRevision(rev: String, path: String) async throws -> [FileDiff] {
        guard let engine = repo?.engine else { return [] }
        return try await engine.diffAgainstRevision(rev: rev, path: path)
    }

    public func refsContaining(sha: String) async throws -> ContainsRefs {
        guard let engine = repo?.engine else { return ContainsRefs() }
        return try await engine.refsContaining(sha: sha)
    }

    /// 取回旧版本（EP03-F04：等价 `git restore --source=<sha> --worktree`，UI 层二次确认）。
    public func restoreFileFromRevision(rev: String, path: String) async throws {
        guard let engine = repo?.engine else { return }
        try await engine.restoreFile(rev: rev, path: path)
        await refresh()
    }
}
