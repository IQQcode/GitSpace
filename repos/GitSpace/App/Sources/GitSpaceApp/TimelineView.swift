import SwiftUI
import GSFeatures
import GSIndex
import GSGitEngine
import GSDesignKit

/// 统一时间线：过滤栏 + 提交列表（图列/信息/仓库/时间）+ 提交详情与 diff。
struct TimelineView: View {
    @Environment(AppModel.self) private var app
    @Bindable var timeline: TimelineModel

    var body: some View {
        VStack(spacing: 0) {
            FilterBar(timeline: timeline)
            HSplitView {
                CommitListView(timeline: timeline)
                    .frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
                DetailPanel(timeline: timeline)
                    .frame(minWidth: 330, idealWidth: 392, maxWidth: 460, maxHeight: .infinity)
            }
        }
    }
}

private struct FilterBar: View {
    @Environment(AppModel.self) private var app
    @Bindable var timeline: TimelineModel

    var body: some View {
        HStack(spacing: GSSpacing.s) {
            Picker("", selection: $timeline.filters.repoPath) {
                Text("全部仓库 (\(app.repoCount))").tag(String?.none)
                ForEach(app.repos) { repo in
                    Text(repo.displayName).tag(String?.some(repo.id))
                }
            }
            .frame(width: 150)

            Picker("", selection: $timeline.filters.branch) {
                Text("全部分支").tag(String?.none)
                ForEach(timeline.branchOptions, id: \.self) { branch in
                    Text(branch).tag(String?.some(branch))
                }
            }
            .frame(width: 140)

            Picker("", selection: $timeline.filters.author) {
                Text("全部作者").tag(String?.none)
                ForEach(timeline.authors, id: \.self) { author in
                    Text(author).tag(String?.some(author))
                }
            }
            .frame(width: 120)

            Picker("", selection: $timeline.filters.dateRange) {
                ForEach(TimelineModel.DateRange.allCases, id: \.self) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .frame(width: 110)

            TextField("搜索提交信息 / hash", text: $timeline.filters.text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 190)

            if !timeline.filters.isDefault {
                Button("清除") { timeline.resetFilters() }
                    .buttonStyle(.link)
            }

            Spacer()

            let count = timeline.filtered.count
            Text("\(count) 条提交 · \(app.repoCount) 个仓库")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, GSSpacing.m)
        .padding(.vertical, GSSpacing.s)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct CommitListView: View {
    @Environment(AppModel.self) private var app
    @Bindable var timeline: TimelineModel
    @State private var pendingCheckout: PendingCheckout?

    struct PendingCheckout: Identifiable {
        let id = UUID()
        let repoID: String
        let sha: String
        /// nil = 检出提交（detached）
        let branchName: String?
        let worktreeDirty: Bool
    }

    var body: some View {
        List(selection: Binding(
            get: { timeline.selectedCommit?.id },
            set: { id in
                timeline.selectedCommit = id.flatMap { candidate in
                    timeline.commits.first { $0.id == candidate }
                }
            }
        )) {
            ForEach(timeline.filtered) { commit in
                CommitRow(
                    commit: commit,
                    onNewBranch: { presetBranch(commit) },
                    onTagHere: { presetTag(commit) },
                    onCheckoutCommit: { requestCheckout(commit: commit, branchName: nil) },
                    onCheckoutBranch: { name in requestCheckout(commit: commit, branchName: name) }
                )
                .tag(commit.id)
            }
        }
        .confirmationDialog(
            checkoutTitle,
            isPresented: Binding(get: { pendingCheckout != nil }, set: { if !$0 { pendingCheckout = nil } }),
            titleVisibility: .visible
        ) {
            if let pending = pendingCheckout, pending.branchName != nil, pending.worktreeDirty {
                Button("stash 后检出") { performCheckout(stashFirst: true) }
            }
            Button(checkoutActionLabel, role: .destructive) { performCheckout(stashFirst: false) }
            Button("取消", role: .cancel) {}
        } message: {
            Text(checkoutMessage)
        }
        .listStyle(.plain)
        .overlay {
            if timeline.filtered.isEmpty {
                EmptyStateView(
                    title: timeline.commits.isEmpty ? "时间线为空" : "没有匹配的提交",
                    hint: timeline.commits.isEmpty ? "添加仓库后这里会聚合所有仓库的提交" : "试试调整仓库、作者或时间筛选",
                    showReset: !timeline.filters.isDefault
                )
            }
        }
        .onChange(of: timeline.selectedCommit?.id) {
            guard let commit = timeline.selectedCommit else { return }
            Task { await timeline.select(commit, app: app) }
        }
        .safeAreaInset(edge: .bottom) {
            if !timeline.truncatedRepos.isEmpty {
                HStack {
                    Image(systemName: "clock.badge.exclamationmark")
                    Text("已按时间窗口截断：\(timeline.truncatedRepos.joined(separator: "、")) 近期之外的历史未加载")
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(Color.gs(.amber))
                .padding(.horizontal, GSSpacing.m)
                .padding(.vertical, 6)
                .background(Color.gs(.amber).opacity(0.1))
            }
        }
    }

    // MARK: 提交右键与检出（EP02-F03 / EP12-F02）

    private func presetBranch(_ commit: TimelineCommit) {
        app.branchSheetPresetStartPoint = commit.commit.sha
        app.activeSheet = .branch
    }

    private func presetTag(_ commit: TimelineCommit) {
        app.tagSheetPresetSHA = commit.commit.sha
        app.activeSheet = .tag
    }

    private func requestCheckout(commit: TimelineCommit, branchName: String?) {
        guard let repo = app.repos.first(where: { $0.config.path == commit.repoPath }) else { return }
        pendingCheckout = PendingCheckout(
            repoID: repo.id,
            sha: commit.commit.sha,
            branchName: branchName,
            worktreeDirty: (repo.status?.isClean == false)
        )
    }

    private var checkoutTitle: String {
        guard let pending = pendingCheckout else { return "" }
        if let branch = pending.branchName {
            return "检出分支 \"\(branch)\"？"
        }
        return "检出提交 \(pending.sha.prefix(7))？"
    }

    private var checkoutActionLabel: String {
        pendingCheckout?.branchName == nil ? "检出（进入 detached HEAD）" : "检出"
    }

    private var checkoutMessage: String {
        guard let pending = pendingCheckout else { return "" }
        if let branch = pending.branchName {
            return pending.worktreeDirty
                ? "工作区有未提交改动，可先 stash 再检出，或取消。"
                : "将切换到该分支。"
        }
        return "检出提交将进入 detached HEAD（不关联分支），后续提交不会被任何分支引用。"
    }

    private func performCheckout(stashFirst: Bool) {
        guard let pending = pendingCheckout,
              let repo = app.repos.first(where: { $0.id == pending.repoID }),
              let engine = repo.engine else { return }
        pendingCheckout = nil
        Task {
            do {
                if stashFirst { try await engine.stashPush(message: "GitSpace: 检出前自动暂存") }
                if let branch = pending.branchName {
                    try await engine.switchBranch(name: branch)
                    app.toasts.show("已切换到 \(branch)")
                } else {
                    try await engine.checkoutDetached(sha: pending.sha)
                    app.toasts.show("已检出 \(pending.sha.prefix(7))（detached HEAD）")
                }
                await app.refresh(repo)
            } catch {
                app.toasts.show(GitPresenter.text(for: error), isError: true)
            }
        }
    }
}

struct CommitRow: View {
    let commit: TimelineCommit
    var onNewBranch: () -> Void = {}
    var onTagHere: () -> Void = {}
    var onCheckoutCommit: () -> Void = {}
    var onCheckoutBranch: (String) -> Void = { _ in }

    var body: some View {
        HStack(alignment: .center, spacing: GSSpacing.s) {
            CommitGraphCell(colorSlot: commit.colorSlot)
                .frame(width: 56, height: GSGraph.rowHeight)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(commit.commit.subject)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    if commit.commit.isMerge {
                        Text("MERGE")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color.gs(.purple))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .strokeBorder(Color.gs(.purple).opacity(0.5), lineWidth: 0.8)
                            )
                    }
                }
                HStack(spacing: 7) {
                    AuthorBadge(name: commit.commit.authorName)
                    Text(commit.commit.shortSHA)
                        .font(.gsMonoSmall)
                        .foregroundStyle(.tertiary)
                    Text(Self.relative(commit.commit.authorTimestamp))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(GSPalette.color(forSlot: commit.colorSlot))
                        .frame(width: 6, height: 6)
                    Text(commit.repoName)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                }
                // Ref 徽标（EP02-F02）：本地分支/远程分支/tag/HEAD 分色；双击分支检出
                HStack(spacing: 4) {
                    ForEach(commit.commit.decorations, id: \.self) { decoration in
                        RefBadge(decoration: decoration) {
                            let kind = RefDecoration.classify(decoration)
                            switch kind {
                            case .headBranch(let name), .localBranch(let name):
                                onCheckoutBranch(name)
                            default:
                                break
                            }
                        }
                    }
                }
                .lineLimit(1)
            }
            .frame(width: 200, alignment: .leading)
        }
        .frame(height: GSGraph.rowHeight)
        .contextMenu {
            Button("复制 SHA") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(commit.commit.sha, forType: .string)
            }
            Button("复制提交信息") {
                NSPasteboard.general.clearContents()
                let message = commit.commit.body.isEmpty
                    ? commit.commit.subject
                    : commit.commit.subject + "\n\n" + commit.commit.body
                NSPasteboard.general.setString(message, forType: .string)
            }
            Divider()
            Button("从此新建分支…") { onNewBranch() }
            Button("在此打 tag…") { onTagHere() }
            Button("检出此提交…") { onCheckoutCommit() }
            if commit.commit.decorations.contains(where: { RefDecoration.classify($0).isBranch }) {
                Button("检出分支…") {
                    if let decoration = commit.commit.decorations.first(where: { RefDecoration.classify($0).isBranch }) {
                        switch RefDecoration.classify(decoration) {
                        case .headBranch(let name), .localBranch(let name):
                            onCheckoutBranch(name)
                        default: break
                        }
                    }
                }
            }
        }
    }

    static func relative(_ timestamp: Int) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(
            for: Date(timeIntervalSince1970: TimeInterval(timestamp)),
            relativeTo: Date()
        )
    }
}

// MARK: - Ref 徽标（EP02-F02）

/// %D 装饰分类（数据来自 git，按前缀分类不猜测）。
enum RefDecoration: Equatable {
    case headBranch(String)   // HEAD -> main
    case localBranch(String)  // 本地分支（无斜杠且非 tag/HEAD）
    case remoteBranch(String) // 含 /（origin/xxx）
    case tag(String)          // tag: v1.0
    case head                 // HEAD（detached）

    static func classify(_ raw: String) -> RefDecoration {
        if raw == "HEAD" { return .head }
        if raw.hasPrefix("HEAD -> ") { return .headBranch(String(raw.dropFirst("HEAD -> ".count))) }
        if raw.hasPrefix("tag: ") { return .tag(String(raw.dropFirst("tag: ".count))) }
        if raw.contains("/") { return .remoteBranch(raw) }
        return .localBranch(raw)
    }

    var isBranch: Bool {
        switch self {
        case .headBranch, .localBranch, .remoteBranch: return true
        case .tag, .head: return false
        }
    }
}

/// 彩色胶囊徽标：双击分支徽标检出（EP02-F02）。
struct RefBadge: View {
    let decoration: String
    var onDoubleClick: (() -> Void)? = nil

    private var kind: RefDecoration { RefDecoration.classify(decoration) }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: iconName).font(.system(size: 7, weight: .bold))
            Text(displayName)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 5)
        .padding(.vertical, 1.5)
        .background(color.opacity(0.13), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.4), lineWidth: 0.8))
        .help(kind.isBranch ? "双击检出 \(displayName)" : displayName)
        .onTapGesture(count: 2) {
            if kind.isBranch { onDoubleClick?() }
        }
    }

    private var iconName: String {
        switch kind {
        case .headBranch, .localBranch: return "arrow.triangle.branch"
        case .remoteBranch: return "cloud"
        case .tag: return "tag"
        case .head: return "location"
        }
    }

    private var displayName: String {
        switch kind {
        case .headBranch(let name), .localBranch(let name), .remoteBranch(let name), .tag(let name):
            return name
        case .head: return "HEAD"
        }
    }

    private var color: Color {
        switch kind {
        case .headBranch: return Color.gs(.accent)
        case .localBranch: return Color.gs(.green)
        case .remoteBranch: return Color.gs(.textMuted)
        case .tag: return Color.gs(.purple)
        case .head: return Color.gs(.amber)
        }
    }
}

/// 提交图列（MVP：每仓一条 lane 的纵向连线 + 节点；DAG lane 布局 P1）。
struct CommitGraphCell: View {
    let colorSlot: Int

    var body: some View {
        Canvas { context, size in
            let x = GSGraph.laneOffset + 0
            let color = GSPalette.color(forSlot: colorSlot)
            var path = Path()
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(path, with: .color(color.opacity(0.3)), lineWidth: 2)
            let center = CGPoint(x: x, y: size.height / 2)
            context.fill(
                Path(ellipseIn: CGRect(
                    x: center.x - GSGraph.nodeRadius,
                    y: center.y - GSGraph.nodeRadius,
                    width: GSGraph.nodeRadius * 2,
                    height: GSGraph.nodeRadius * 2
                )),
                with: .color(color)
            )
        }
    }
}

struct AuthorBadge: View {
    let name: String

    var body: some View {
        HStack(spacing: 4) {
            Text(String(name.prefix(1)))
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 15, height: 15)
                .background(GSPalette.color(forName: name), in: Circle())
            Text(name)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct DetailPanel: View {
    @Environment(AppModel.self) private var app
    @Bindable var timeline: TimelineModel
    @State private var selectedFileID: String?
    // EP02-F04：「包含于」按需加载
    @State private var containsRefs: ContainsRefs?
    @State private var isLoadingContains = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let commit = timeline.selectedCommit {
                header(commit: commit)
                Divider()
                fileList(commit: commit)
                if let file = timeline.selectedFiles.first(where: { $0.id == selectedFileID })
                    ?? timeline.selectedFiles.first {
                    Divider()
                    DiffFileView(file: file)
                }
            } else {
                EmptyStateView(title: "未选择提交", hint: "在时间线中点选一条提交查看详情与 diff")
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func header(commit: TimelineCommit) -> some View {
        VStack(alignment: .leading, spacing: GSSpacing.s) {
            HStack(spacing: 6) {
                Circle().fill(GSPalette.color(forSlot: commit.colorSlot)).frame(width: 7, height: 7)
                Text(commit.repoName).font(.caption.weight(.semibold))
                Text(commit.commit.shortSHA).font(.gsMonoSmall).foregroundStyle(.tertiary)
                if commit.commit.isMerge {
                    Text("MERGE").font(.system(size: 8, weight: .bold)).foregroundStyle(Color.gs(.purple))
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(commit.commit.sha, forType: .string)
                    app.toasts.show("已复制完整 hash")
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("复制完整 SHA")
            }
            Text(commit.commit.subject)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    AuthorBadge(name: commit.commit.authorName)
                    Text(CommitRow.relative(commit.commit.authorTimestamp))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            if !commit.commit.decorations.isEmpty {
                HStack(spacing: 4) {
                    ForEach(commit.commit.decorations, id: \.self) { decoration in
                        Text(decoration)
                            .font(.gsMonoSmall)
                            .foregroundStyle(Color.gs(.accent))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.gs(.accent).opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
            // EP02-F04：author 与 committer 不同才显示 committer 行
            if commit.commit.hasDistinctCommitter {
                HStack(spacing: 6) {
                    Text("committer")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    AuthorBadge(name: commit.commit.committerName)
                    Text(CommitRow.relative(commit.commit.committerTimestamp))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            if !commit.commit.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let (main, trailers) = Self.splitTrailers(commit.commit.body)
                if !main.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(main)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(10)
                }
                if !trailers.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(trailers.enumerated()), id: \.offset) { _, trailer in
                            Text(trailer)
                                .font(.gsMonoSmall)
                                .foregroundStyle(.tertiary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(GSSpacing.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            // 父提交（可点击在时间线定位）
            if !commit.commit.parents.isEmpty {
                HStack(spacing: 5) {
                    Text("父提交")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    ForEach(commit.commit.parents, id: \.self) { parent in
                        Button {
                            jumpToCommit(parent)
                        } label: {
                            Text(String(parent.prefix(7)))
                                .font(.gsMonoSmall)
                                .foregroundStyle(Color.gs(.accent))
                                .underline()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            // 「包含于」（EP02-F04：按需加载 branch -a --contains / tag --contains）
            HStack(spacing: GSSpacing.s) {
                if let refs = containsRefs {
                    if refs.isEmpty {
                        Text("不被任何分支或 tag 包含")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else {
                        HStack(spacing: 4) {
                            ForEach(refs.localBranches, id: \.self) { RefBadge(decoration: $0) }
                            ForEach(refs.remoteBranches, id: \.self) { RefBadge(decoration: $0) }
                            ForEach(refs.tags, id: \.self) { RefBadge(decoration: "tag: \($0)") }
                        }
                        .lineLimit(2)
                    }
                } else {
                    Button {
                        loadContains(commit: commit)
                    } label: {
                        if isLoadingContains {
                            ProgressView().controlSize(.mini)
                        } else {
                            Text("包含于…").font(.caption)
                        }
                    }
                    .buttonStyle(.link)
                    .disabled(isLoadingContains)
                }
                Spacer()
            }
        }
        .padding(GSSpacing.m)
        .onChange(of: commit.commit.sha) {
            containsRefs = nil
        }
    }

    /// git trailers（Signed-off-by / Change-Id 等）：从正文尾部连续的 `Key: ` 行提取。
    static func splitTrailers(_ body: String) -> (main: String, trailers: [String]) {
        var lines = body.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var trailers: [String] = []
        while let last = lines.last,
              last.range(of: #"^[A-Za-z][A-Za-z0-9-]*: "#, options: .regularExpression) != nil {
            trailers.insert(last, at: 0)
            lines.removeLast()
        }
        return (lines.joined(separator: "\n"), trailers)
    }

    private func jumpToCommit(_ sha: String) {
        guard let match = timeline.commits.first(where: { $0.commit.sha.hasPrefix(sha) }) else {
            app.toasts.show("父提交不在已加载时间窗内", isError: true)
            return
        }
        Task { await timeline.select(match, app: app) }
    }

    private func loadContains(commit: TimelineCommit) {
        guard let repo = app.repos.first(where: { $0.config.path == commit.repoPath }),
              let engine = repo.engine else { return }
        isLoadingContains = true
        Task {
            defer { isLoadingContains = false }
            containsRefs = (try? await engine.refsContaining(sha: commit.commit.sha)) ?? ContainsRefs()
        }
    }

    private func fileList(commit: TimelineCommit) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("改动文件 · \(timeline.selectedFiles.count)")
                Spacer()
                let add = timeline.selectedFiles.reduce(0) { $0 + $1.additions }
                let del = timeline.selectedFiles.reduce(0) { $0 + $1.deletions }
                Text("+\(add)")
                    .font(.gsMonoSmall)
                    .foregroundStyle(Color.gs(.green))
                Text("−\(del)")
                    .font(.gsMonoSmall)
                    .foregroundStyle(Color.gs(.red))
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)
            .padding(.horizontal, GSSpacing.m)
            .padding(.vertical, GSSpacing.xs)

            ForEach(timeline.selectedFiles) { file in
                FileDiffRow(
                    file: file,
                    isSelected: (selectedFileID ?? timeline.selectedFiles.first?.id) == file.id,
                    showActions: false
                ) {
                    selectedFileID = file.id
                }
            }
            if timeline.isLoadingDetail {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("加载 diff…").font(.caption).foregroundStyle(.tertiary)
                }
                .padding(GSSpacing.m)
            }
        }
    }

    private func relativeDate(_ timestamp: Int) -> String {
        CommitRow.relative(timestamp)
    }
}

/// 文件行（时间线详情与改动视图共用）。
struct FileDiffRow: View {
    let file: FileDiff
    let isSelected: Bool
    let showActions: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 7) {
                Text(file.kind.rawValue)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(statusColor)
                    .frame(width: 15, height: 15)
                    .background(statusColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                Text((file.originalPath.map { "\($0) → " } ?? "") + file.path)
                    .font(.gsMonoSmall)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Text("+\(file.additions)")
                    .font(.gsMonoSmall)
                    .foregroundStyle(Color.gs(.green))
                Text("−\(file.deletions)")
                    .font(.gsMonoSmall)
                    .foregroundStyle(Color.gs(.red))
            }
            .padding(.horizontal, GSSpacing.m)
            .padding(.vertical, 5)
            .background(
                isSelected ? Color.primary.opacity(0.06) : Color.clear,
                in: RoundedRectangle(cornerRadius: 5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var statusColor: Color {
        switch file.kind {
        case .added, .copied: return Color.gs(.green)
        case .deleted: return Color.gs(.red)
        case .renamed: return Color.gs(.purple)
        default: return Color.gs(.amber)
        }
    }
}
