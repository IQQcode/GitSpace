import SwiftUI
import GSFeatures
import GSDesignKit

struct RootView: View {
    @Environment(AppModel.self) private var app
    @State private var timelineModel = TimelineModel()
    @State private var repoVM = RepoViewModel()
    @State private var tab: MainTab = .timeline
    @State private var showAddRepo = false
    @State private var showScan = false
    @State private var showBatch = false

    enum MainTab: String, CaseIterable, Identifiable {
        case timeline
        case status
        case working
        case repo

        var id: String { rawValue }
        var title: String {
            switch self {
            case .timeline: return "统一时间线"
            case .status: return "多仓状态"
            case .working: return "改动 · 提交"
            case .repo: return "分支 · 合并"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(tab: $tab, showAddRepo: $showAddRepo, showScan: $showScan)
        } detail: {
            VStack(spacing: 0) {
                headerBar
                if repoVM.isMergeInProgress && (tab == .working || tab == .repo) {
                    MergeBanner(vm: repoVM)
                }
                content
                StatusBarView()
            }
        }
        .sheet(isPresented: $showBatch) { BatchSheetView() }
        .sheet(isPresented: $showAddRepo) { AddRepoSheet() }
        .sheet(isPresented: $showScan) { ScanSheetView() }
        .overlay(alignment: .bottomTrailing) { ToastsView() }
        .task { await initialLoad() }
        .onChange(of: app.selectedRepoPath) {
            Task { await repoVM.bind(to: app.selectedRepo) }
        }
    }

    private var content: some View {
        Group {
            switch tab {
            case .timeline:
                TimelineView(timeline: timelineModel)
            case .status:
                StatusView(onRunBatch: runBatch)
            case .working:
                if app.selectedRepo != nil {
                    WorkingView(vm: repoVM)
                } else {
                    EmptyStateView(title: "未选择仓库", hint: "在左侧选择一个仓库后开始提交")
                }
            case .repo:
                if app.selectedRepo != nil {
                    RepoView(vm: repoVM)
                } else {
                    EmptyStateView(title: "未选择仓库", hint: "在左侧选择一个仓库后管理分支与合并")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var headerBar: some View {
        HStack(spacing: GSSpacing.s) {
            HStack(spacing: 2) {
                ForEach(MainTab.allCases) { item in
                    Button {
                        tab = item
                    } label: {
                        HStack(spacing: 6) {
                            Text(item.title)
                            if item == .status && app.attentionCount > 0 {
                                Text("\(app.attentionCount)")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.gs(.red, dark: true).opacity(0.18), in: Capsule())
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            tab == item ? AnyShapeStyle(Color.primary.opacity(0.08)) : AnyShapeStyle(.clear),
                            in: RoundedRectangle(cornerRadius: 7)
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(tab == item ? Color.primary : Color.secondary)
                }
            }
            Spacer()
            Button {
                Task { await refreshEverything() }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .disabled(app.isRefreshing)

            Button {
                runBatch(.fetch, repos: app.repos)
            } label: {
                Label("全部 Fetch", systemImage: "arrow.down.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.gs(.accent))
        }
        .padding(.horizontal, GSSpacing.m)
        .padding(.vertical, GSSpacing.s)
        .background(Color(nsColor: .windowBackgroundColor))
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

    private func runBatch(_ action: BatchAction, repos: [ManagedRepo]) {
        app.batch.start(action: action, repos: repos)
        showBatch = true
    }
}

/// 合并进行中的顶部常驻条（MRD 10.6 状态表）。
struct MergeBanner: View {
    @Bindable var vm: RepoViewModel

    var body: some View {
        HStack(spacing: GSSpacing.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.gs(.amber))
            Text(vm.unmergedEntries.isEmpty
                 ? "合并进行中：冲突已全部解决，可完成合并提交"
                 : "合并进行中：\(vm.unmergedEntries.count) 个冲突文件待解决")
                .font(.callout.weight(.medium))
            Spacer()
            Button("中止合并", role: .destructive) {
                Task {
                    try? await vm.abortMerge()
                }
            }
        }
        .padding(.horizontal, GSSpacing.m)
        .padding(.vertical, GSSpacing.s)
        .background(Color.gs(.amber).opacity(0.12))
    }
}
