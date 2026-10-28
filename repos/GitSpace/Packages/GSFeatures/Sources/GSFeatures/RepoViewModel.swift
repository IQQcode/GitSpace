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
    public var message: String = ""
    public var amend = false
    public var mergeRefInput: String = ""
    public var mergeNoFF = false
    public var isBusy = false
    public private(set) var lastErrorText: String?
    public private(set) var hookOutput: String?
    public private(set) var lastMergeOutcomeText: String?

    public init() {}

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
        message = ""
        amend = false
        lastErrorText = nil
        hookOutput = nil
        lastMergeOutcomeText = nil
        await refresh()
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
                sha = try await engine.commit(message: message, amend: amend)
                message = ""
                amend = false
            }
            await refresh()
            return sha
        } catch let error as GitError {
            lastErrorText = GitPresenter.text(for: error)
            if case .hookFailed(let output) = error {
                hookOutput = output
            }
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
        let outcome = try await engine.merge(ref: ref, style: mergeNoFF ? .noFastForward : .auto)
        switch outcome {
        case .fastForward: lastMergeOutcomeText = "已快进合并 \(ref)"
        case .merged: lastMergeOutcomeText = "已合并 \(ref)（生成合并提交）"
        case .upToDate: lastMergeOutcomeText = "已是最新，无需合并"
        case .conflicts(let entries): lastMergeOutcomeText = "合并冲突：\(entries.count) 个文件待解决"
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
}
