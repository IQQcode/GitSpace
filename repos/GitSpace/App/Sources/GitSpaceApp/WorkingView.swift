import SwiftUI
import GSFeatures
import GSGitEngine
import GSDesignKit

/// 改动视图：未暂存 / 已暂存两栏 + diff（文件级与块级暂存）+ 提交（MRD 10.6 流程五）。
struct WorkingView: View {
    @Environment(AppModel.self) private var app
    @Bindable var vm: RepoViewModel
    let onOpenCommit: (String) -> Void
    @AppStorage("externalEditor") private var externalEditor = "xcode"
    @AppStorage("externalEditorCustom") private var externalEditorCustom = ""
    @State private var hunkSelection = Set<Int>()
    @State private var pendingDiscard: PendingDiscard?
    @State private var isCommitting = false
    @State private var blameRequest: FileToolRequest?
    @State private var historyRequest: FileToolRequest?

    enum PendingDiscard {
        case file(path: String, kind: RepoViewModel.DiscardKind)
        case hunks(file: FileDiff, ids: Set<Int>)
        case all
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            HSplitView {
                leftColumn
                    .frame(minWidth: 300, idealWidth: 340, maxWidth: 460, maxHeight: .infinity)
                diffPanel
                    .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
            }
            commitBar
        }
        .confirmationDialog(
            discardDialogTitle,
            isPresented: Binding(get: { pendingDiscard != nil }, set: { if !$0 { pendingDiscard = nil } }),
            titleVisibility: .visible
        ) {
            Button("丢弃（可撤销）", role: .destructive) {
                guard let request = pendingDiscard else { return }
                performDiscard(request)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(discardDialogMessage)
        }
        .sheet(item: $blameRequest) { request in
            BlameSheet(vm: vm, request: request, onOpenCommit: onOpenCommit)
        }
        .sheet(item: $historyRequest) { request in
            FileHistorySheet(
                vm: vm,
                request: request,
                onOpenCommit: onOpenCommit,
                onOpenBlame: { sha, path in
                    historyRequest = nil
                    blameRequest = FileToolRequest(path: path, rev: sha)
                }
            )
        }
    }

    private var discardDialogTitle: String {
        switch pendingDiscard {
        case .file(let path, _): return "丢弃 \"\(path)\" 的改动？"
        case .hunks(let file, let ids): return "丢弃 \"\(file.path)\" 的 \(ids.count) 个改动块？"
        case .all: return "丢弃全部改动？"
        case nil: return ""
        }
    }

    private var discardDialogMessage: String {
        switch pendingDiscard {
        case .file(_, let kind) where kind == .untracked:
            return "未跟踪文件将移入废纸篓。丢弃前会自动创建快照，可撤销。"
        case .all:
            return "将丢弃 \(vm.unstagedEntries.count) 个文件的改动与 \(vm.untrackedEntries.count) 个未跟踪文件。丢弃前会自动创建快照，可撤销。"
        default:
            return "丢弃前会自动创建快照，丢弃后可通过通知条撤销。"
        }
    }

    // MARK: 外部工具（EP09-F01）

    private func openInEditor(_ relativePath: String, line: Int?) {
        guard let repo = app.selectedRepo else { return }
        let url = repo.config.fileURL(relativePath)
        let repoRoot = URL(fileURLWithPath: repo.config.expandedPath)
        do {
            try ExternalToolsLauncher.openInEditor(
                ExternalEditor(rawValue: externalEditor) ?? .xcode,
                repoPath: repoRoot,
                file: url,
                line: line,
                customTemplate: externalEditorCustom
            )
        } catch {
            app.toasts.show(GitPresenter.text(for: error), isError: true)
        }
    }

    // MARK: 丢弃（EP04-F01：快照 + 撤销）

    private func performDiscard(_ pending: PendingDiscard) {
        guard let repo = app.selectedRepo else { return }
        Task {
            do {
                switch pending {
                case .file(let path, let kind):
                    let scope: GitRepository.DiscardScope
                    switch kind {
                    case .worktree: scope = .worktree(path: path)
                    case .stagedAndWorktree: scope = .stagedAndWorktree(path: path)
                    case .untracked: scope = .untracked(path: path)
                    }
                    try await app.discardUndo.discardFiles(repo: repo, scopes: [scope])
                case .hunks(let file, let ids):
                    try await app.discardUndo.discardHunks(repo: repo, file: file, hunkIDs: ids)
                case .all:
                    try await app.discardUndo.discardAll(repo: repo)
                }
                await vm.refresh()
                app.toasts.showWithAction("已丢弃改动", actionLabel: "撤销") {
                    Task {
                        let message = await app.discardUndo.undo(repo: repo)
                        app.toasts.show(message, isError: !message.hasPrefix("已恢复"))
                        await vm.refresh()
                    }
                }
            } catch {
                app.toasts.show(GitPresenter.text(for: error), isError: true)
            }
        }
    }

    // MARK: 头部

    private var header: some View {
        HStack(spacing: GSSpacing.s) {
            Circle().fill(GSPalette.color(forSlot: app.selectedRepo?.colorSlot ?? 0)).frame(width: 8, height: 8)
            Text(app.selectedRepo?.displayName ?? "—").font(.headline)
            if let branch = vm.currentBranch {
                Text(branch).font(.gsMonoSmall).foregroundStyle(Color.gs(.accent))
            }
            if vm.isDetached {
                Text("detached HEAD").font(.caption).foregroundStyle(Color.gs(.amber))
            }
            Spacer()
            if let status = vm.status {
                Text("未提交 \(status.dirtyCount) · 未推送 \(max(0, status.ahead))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            if vm.unstagedEntries.isEmpty && vm.untrackedEntries.isEmpty && vm.stagedEntries.isEmpty {
                EmptyView()
            } else {
                Button("丢弃全部改动…", role: .destructive) {
                    pendingDiscard = .all
                }
                .font(.caption)
                .disabled(vm.unstagedEntries.isEmpty && vm.untrackedEntries.isEmpty)
            }
        }
        .padding(.horizontal, GSSpacing.m)
        .padding(.vertical, GSSpacing.s)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: 左栏（未暂存 / 未跟踪 / 已暂存）

    private var leftColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("未暂存 · \(vm.unstagedEntries.count)") {
                    if !vm.unstagedEntries.isEmpty {
                        Button("全部暂存") {
                            Task { try? await vm.stageFiles(vm.unstagedEntries.map(\.path)) }
                        }
                        .buttonStyle(.link)
                    }
                }
                ForEach(vm.unstagedEntries) { entry in
                    ChangeRow(
                        title: entry.path,
                        kindLetter: (entry.worktreeKind ?? .modified).rawValue,
                        isSelected: vm.selectedSide == .unstaged && vm.selectedPath == entry.path,
                        leadingActions: [
                            ("暂存", "plus.square.on.square", { Task { try? await vm.stageFiles([entry.path]) } })
                        ],
                        trailingAction: ("丢弃", "arrow.uturn.backward", {
                            pendingDiscard = PendingDiscard.file(
                                path: entry.path,
                                kind: (entry.indexKind != nil) ? .stagedAndWorktree : .worktree
                            )
                        })
                    ) {
                        vm.select(path: entry.path, side: .unstaged)
                    }
                    .contextMenu {
                        Button("Blame") { blameRequest = FileToolRequest(path: entry.path) }
                        Button("文件历史") { historyRequest = FileToolRequest(path: entry.path) }
                        Divider()
                        Button("在编辑器打开") { openInEditor(entry.path, line: nil) }
                        Button("复制路径") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(entry.path, forType: .string)
                        }
                    }
                }

                sectionHeader("未跟踪 · \(vm.untrackedEntries.count)") {}
                ForEach(vm.untrackedEntries) { entry in
                    ChangeRow(
                        title: entry.path,
                        kindLetter: "U",
                        isSelected: vm.selectedSide == .unstaged && vm.selectedPath == entry.path,
                        leadingActions: [
                            ("暂存", "plus.square.on.square", { Task { try? await vm.stageFiles([entry.path]) } })
                        ],
                        trailingAction: ("删除", "trash", {
                            pendingDiscard = PendingDiscard.file(path: entry.path, kind: .untracked)
                        })
                    ) {
                        vm.select(path: entry.path, side: .unstaged)
                    }
                }

                sectionHeader("已暂存 · \(vm.stagedEntries.count)") {
                    if !vm.stagedEntries.isEmpty {
                        Button("全部取消") {
                            Task { try? await vm.unstageFiles(vm.stagedEntries.map(\.path)) }
                        }
                        .buttonStyle(.link)
                    }
                }
                ForEach(vm.stagedEntries) { entry in
                    ChangeRow(
                        title: entry.path,
                        kindLetter: (entry.indexKind ?? .modified).rawValue,
                        isSelected: vm.selectedSide == .staged && vm.selectedPath == entry.path,
                        leadingActions: [
                            ("取消暂存", "minus.square", { Task { try? await vm.unstageFiles([entry.path]) } })
                        ],
                        trailingAction: nil
                    ) {
                        vm.select(path: entry.path, side: .staged)
                    }
                    .contextMenu {
                        Button("Blame") { blameRequest = FileToolRequest(path: entry.path) }
                        Button("文件历史") { historyRequest = FileToolRequest(path: entry.path) }
                        Divider()
                        Button("在编辑器打开") { openInEditor(entry.path, line: nil) }
                        Button("复制路径") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(entry.path, forType: .string)
                        }
                    }
                }

                if vm.unstagedEntries.isEmpty && vm.untrackedEntries.isEmpty && vm.stagedEntries.isEmpty {
                    EmptyStateView(title: "工作区干净", hint: "没有待提交的改动")
                        .padding(.top, GSSpacing.xl)
                }
            }
        }
    }

    private func sectionHeader(_ title: String, @ViewBuilder trailing: () -> some View) -> some View {
        HStack {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            Spacer()
            trailing()
        }
        .padding(.horizontal, GSSpacing.m)
        .padding(.top, GSSpacing.m)
        .padding(.bottom, GSSpacing.xs)
    }

    // MARK: 右栏（diff + hunk 选择）

    private var diffPanel: some View {
        VStack(spacing: 0) {
            if let file = vm.selectedFile {
                diffHeader(file)
                if !file.isBinary && !file.hunks.isEmpty {
                    hunkBar(file)
                }
                if file.isBinary {
                    EmptyStateView(title: "二进制文件", hint: "图片 diff 在 P1 支持（MRD 10.1）")
                } else {
                    DiffFileView(file: file)
                }
            } else {
                EmptyStateView(title: "未选择文件", hint: "在左侧选择文件查看 diff")
            }
        }
        .onChange(of: vm.selectedFile?.id) {
            hunkSelection = []
        }
    }

    private func diffHeader(_ file: FileDiff) -> some View {
        HStack(spacing: GSSpacing.s) {
            Text(file.path)
                .font(.gsMonoSmall)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text("+\(file.additions)").font(.gsMonoSmall).foregroundStyle(Color.gs(.green))
            Text("−\(file.deletions)").font(.gsMonoSmall).foregroundStyle(Color.gs(.red))
        }
        .padding(.horizontal, GSSpacing.m)
        .padding(.vertical, GSSpacing.s)
        .background(Color.primary.opacity(0.03))
    }

    private func hunkBar(_ file: FileDiff) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: GSSpacing.s) {
                Text("共 \(file.hunks.count) 个 hunk")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("全选") { hunkSelection = Set(file.hunks.map(\.id)) }
                    .buttonStyle(.link)
                    .font(.caption)
                if vm.selectedSide == .unstaged {
                    stageHunkButton(file: file, title: "暂存选中块") { ids in
                        try? await vm.stageHunks(of: file, hunkIDs: ids)
                    }
                    Button("暂存全部") {
                        Task {
                            try? await vm.stageFiles([file.path])
                            hunkSelection = []
                        }
                    }
                    .font(.caption)
                    Button("丢弃选中块…") {
                        let ids = hunkSelection.isEmpty ? Set(file.hunks.map(\.id)) : hunkSelection
                        pendingDiscard = .hunks(file: file, ids: ids)
                    }
                    .font(.caption)
                    .foregroundStyle(Color.gs(.red))
                } else {
                    stageHunkButton(file: file, title: "取消暂存选中块") { ids in
                        try? await vm.unstageHunks(of: file, hunkIDs: ids)
                    }
                }
            }
            .padding(.horizontal, GSSpacing.m)
            .padding(.vertical, 6)

            ForEach(file.hunks) { hunk in
                Toggle(isOn: Binding(
                    get: { hunkSelection.contains(hunk.id) },
                    set: { on in
                        if on { hunkSelection.insert(hunk.id) } else { hunkSelection.remove(hunk.id) }
                    }
                )) {
                    HStack(spacing: 6) {
                        Text(hunk.header)
                            .font(.gsMonoSmall)
                            .foregroundStyle(Color.gs(.accent))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("+\(hunk.additions) −\(hunk.deletions)")
                            .font(.gsMonoSmall)
                            .foregroundStyle(.tertiary)
                    }
                }
                .toggleStyle(.checkbox)
                .padding(.horizontal, GSSpacing.m)
                .padding(.vertical, 2)
            }
            Divider()
        }
    }

    private func stageHunkButton(file: FileDiff, title: String,
                                 action: @escaping (Set<Int>) async -> Void) -> some View {
        Button(title) {
            let ids = hunkSelection.isEmpty ? Set(file.hunks.map(\.id)) : hunkSelection
            Task {
                await action(ids)
                hunkSelection = []
            }
        }
        .font(.caption)
    }

    // MARK: 提交栏（EP04-F02 信息辅助 + EP04-F03 提交并推送）

    private var commitBar: some View {
        VStack(spacing: GSSpacing.s) {
            if vm.isMergeInProgress {
                HStack {
                    Label(
                        vm.canCommitMerge ? "冲突已全部解决，完成合并提交" : "仍有 \(vm.unmergedEntries.count) 个冲突文件未解决，不能提交",
                        systemImage: vm.canCommitMerge ? "checkmark.seal" : "exclamationmark.triangle"
                    )
                    .font(.callout.weight(.medium))
                    .foregroundStyle(vm.canCommitMerge ? Color.gs(.green) : Color.gs(.amber))
                    Spacer()
                }
            } else {
                commitMessageInput
                Toggle("追加到上一次提交（amend）", isOn: $vm.amend)
                    .font(.caption)
            }

            HStack {
                if let error = vm.lastErrorText {
                    Image(systemName: "xmark.octagon.fill")
                        .foregroundStyle(Color.gs(.red))
                    Text(error)
                        .font(.caption)
                        .lineLimit(2)
                        .foregroundStyle(Color.gs(.red))
                }
                Spacer()
                if vm.isMergeInProgress {
                    Button("中止合并", role: .destructive) {
                        Task { try? await vm.abortMerge() }
                    }
                }
                if !vm.isMergeInProgress {
                    Button {
                        commitAndPush()
                    } label: {
                        Label("提交并推送", systemImage: "arrow.up.circle")
                    }
                    .keyboardShortcut("\r", modifiers: [.command, .option])
                    .disabled(!vm.canCommit || vm.isBusy || isCommitting)
                }
                Button {
                    commitOnly()
                } label: {
                    Label(
                        vm.isMergeInProgress ? "完成合并提交" : (vm.amend ? "Amend 提交" : "提交"),
                        systemImage: "arrow.up.circle.fill"
                    )
                }
                .keyboardShortcut("\r", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .tint(Color.gs(.accent))
                .disabled(!vm.canCommit || vm.isBusy || isCommitting)
            }

            if let hook = vm.hookOutput {
                DisclosureGroup("钩子原始输出") {
                    ScrollView {
                        Text(hook)
                            .font(.gsMonoSmall)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 140)
                }
                .font(.caption)
            }
        }
        .padding(GSSpacing.m)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// 标题行：输入 + 长度计数 + 历史下拉（EP04-F02）。
    private var commitMessageInput: some View {
        VStack(alignment: .leading, spacing: GSSpacing.xs) {
            HStack(spacing: GSSpacing.s) {
                TextField("标题（第一行，可用卡片号前缀）", text: $vm.messageTitle)
                    .textFieldStyle(.roundedBorder)
                titleCounter
                historyMenu
            }
            TextEditor(text: $vm.messageBody)
                .font(.callout)
                .scrollContentBackground(.hidden)
                .frame(height: 48)
                .padding(6)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topLeading) {
                    if vm.messageBody.isEmpty {
                        Text("正文（可选，第二行起）")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(12)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    @ViewBuilder
    private var titleCounter: some View {
        switch vm.titleLengthState {
        case .normal(let count):
            Text("\(count) / 50").font(.gsMonoSmall).foregroundStyle(.tertiary)
        case .overRecommended(let count):
            Text("\(count) / 50").font(.gsMonoSmall).foregroundStyle(Color.gs(.amber))
                .help("标题超过 50 字符，建议精简")
        case .overLimit(let count):
            Label("\(count)", systemImage: "exclamationmark.triangle.fill")
                .font(.gsMonoSmall)
                .foregroundStyle(Color.gs(.red))
                .help("标题超过 72 字符")
        }
    }

    /// [v] 历史下拉：本仓最近 20 条提交标题；选中后整段替换。
    private var historyMenu: some View {
        Menu {
            if vm.recentSubjects.isEmpty {
                Text("暂无历史提交").font(.caption)
            } else {
                ForEach(Array(vm.recentSubjects.prefix(20).enumerated()), id: \.offset) { _, subject in
                    Button(subject.lineLimitText) {
                        vm.applyMessageText(subject)
                    }
                }
            }
        } label: {
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("历史提交信息（最近 20 条）")
    }

    private func commitOnly() {
        Task {
            isCommitting = true
            defer { isCommitting = false }
            do {
                _ = try await vm.commit()
                app.toasts.show("提交成功")
            } catch {
                app.toasts.show(GitPresenter.text(for: error), isError: true)
            }
        }
    }

    /// 提交并推送（EP04-F03，⌥⌘↩）：提交成功后进入推送确认（EP05-F02）。
    private func commitAndPush() {
        Task {
            isCommitting = true
            defer { isCommitting = false }
            do {
                _ = try await vm.commit()
                app.toasts.show("提交成功")
                if let repo = app.selectedRepo {
                    await app.openPushConfirmation(for: [repo])
                }
            } catch {
                app.toasts.show(GitPresenter.text(for: error), isError: true)
            }
        }
    }
}

/// 改动列表行。
struct ChangeRow: View {
    let title: String
    let kindLetter: String
    let isSelected: Bool
    let leadingActions: [(String, String, () -> Void)]
    let trailingAction: (String, String, () -> Void)?
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: GSSpacing.s) {
            Text(kindLetter)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(letterColor)
                .frame(width: 16, height: 16)
                .background(letterColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
            Text(title)
                .font(.gsMonoSmall)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            ForEach(Array(leadingActions.enumerated()), id: \.offset) { _, action in
                Button {
                    action.2()
                } label: {
                    Label(action.0, systemImage: action.1)
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .help(action.0)
            }
            if let trailing = trailingAction {
                Button {
                    trailing.2()
                } label: {
                    Label(trailing.0, systemImage: trailing.1)
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(Color.gs(.red))
                .help(trailing.0)
            }
        }
        .padding(.horizontal, GSSpacing.m)
        .padding(.vertical, 5)
        .background(
            isSelected ? Color.gs(.accent).opacity(0.12) : Color.clear,
            in: RoundedRectangle(cornerRadius: 5)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private var letterColor: Color {
        switch kindLetter {
        case "A", "U": return Color.gs(.green)
        case "D": return Color.gs(.red)
        case "R": return Color.gs(.purple)
        default: return Color.gs(.amber)
        }
    }
}

private extension String {
    /// 历史下拉菜单项的截断展示。
    var lineLimitText: String {
        count > 64 ? prefix(64) + "…" : self
    }
}
