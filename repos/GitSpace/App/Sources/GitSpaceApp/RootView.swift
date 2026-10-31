import SwiftUI
import GSFeatures
import GSDesignKit

struct RootView: View {
    @Environment(AppModel.self) private var app
    @State private var timelineModel = TimelineModel()
    @State private var repoVM = RepoViewModel()
    @State private var tab: MainTab = .timeline
    @AppStorage("appearance") private var appearance = "system"

    var body: some View {
        @Bindable var app = app
        VStack(spacing: 0) {
            TitleBar()
            NavigationSplitView {
                SidebarView(tab: $tab)
            } detail: {
                VStack(spacing: 0) {
                    headerBar
                    if app.anyMergeInProgress { mergeBanner }
                    content
                    StatusBarView()
                }
            }
        }
        .sheet(item: $app.activeSheet) { sheet in sheetView(sheet) }
        .overlay { paletteOverlay }
        .overlay(alignment: .bottomTrailing) { ToastsView() }
        .task {
            // 提交草稿存取（EP04-F02：会话级，跨仓库切换保留）
            repoVM.draftProvider = { app.commitDrafts[$0] }
            repoVM.draftStore = { app.commitDrafts[$0] = $1 }
            await initialLoad()
        }
        .onChange(of: app.requestedTab) {
            if let requested = app.requestedTab {
                tab = requested
                app.requestedTab = nil
            }
        }
        .onChange(of: app.selectedRepoPath) {
            Task { await repoVM.bind(to: app.selectedRepo) }
        }
    }

    private var content: some View {
        Group {
            switch tab {
            case .timeline:
                TimelineView(timeline: timelineModel)
            case .commit:
                if app.selectedRepo != nil {
                    WorkingView(vm: repoVM, onOpenCommit: openCommitInTimeline)
                } else {
                    EmptyStateView(title: "未选择仓库", hint: "在左侧选择一个仓库后开始提交")
                }
            case .status:
                StatusView(
                    onRunBatch: runBatch,
                    onPushConfirm: { targets in
                        Task { await app.openPushConfirmation(for: targets) }
                    }
                )
            case .changeset:
                ChangesetView(timeline: timelineModel, onOpenTimeline: { card in
                    timelineModel.filters.text = card
                    tab = .timeline
                })
            case .search:
                SearchView(timeline: timelineModel)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var headerBar: some View {
        HStack(spacing: GSSpacing.s) {
            HStack(spacing: 2) {
                ForEach(MainTab.allCases) { tabButton($0) }
            }
            Spacer()
            Button { Task { await refreshEverything() } } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .disabled(app.isRefreshing)
            Button { runBatch(.fetch, repos: app.repos) } label: {
                Label("全部 Fetch", systemImage: "arrow.down.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.gs(.accent))
        }
        .padding(.horizontal, GSSpacing.m)
        .padding(.vertical, GSSpacing.s)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func tabButton(_ item: MainTab) -> some View {
        Button { tab = item } label: {
            HStack(spacing: 6) {
                Text(item.title)
                if let count = tabCount(item) {
                    Text("\(count)")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(tab == item ? AnyShapeStyle(Color.primary.opacity(0.08)) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .foregroundStyle(tab == item ? Color.primary : Color.secondary)
    }

    private func tabCount(_ item: MainTab) -> Int? {
        switch item {
        case .timeline: return timelineModel.filtered.count
        case .commit: return repoVM.status?.dirtyCount
        case .status: return app.attentionCount > 0 ? app.attentionCount : nil
        case .changeset, .search: return nil
        }
    }

    private var mergeBanner: some View {
        HStack(spacing: GSSpacing.s) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.gs(.amber))
            Text("\(app.repos.filter { $0.isMergeInProgress }.count) 个仓库合并进行中")
                .font(.callout.weight(.medium))
            Spacer()
            Button("去解决") {
                if let id = app.mergingRepoID {
                    app.selectedRepoPath = id
                    tab = .commit
                }
            }
        }
        .padding(.horizontal, GSSpacing.m).padding(.vertical, GSSpacing.s)
        .background(Color.gs(.amber).opacity(0.12))
    }

    @ViewBuilder
    private func sheetView(_ sheet: AppSheet) -> some View {
        switch sheet {
        case .addRepo: AddRepoSheet()
        case .scan: ScanSheetView()
        case .batch: BatchSheetView()
        case .branch: BranchSheet(vm: repoVM)
        case .merge: MergeSheet(vm: repoVM)
        case .stash: StashSheet(vm: repoVM)
        case .tag: TagSheet(vm: repoVM)
        case .importManifest: ImportManifestSheet()
        case .pushConfirm: PushConfirmSheet()
        }
    }

    @ViewBuilder
    private var paletteOverlay: some View {
        @Bindable var app = app
        if app.isPaletteOpen {
            CommandPaletteView(commands: paletteCommands, query: $app.paletteQuery, isPresented: $app.isPaletteOpen)
        }
    }

    private var paletteCommands: [PaletteCommand] {
        [
            PaletteCommand(label: "切换深浅色主题", shortcut: "⌘⇧L") { cycleTheme() },
            PaletteCommand(label: "全部仓库 Fetch", shortcut: "⌘⇧F") { app.runBatch(.fetch, repos: app.repos) },
            PaletteCommand(label: "批量 Pull（选中待同步仓库）", shortcut: nil) { app.bulkPull() },
            PaletteCommand(label: "批量 Push（选中未推送仓库）", shortcut: nil) { app.bulkPush() },
            PaletteCommand(label: "新建 / 管理分支", shortcut: "⌘⇧B") { app.openRepoSheet(.branch) },
            PaletteCommand(label: "合并分支", shortcut: "⌘⇧M") { app.openRepoSheet(.merge) },
            PaletteCommand(label: "打开 Stash", shortcut: "⌘⇧S") { app.openRepoSheet(.stash) },
            PaletteCommand(label: "打开 Tag 管理", shortcut: "⌘⇧T") { app.openRepoSheet(.tag) },
            PaletteCommand(label: "添加仓库", shortcut: "⌘O") { app.activeSheet = .addRepo },
            PaletteCommand(label: "扫描父目录", shortcut: "⌘⇧O") { app.activeSheet = .scan },
            PaletteCommand(label: "导入 mgit 清单", shortcut: nil) { app.activeSheet = .importManifest }
        ]
    }

    /// Blame / 文件历史点击行 → 时间线定位（EP03-F03；仅限已加载时间窗内提交）。
    private func openCommitInTimeline(sha: String) {
        guard let match = timelineModel.commits.first(where: { $0.commit.sha.hasPrefix(sha) }) else {
            app.toasts.show("该提交不在已加载时间窗内，可调整过滤或时间窗口", isError: true)
            return
        }
        tab = .timeline
        Task { await timelineModel.select(match, app: app) }
    }

    private func cycleTheme() {
        switch appearance {
        case "system": appearance = "light"
        case "light": appearance = "dark"
        default: appearance = "system"
        }
    }

    private func runBatch(_ action: BatchAction, repos: [ManagedRepo]) {
        app.batch.start(action: action, repos: repos)
        app.activeSheet = .batch
    }

    private func initialLoad() async {
        await app.load()
        await timelineModel.reload(app: app)
        await repoVM.bind(to: app.selectedRepo)
    }

    private func refreshEverything() async {
        await app.refreshAll()
        await timelineModel.reload(app: app)
        await repoVM.refresh()
    }
}
