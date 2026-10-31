import SwiftUI
import GSFeatures
import GSGitEngine
import GSDesignKit

/// 左侧栏：工作区卡片 + 仓库列表（同步状态徽标）+ 纳管动作。
struct SidebarView: View {
    @Environment(AppModel.self) private var app
    @Binding var tab: MainTab
    @State private var query = ""
    @State private var repoToRemove: ManagedRepo?

    var filteredRepos: [ManagedRepo] {
        let keyword = query.trimmingCharacters(in: .whitespaces)
        guard !keyword.isEmpty else { return app.repos }
        return app.repos.filter {
            $0.displayName.localizedCaseInsensitiveContains(keyword)
                || ($0.branchName?.localizedCaseInsensitiveContains(keyword) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            workspaceCard
            searchField
            headerLabel
            repoList
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .confirmationDialog(
            "移除仓库 \"\(repoToRemove?.displayName ?? "")\"？",
            isPresented: Binding(get: { repoToRemove != nil }, set: { if !$0 { repoToRemove = nil } }),
            titleVisibility: .visible
        ) {
            Button("仅从工作区移除（不删除文件）", role: .destructive) {
                if let repo = repoToRemove { app.removeRepo(repo) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("仓库文件与历史不受影响，可随时重新添加。")
        }
    }

    private var workspaceCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(app.workspace?.name ?? "GitSpace")
                    .font(.headline)
                Spacer()
                Text("MULTI-REPO")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.gs(.accent))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.gs(.accent).opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
            }
            if !workspaceSubtitle.isEmpty {
                Text(workspaceSubtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack(spacing: GSSpacing.s) {
                Label("\(app.repoCount) 个仓库", systemImage: "shippingbox")
                if let version = app.gitVersionText.split(separator: ".").first {
                    Label("git \(version).x", systemImage: "terminal")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let summary = branchConsistencySummary {
                Text(summary)
                    .font(.caption2)
                    .foregroundStyle(summary.contains("一致") ? Color.gs(.green) : Color.gs(.amber))
            }
            Text(freshnessText).font(.caption2).foregroundStyle(.tertiary)
            if app.isRefreshing {
                ProgressView().progressViewStyle(.linear).frame(height: 2)
            }
        }
        .padding(GSSpacing.m)
        .background(Color.gs(.accent).opacity(0.06))
        .padding(.horizontal, GSSpacing.s)
        .padding(.top, GSSpacing.s)
    }

    /// 分支一致性小结（EP05-F03）：基准 = 多数仓当前分支。
    private var branchConsistencySummary: String? {
        let branches = app.repos.compactMap(\.branchName)
        guard branches.count >= 2, let baseline = branchBaseline else { return nil }
        let aligned = branches.filter { $0 == baseline }.count
        return aligned == branches.count
            ? "分支一致 \(aligned) / \(branches.count)（均在 \(baseline)）"
            : "分支一致 \(aligned) / \(branches.count)，基准 \(baseline)"
    }

    private var branchBaseline: String? {
        let branches = app.repos.compactMap(\.branchName)
        var counts: [String: Int] = [:]
        for branch in branches { counts[branch, default: 0] += 1 }
        return counts.max { $0.value < $1.value }?.key
    }

    private var workspaceSubtitle: String {
        let names = app.repos.prefix(2).map(\.displayName)
        guard !names.isEmpty else { return "" }
        return names.joined(separator: " + ") + (app.repoCount > 2 ? " 等" : "")
    }

    private var freshnessText: String {
        guard let refreshed = app.lastRefreshed else { return "尚未刷新" }
        return "数据截至 " + refreshed.formatted(date: .omitted, time: .shortened)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)
                .font(.caption)
            TextField("筛选仓库或分支", text: $query)
                .textFieldStyle(.plain)
                .font(.callout)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
        .padding(.horizontal, GSSpacing.m)
        .padding(.vertical, GSSpacing.s)
        .background(KeyboardShortcutHandler { query = "" })
    }

    private var headerLabel: some View {
        HStack {
            Text("仓库 · \(app.repoCount)")
            Spacer()
            Text("同步状态")
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.tertiary)
        .textCase(.uppercase)
        .padding(.horizontal, GSSpacing.m)
        .padding(.top, GSSpacing.xs)
    }

    private var repoList: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                if filteredRepos.isEmpty {
                    Text(query.isEmpty ? "还没有仓库，先添加或扫描" : "没有匹配的仓库")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, GSSpacing.l)
                }
                ForEach(filteredRepos) { repo in
                    RepoRow(
                        repo: repo,
                        isSelected: app.selectedRepoPath == repo.id,
                        onSelect: {
                            app.selectedRepoPath = repo.id
                            tab = .timeline
                        },
                        onRemove: { repoToRemove = repo }
                    )
                }
            }
            .padding(.horizontal, GSSpacing.s)
            .padding(.vertical, GSSpacing.xs)
        }
    }

    private var footer: some View {
        VStack(spacing: 2) {
            Divider()
            sideAction("添加仓库", key: "⌘O", icon: "plus.square") { app.activeSheet = .addRepo }
            sideAction("扫描父目录", key: "⌘⇧O", icon: "square.stack.3d.up") { app.activeSheet = .scan }
            sideAction("导入 mgit 清单", key: nil, icon: "doc.text") { app.activeSheet = .importManifest }
            Divider().padding(.vertical, 2)
            sideAction("分支管理", key: "⌘⇧B", icon: "arrow.triangle.branch") { openRepoSheet(.branch) }
            sideAction("合并分支", key: "⌘⇧M", icon: "arrow.triangle.merge") { openRepoSheet(.merge) }
            sideAction("Stash 暂存", key: "⌘⇧S", icon: "archivebox") { openRepoSheet(.stash) }
            sideAction("Tag 管理", key: "⌘⇧T", icon: "tag") { openRepoSheet(.tag) }
        }
        .font(.callout)
        .padding(.bottom, GSSpacing.s)
    }

    private func sideAction(_ title: String, key: String?, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label {
                HStack {
                    Text(title)
                    Spacer()
                    if let key { Text(key).font(.caption2).foregroundStyle(.tertiary) }
                }
            } icon: {
                Image(systemName: icon)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, GSSpacing.s)
        .padding(.vertical, 6)
    }

    private func openRepoSheet(_ sheet: AppSheet) {
        guard app.selectedRepo != nil else {
            app.toasts.show("请先在左侧选择一个仓库", isError: true)
            return
        }
        app.activeSheet = sheet
    }
}

private struct KeyboardShortcutHandler: View {
    let onFocus: () -> Void
    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .focusable(false)
    }
}

struct RepoRow: View {
    @Environment(AppModel.self) private var app
    let repo: ManagedRepo
    let isSelected: Bool
    let onSelect: () -> Void
    let onRemove: () -> Void
    @AppStorage("externalTerminal") private var externalTerminal = "terminal"
    @AppStorage("externalTerminalCustom") private var externalTerminalCustom = ""
    @AppStorage("externalEditor") private var externalEditor = "xcode"
    @AppStorage("externalEditorCustom") private var externalEditorCustom = ""

    private var repoURL: URL { URL(fileURLWithPath: repo.config.expandedPath) }

    private func openInTerminal() {
        do {
            try ExternalToolsLauncher.openInTerminal(
                ExternalTerminal(rawValue: externalTerminal) ?? .terminal,
                repoPath: repoURL,
                customTemplate: externalTerminalCustom
            )
        } catch {
            app.toasts.show(GitPresenter.text(for: error), isError: true)
        }
    }

    private func openInEditor(file: URL?, line: Int?) {
        do {
            try ExternalToolsLauncher.openInEditor(
                ExternalEditor(rawValue: externalEditor) ?? .xcode,
                repoPath: repoURL,
                file: file,
                line: line,
                customTemplate: externalEditorCustom
            )
        } catch {
            app.toasts.show(GitPresenter.text(for: error), isError: true)
        }
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: GSSpacing.s) {
                Circle()
                    .fill(GSPalette.color(forSlot: repo.colorSlot))
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(repo.displayName)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        FlagChips(status: repo.status, errorText: repo.errorText)
                    }
                    BranchQuickSwitchLabel(repo: repo)
                }
            }
            .padding(.horizontal, GSSpacing.s)
            .padding(.vertical, 7)
            .background(
                isSelected ? Color.gs(.accent).opacity(0.14) : Color.clear,
                in: RoundedRectangle(cornerRadius: 7)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("在访达中显示") {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: repo.config.path)
            }
            Divider()
            Button("在终端打开") { openInTerminal() }
            Button("在编辑器打开") { openInEditor(file: nil, line: nil) }
            Button("复制路径") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(repo.config.expandedPath, forType: .string)
            }
            Divider()
            Button("从工作区移除…", role: .destructive, action: onRemove)
        }
    }
}

/// ↑n / ↓n / ●n / ✓ 徽标（对齐原型 repoFlags）。
struct FlagChips: View {
    let status: RepoStatus?
    let errorText: String?

    var body: some View {
        HStack(spacing: 4) {
            if errorText != nil {
                chip("!", color: .red)
            } else if let status {
                if status.hasConflicts { chip("⚡︎", color: .red) }
                if status.dirtyCount > 0 { chip("●\(status.dirtyCount)", color: .red) }
                if status.ahead > 0 { chip("↑\(status.ahead)", color: .green) }
                if status.behind > 0 { chip("↓\(status.behind)", color: .amber) }
                if status.isClean && !status.hasConflicts { chip("✓", color: .textMuted) }
            } else {
                ProgressView().controlSize(.mini)
            }
        }
    }

    private func chip(_ text: String, color: GSColor) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color.gs(color))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color.gs(color).opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
    }
}
