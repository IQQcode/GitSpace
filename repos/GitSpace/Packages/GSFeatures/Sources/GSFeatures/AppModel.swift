import Foundation
import Observation
import GSGitEngine
import GSIndex
import GSInfra

/// 工作区内一个已纳管仓库的运行时状态（@Observable，状态总览与侧栏共享）。
@MainActor
@Observable
public final class ManagedRepo: Identifiable {
    public let config: ManagedRepoConfig
    public let engine: GitRepository?
    public let colorSlot: Int
    public var status: RepoStatus?
    public var errorText: String?
    public var lastFetched: Date?
    public var lastStatusUpdate: Date?

    public init(config: ManagedRepoConfig, colorSlot: Int, operationLogger: OperationLog? = .shared) {
        self.config = config
        self.colorSlot = colorSlot
        let expanded = (config.path as NSString).expandingTildeInPath
        self.engine = GitRepository(path: URL(fileURLWithPath: expanded), operationLogger: operationLogger)
    }

    public nonisolated var id: String { config.id }
    public nonisolated var displayName: String { config.name }
    public var isValidGitRepository: Bool { engine != nil }
    public var branchName: String? { status?.branch }
    public var isMergeInProgress: Bool { status?.isMergeInProgress ?? false }
    public var hasConflicts: Bool { !(status?.unmerged.isEmpty ?? true) }

    /// 状态总览的“需处理”判定：冲突 / 引擎异常。
    public var needsAttention: Bool { hasConflicts || errorText != nil }
}

/// 应用根模型：工作区纳管、逐仓状态刷新、批量同步入口。
@MainActor
@Observable
public final class AppModel {
    public private(set) var repos: [ManagedRepo] = []
    public var workspace: WorkspaceConfig?
    public var selectedRepoPath: String?
    public var isRefreshing = false
    public var lastRefreshed: Date?
    public var gitVersionText: String = ""
    public let batch = BatchSyncModel()
    public let toasts = ToastCenter()
    /// 时间线加载窗口（天），设置页可调（MRD 10.6 超大仓策略）。
    public var timelineWindowDays: Int = 90

    // MARK: UI 状态（命令面板 / 全局弹窗 / 多仓选中集）
    public var isPaletteOpen = false
    public var paletteQuery = ""
    /// 多仓状态视图选中集，上移至此以便命令面板预选批量 Pull / Push。
    public var selectedRepos: Set<String> = []
    public var activeSheet: AppSheet?
    /// 推送确认面板的预检结果（EP05-F02）。
    public private(set) var pushPreview: [PushPreviewItem] = []
    /// 各仓未成功提交的草稿（EP04-F02：钩子失败等场景保留到下次打开，会话级）。
    public var commitDrafts: [String: String] = [:]
    /// 提交右键「从此新建分支…」的预填起点（EP02-F03）。
    public var branchSheetPresetStartPoint: String?
    /// 提交右键「在此打 tag…」的预填提交（EP02-F03）。
    public var tagSheetPresetSHA: String?
    /// 丢弃撤销中心（EP04-F01）。
    public let discardUndo = DiscardUndoCenter()

    public init() {}

    public var selectedRepo: ManagedRepo? {
        repos.first { $0.id == selectedRepoPath }
    }

    public var repoCount: Int { repos.count }
    public var cleanCount: Int { repos.filter { ($0.status?.isClean ?? false) && !$0.needsAttention }.count }
    public var pendingSyncCount: Int {
        repos.filter { status in
            guard let s = status.status else { return false }
            return s.ahead > 0 || s.behind > 0
        }.count
    }
    public var attentionCount: Int { repos.filter(\.needsAttention).count }
    public var totalUnpushed: Int { repos.reduce(0) { $0 + max(0, $1.status?.ahead ?? 0) } }
    public var anyMergeInProgress: Bool { repos.contains { $0.isMergeInProgress } }
    public var mergingRepoID: String? { repos.first { $0.isMergeInProgress }?.id }

    // MARK: 生命周期

    public func load() async {
        gitVersionText = (try? await GitProcessRunner.shared.gitVersion()) ?? "未知"
        let configs = WorkspaceStore.shared.loadAll()
        let ws = configs.first ?? WorkspaceConfig(name: "默认工作区", repos: [])
        workspace = ws
        rebuildRepos(from: ws.repos)
        await refreshAll()
    }

    private func rebuildRepos(from configs: [ManagedRepoConfig]) {
        repos = configs.enumerated().map { index, config in
            ManagedRepo(config: config, colorSlot: index)
        }
        if selectedRepoPath == nil {
            selectedRepoPath = repos.first?.id
        }
    }

    public func persist() {
        guard var ws = workspace else { return }
        ws.repos = repos.map(\.config)
        workspace = ws
        WorkspaceStore.shared.saveAll([ws])
    }

    // MARK: 纳管

    /// 返回 nil 表示成功，否则为错误文案。
    @discardableResult
    public func addRepo(path: String, name: String? = nil) async -> String? {
        let expanded = (path as NSString).expandingTildeInPath
        let gitPath = expanded + "/.git"
        guard FileManager.default.fileExists(atPath: gitPath) else {
            return "该目录不是 Git 仓库：\(expanded)"
        }
        guard !repos.contains(where: { $0.config.path == expanded }) else {
            return "仓库已在工作区中"
        }
        let config = ManagedRepoConfig(path: expanded, name: name)
        let repo = ManagedRepo(config: config, colorSlot: repos.count)
        repos.append(repo)
        persist()
        await refresh(repo)
        toasts.show("已添加仓库 \(repo.displayName)")
        return nil
    }

    public func removeRepo(_ repo: ManagedRepo) {
        repos.removeAll { $0.id == repo.id }
        repos = repos.enumerated().map { index, item in
            // 重排色槽保持稳定
            ManagedRepo(config: item.config, colorSlot: index)
        }
        if selectedRepoPath == repo.id {
            selectedRepoPath = repos.first?.id
        }
        persist()
        toasts.show("已移除仓库 \(repo.displayName)")
    }

    public func importDiscovered(_ discovered: [DiscoveredRepo]) async {
        var added = 0
        for item in discovered {
            guard !repos.contains(where: { $0.config.path == item.path.path }) else { continue }
            repos.append(ManagedRepo(config: ManagedRepoConfig(path: item.path.path, name: item.name), colorSlot: repos.count))
            added += 1
        }
        persist()
        await refreshAll()
        toasts.show("已导入 \(added) 个仓库到工作区")
    }

    // MARK: 状态刷新

    public func refreshAll() async {
        isRefreshing = true
        await withTaskGroup(of: Void.self) { group in
            for repo in repos {
                group.addTask { await self.refresh(repo) }
            }
        }
        isRefreshing = false
        lastRefreshed = Date()
    }

    public func refresh(_ repo: ManagedRepo) async {
        guard let engine = repo.engine else {
            repo.errorText = "目录不是 Git 仓库"
            return
        }
        do {
            repo.status = try await engine.status()
            repo.errorText = nil
            repo.lastStatusUpdate = Date()
        } catch {
            // 单仓读取失败不阻塞其他仓库（MRD 10.4-7）
            repo.errorText = GitPresenter.text(for: error)
        }
    }

    public func markFetched(_ repo: ManagedRepo) {
        repo.lastFetched = Date()
    }

    // MARK: 推送确认（EP05-F02：先预检 → 确认 → 执行）

    /// 只读预检：逐仓刷新 status 后整理预览项，然后打开确认面板。
    public func openPushConfirmation(for repos: [ManagedRepo]) async {
        guard !repos.isEmpty else { return }
        var items: [PushPreviewItem] = []
        for repo in repos {
            await refresh(repo)
            if let status = repo.status {
                let reason: String?
                if status.upstream == nil {
                    reason = "无上游分支"
                } else if status.ahead == 0 {
                    reason = "无待推送提交"
                } else {
                    reason = nil
                }
                items.append(PushPreviewItem(
                    repoID: repo.id,
                    repoName: repo.displayName,
                    branch: status.branch,
                    upstream: status.upstream,
                    ahead: status.ahead,
                    skipReason: reason
                ))
            } else {
                items.append(PushPreviewItem(
                    repoID: repo.id,
                    repoName: repo.displayName,
                    branch: nil, upstream: nil, ahead: 0,
                    skipReason: repo.errorText ?? "读取失败"
                ))
            }
        }
        pushPreview = items
        activeSheet = .pushConfirm
    }

    /// 确认面板点「推送」后执行（复用批量同步的排队/并发/逐仓结果）。
    public func confirmPush() {
        let targets = repos.filter { repo in
            pushPreview.contains { $0.repoID == repo.id && $0.isPushable }
        }
        activeSheet = nil
        guard !targets.isEmpty else { return }
        batch.start(action: .push, repos: targets)
        activeSheet = .batch
    }
}

/// 全局弹窗路由（命令面板与侧栏共用，驱动 .sheet(item:)）。
public enum AppSheet: String, Identifiable, Sendable {
    case addRepo, scan, batch, branch, merge, stash, tag, importManifest
    case pushConfirm
    public var id: String { rawValue }
}

// MARK: - 推送前确认（EP05-F02）

/// 推送预检项：数据只来自只读 status（porcelain v2 branch.ab），不自算。
public struct PushPreviewItem: Identifiable, Sendable {
    public let repoID: String
    public let repoName: String
    public let branch: String?
    public let upstream: String?
    public let ahead: Int
    /// nil = 将执行；否则为跳过原因（无上游分支 / 无待推送提交 / 读取失败）。
    public let skipReason: String?

    public var id: String { repoID }
    public var isPushable: Bool { skipReason == nil }

    public init(repoID: String, repoName: String, branch: String?, upstream: String?, ahead: Int, skipReason: String?) {
        self.repoID = repoID
        self.repoName = repoName
        self.branch = branch
        self.upstream = upstream
        self.ahead = ahead
        self.skipReason = skipReason
    }
}

// MARK: - 批量同步（MRD 10.2-B：逐仓 排队/执行/成功/跳过/失败 + 可取消 + 重试）

public enum BatchAction: String, CaseIterable, Sendable {
    case fetch = "Fetch"
    case pull = "Pull"
    case push = "Push"
}

public enum BatchItemState: Equatable, Sendable {
    case queued
    case running
    case succeeded
    case skipped(reason: String)
    case failed(reason: String)
    case cancelled
}

@MainActor
@Observable
public final class BatchSyncModel {
    public struct Item: Identifiable {
        public let repo: ManagedRepo
        public var state: BatchItemState
        public var id: String { repo.id }
    }

    public private(set) var action: BatchAction = .fetch
    public private(set) var items: [Item] = []
    public private(set) var isRunning = false
    public var pullMode: PullMode = .fastForwardOnly
    public var concurrency: Int = 4

    private var task: Task<Void, Never>?

    public var isIdle: Bool { !isRunning }
    public var failedItems: [Item] { items.filter { if case .failed = $0.state { return true } else { return false } } }
    public var summaryText: String {
        let ok = items.filter { $0.state == .succeeded }.count
        let skipped = items.filter { if case .skipped = $0.state { return true } else { return false } }.count
        let failed = failedItems.count
        var parts = ["成功 \(ok)"]
        if skipped > 0 { parts.append("跳过 \(skipped)") }
        if failed > 0 { parts.append("失败 \(failed)") }
        return parts.joined(separator: " · ")
    }

    public func start(action: BatchAction, repos: [ManagedRepo]) {
        guard !isRunning else { return }
        self.action = action
        items = repos.map { Item(repo: $0, state: .queued) }
        guard !items.isEmpty else { return }
        isRunning = true
        let concurrency = self.concurrency
        let semaphore = AsyncSemaphore(max(1, concurrency))
        task = Task { [weak self] in
            guard let self else { return }
            await withTaskGroup(of: Void.self) { group in
                for index in self.items.indices {
                    group.addTask {
                        await self.execute(index: index, semaphore: semaphore)
                    }
                }
            }
            self.isRunning = false
            self.notifyDone()
        }
    }

    public func cancel() {
        task?.cancel()
        isRunning = false
    }

    public func retryFailed() {
        let repos = failedItems.map(\.repo)
        guard !repos.isEmpty else { return }
        start(action: action, repos: repos)
    }

    private func execute(index: Int, semaphore: AsyncSemaphore) async {
        await semaphore.wait()
        defer { semaphore.signal() }
        if Task.isCancelled {
            items[index].state = .cancelled
            return
        }
        items[index].state = .running
        let repo = items[index].repo
        do {
            guard let engine = repo.engine else {
                throw GitError.notARepository(path: repo.config.path)
            }
            switch action {
            case .fetch:
                try await engine.fetchAll()
                items[index].state = .succeeded
                repo.lastFetched = Date()
            case .pull:
                guard let status = repo.status, status.upstream != nil else {
                    items[index].state = .skipped(reason: "无上游分支")
                    break
                }
                try await engine.pull(mode: pullMode)
                items[index].state = .succeeded
                repo.lastFetched = Date()
            case .push:
                guard let status = repo.status, status.upstream != nil else {
                    items[index].state = .skipped(reason: "无上游分支")
                    break
                }
                guard status.ahead > 0 else {
                    items[index].state = .skipped(reason: "无待推送提交")
                    break
                }
                try await engine.push()
                items[index].state = .succeeded
                repo.lastFetched = Date()
            }
            // 逐仓刷新状态（MRD 10.6 流程四）
            await refresh(repo: repo, keeping: items[index].state)
        } catch {
            if Task.isCancelled {
                items[index].state = .cancelled
            } else {
                items[index].state = .failed(reason: GitPresenter.text(for: error))
            }
        }
    }

    private func refresh(repo: ManagedRepo, keeping state: BatchItemState) async {
        guard let engine = repo.engine else { return }
        do {
            repo.status = try await engine.status()
            repo.errorText = nil
            repo.lastStatusUpdate = Date()
        } catch {
            repo.errorText = GitPresenter.text(for: error)
        }
        _ = state
    }

    private func notifyDone() {
        // 完成提示由视图层监听 isRunning 变化展示，这里不弹窗。
    }
}

// MARK: - Toast

@MainActor
@Observable
public final class ToastCenter {
    public struct Toast: Identifiable {
        public let id = UUID()
        public let text: String
        public let isError: Bool
        /// 可选动作（如丢弃撤销的「撤销」、合并完成的「推送」）。
        public let actionLabel: String?
        public let action: (() -> Void)?

        public init(text: String, isError: Bool = false, actionLabel: String? = nil, action: (() -> Void)? = nil) {
            self.text = text
            self.isError = isError
            self.actionLabel = actionLabel
            self.action = action
        }
    }

    public private(set) var toasts: [Toast] = []

    public func show(_ text: String, isError: Bool = false) {
        show(Toast(text: text, isError: isError))
    }

    public func show(_ toast: Toast) {
        toasts.append(toast)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.8))
            self?.toasts.removeAll { $0.id == toast.id }
        }
    }

    /// 带动作的提示（如 [撤销]）；动作触发后立即移除该条。
    public func showWithAction(_ text: String, actionLabel: String, action: @escaping () -> Void) {
        show(Toast(text: text, actionLabel: actionLabel, action: action))
    }

    /// 立即移除一条提示（动作按钮点击后调用）。
    public func dismiss(id: UUID) {
        toasts.removeAll { $0.id == id }
    }
}

// MARK: - 错误文案

public enum GitPresenter {
    public static func text(for error: Error) -> String {
        if let gitError = error as? GitError {
            return gitError.errorDescription ?? String(describing: gitError)
        }
        return error.localizedDescription
    }
}
