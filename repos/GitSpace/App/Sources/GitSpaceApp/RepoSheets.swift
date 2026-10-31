import SwiftUI
import GSFeatures
import GSGitEngine
import GSDesignKit

// 把 RepoView 的 分支/合并/stash/tag 四段功能拆成独立弹窗, 并新增导入清单弹窗。
// 每个弹窗作用于调用方传入并已绑定到当前选中仓库的 RepoViewModel, 直接调用其方法。
// 版式参照 Sheets.swift 的 AddRepoSheet: 竖向 VStack(spacing: GSSpacing.m), 标题 .headline,
// .padding(GSSpacing.l), .frame(width:), 底部主按钮 borderedProminent tint Color.gs(.accent)。
// 破坏性操作(删分支 / Drop stash / 删 tag / 中止合并)均走 confirmationDialog 二次确认。

// MARK: - 分支弹窗

struct BranchSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Bindable var vm: RepoViewModel

    // 新建分支输入
    @State private var newBranchName = ""
    @State private var newBranchFrom = ""
    // 待删除分支(触发删除二次确认)
    @State private var branchPendingDelete: BranchInfo?
    // 脏工作区切换时待处理的目标分支名(触发 stash 后切换二次确认)
    @State private var switchPendingStash: String?

    var body: some View {
        VStack(alignment: .leading, spacing: GSSpacing.m) {
            Text("分支").font(.headline)

            // 新建并切换
            HStack(spacing: GSSpacing.s) {
                TextField("新分支名(如 feature/task-123)", text: $newBranchName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
                Picker("基于", selection: $newBranchFrom) {
                    Text("当前 HEAD").tag("")
                    ForEach(vm.branches, id: \.name) { branch in
                        Text(branch.name).tag(branch.name)
                    }
                }
                .frame(width: 180)
                Button("创建并切换") { createBranch() }
                    .disabled(newBranchName.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Divider()

            // 本地分支列表 加 远程分支检出
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(vm.branches) { branch in
                        BranchSheetRow(
                            branch: branch,
                            onSwitch: { switchBranch(branch) },
                            onRename: { renameBranch(branch) },
                            onDelete: { branchPendingDelete = branch }
                        )
                    }
                    if !vm.remoteBranches.isEmpty {
                        Divider().padding(.vertical, GSSpacing.xs)
                        Text("远程分支(检出为本地并建立 upstream)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                        ForEach(vm.remoteBranches) { remote in
                            HStack {
                                Text(remote.name).font(.gsMonoSmall)
                                Spacer()
                                Button("检出") { checkoutRemote(remote) }
                                    .buttonStyle(.link)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .frame(minHeight: 220)

            HStack {
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.gs(.accent))
            }
        }
        .padding(GSSpacing.l)
        .frame(width: 560, height: 500)
        // 脏工作区切换: stash 后切换 / 取消
        .confirmationDialog(
            "工作区有未提交改动, 无法直接切换到 \"\(switchPendingStash ?? "")\"",
            isPresented: Binding(get: { switchPendingStash != nil }, set: { if !$0 { switchPendingStash = nil } }),
            titleVisibility: .visible
        ) {
            Button("stash 后切换") { stashThenSwitch() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("会先把当前改动保存到 stash, 再切换分支。")
        }
        // 删除分支: 删除已合并 -d / 强制删除未合并 -D / 取消
        .confirmationDialog(
            "删除分支 \"\(branchPendingDelete?.name ?? "")\"?",
            isPresented: Binding(get: { branchPendingDelete != nil }, set: { if !$0 { branchPendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("删除已合并分支(-d)", role: .destructive) { deleteBranch(force: false) }
            Button("强制删除未合并分支(-D)", role: .destructive) { deleteBranch(force: true) }
            Button("取消", role: .cancel) {}
        } message: {
            Text("未合并分支强制删除后, 其提交只能通过 reflog 找回。")
        }
    }

    // MARK: 动作

    private func createBranch() {
        Task {
            do {
                try await vm.createBranch(name: newBranchName, from: newBranchFrom.isEmpty ? nil : newBranchFrom)
                newBranchName = ""
                app.toasts.show("分支已创建并切换")
            } catch {
                app.toasts.show(GitPresenter.text(for: error), isError: true)
            }
        }
    }

    private func switchBranch(_ branch: BranchInfo) {
        Task {
            do {
                try await vm.switchBranch(name: branch.name)
            } catch RepoViewModel.SwitchBlocker.dirtyWorkspace {
                // 脏工作区: 转交二次确认决定是否 stash 后切换
                switchPendingStash = branch.name
            } catch {
                app.toasts.show(GitPresenter.text(for: error), isError: true)
            }
        }
    }

    private func stashThenSwitch() {
        guard let name = switchPendingStash else { return }
        Task {
            do {
                try await vm.stashThenSwitchBranch(name: name)
                app.toasts.show("已 stash 并切换到 \(name)")
            } catch {
                app.toasts.show(GitPresenter.text(for: error), isError: true)
            }
        }
    }

    private func renameBranch(_ branch: BranchInfo) {
        Task {
            do {
                // 简单重命名: 追加 -renamed (与原 RepoView 口径一致)
                try await vm.renameBranch(oldName: branch.name, newName: branch.name + "-renamed")
            } catch {
                app.toasts.show(GitPresenter.text(for: error), isError: true)
            }
        }
    }

    private func checkoutRemote(_ remote: RemoteBranchInfo) {
        Task {
            do {
                try await vm.checkoutRemoteBranch(remote)
            } catch {
                app.toasts.show(GitPresenter.text(for: error), isError: true)
            }
        }
    }

    private func deleteBranch(force: Bool) {
        guard let branch = branchPendingDelete else { return }
        Task {
            do {
                try await vm.deleteBranch(name: branch.name, force: force)
                app.toasts.show("已删除分支 \(branch.name)")
            } catch {
                app.toasts.show(GitPresenter.text(for: error), isError: true)
            }
        }
    }
}

// MARK: 分支行视图(等价于 RepoView.BranchRow, 这里自带 fileprivate 实现)

fileprivate struct BranchSheetRow: View {
    let branch: BranchInfo
    let onSwitch: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: GSSpacing.s) {
            Image(systemName: branch.isCurrent ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(branch.isCurrent ? Color.gs(.green) : Color.secondary.opacity(0.4))
            Text(branch.name)
                .font(.callout.weight(branch.isCurrent ? .semibold : .regular))
            if let upstream = branch.upstream {
                Text("→ \(upstream)")
                    .font(.gsMonoSmall)
                    .foregroundStyle(branch.upstreamGone ? Color.gs(.red) : .secondary)
            }
            if branch.ahead > 0 || branch.behind > 0 {
                Text("↑\(branch.ahead) ↓\(branch.behind)")
                    .font(.gsMonoSmall)
                    .foregroundStyle(Color.gs(.amber))
            }
            Spacer()
            if !branch.isCurrent {
                Button("切换", action: onSwitch).buttonStyle(.link)
                Button("重命名", action: onRename).buttonStyle(.link)
                Button("删除…", action: onDelete).buttonStyle(.link).foregroundStyle(Color.gs(.red))
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - 合并弹窗

struct MergeSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Bindable var vm: RepoViewModel
    @AppStorage("mergeTool") private var mergeToolRaw = "filemerge"
    @AppStorage("mergeToolCustomTemplate") private var mergeToolCustomTemplate = ""

    // 中止合并二次确认
    @State private var showAbortConfirm = false
    // 外部合并工具运行状态（EP07-F02）
    @State private var toolRun: ExternalToolRun?
    // 两者都保留编辑目标（EP07-F03）
    @State private var bothKeepTarget: UnmergedEntry?

    struct ExternalToolRun: Identifiable {
        let id = UUID()
        let path: String
        var state: State
        enum State: Equatable {
            case running
            case finished(ExternalMergeToolLauncher.RunResult)
        }
    }

    // 合并来源候选: 非当前本地分支 加 远程分支
    private var mergeCandidates: [String] {
        vm.branches.filter { !$0.isCurrent }.map(\.name)
            + vm.remoteBranches.map(\.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: GSSpacing.m) {
            Text("合并与冲突").font(.headline)

            if vm.isMergeInProgress {
                mergeInProgressView
            } else {
                mergeStartView
            }

            Divider()
            HStack {
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.gs(.accent))
            }
        }
        .padding(GSSpacing.l)
        .frame(width: 620, height: 520)
        // 中止合并二次确认
        .confirmationDialog(
            "中止本次合并?",
            isPresented: $showAbortConfirm,
            titleVisibility: .visible
        ) {
            Button("中止合并", role: .destructive) { abortMerge() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("工作区会回到合并前的状态, 已解决的冲突标记将丢失。")
        }
        // 两者都保留：编辑预览（EP07-F03）
        .sheet(item: $bothKeepTarget) { conflict in
            BothKeepSheet(vm: vm, conflict: conflict)
        }
    }

    // 合并进行中: 冲突列表 加 完成提交 / 中止 / 外部工具 / 两者都保留
    @ViewBuilder
    private var mergeInProgressView: some View {
        if let run = toolRun {
            externalToolStateView(run)
            Divider()
        }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(vm.unmergedEntries) { conflict in
                    MergeConflictRow(
                        conflict: conflict,
                        onResolve: { resolution in resolveConflict(conflict, resolution) },
                        onMarkResolved: { markResolved(conflict) },
                        onOpenExternal: { openExternalTool(conflict) },
                        onBothKeep: { bothKeepTarget = conflict }
                    )
                }
            }
        }
        .frame(minHeight: 180)

        HStack {
            if vm.canCommitMerge {
                Button("完成合并提交") { commitMerge() }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.gs(.accent))
            } else {
                Text("解决全部冲突后才能提交(当前 \(vm.unmergedEntries.count) 个未解决)")
                    .font(.caption)
                    .foregroundStyle(Color.gs(.amber))
            }
            Spacer()
            Button("中止合并", role: .destructive) { showAbortConfirm = true }
        }
    }

    // 未在合并: 来源分支 Picker 加 no-ff 加 合并信息 加 合并按钮
    @ViewBuilder
    private var mergeStartView: some View {
        VStack(alignment: .leading, spacing: GSSpacing.s) {
            HStack(spacing: GSSpacing.s) {
                Text("来源分支 / 引用")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: $vm.mergeRefInput) {
                    Text("选择分支…").tag("")
                    ForEach(mergeCandidates, id: \.self) { candidate in
                        Text(candidate).tag(candidate)
                    }
                }
                .labelsHidden()
                .frame(width: 220)
            }
            Toggle("no-ff(生成合并提交)", isOn: $vm.mergeNoFF)
                .font(.caption)
            VStack(alignment: .leading, spacing: 4) {
                TextField("合并信息（快进合并时忽略）", text: $vm.mergeMessageInput)
                    .textFieldStyle(.roundedBorder)
                Text("留空使用 git 默认信息；产生合并提交时以输入为准（EP07-F01）。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            HStack {
                Spacer()
                Button("合并") { merge() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.gs(.accent))
                    .disabled(vm.mergeRefInput.isEmpty || vm.isDetached)
            }
        }
    }

    // MARK: 外部合并工具（EP07-F02）

    @ViewBuilder
    private func externalToolStateView(_ run: ExternalToolRun) -> some View {
        HStack(spacing: GSSpacing.s) {
            switch run.state {
            case .running:
                ProgressView().controlSize(.small)
                Text("外部工具处理 \"\(run.path)\" 中…（FileMerge 需在窗口内保存后关闭）")
                    .font(.caption)
                Spacer()
                Button("完成检查") { finishExternalTool(run) }
                    .font(.caption)
            case .finished(let result):
                switch result {
                case .cleared:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.gs(.green))
                    Text("\"\(run.path)\" 已无冲突标记")
                        .font(.caption)
                    Spacer()
                    Button("标记已解决") { markResolved(UnmergedEntry(path: run.path, code: "UU")) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(Color.gs(.accent))
                case .stillConflicted(let markers):
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.gs(.amber))
                    Text("仍有 \(markers) 处冲突标记，未自动标记解决")
                        .font(.caption)
                        .foregroundStyle(Color.gs(.amber))
                    Spacer()
                    Button("重新打开") { openExternalTool(UnmergedEntry(path: run.path, code: "UU")) }
                        .font(.caption)
                    Button("完成检查") { finishExternalTool(run) }
                        .font(.caption)
                case .timedOut:
                    Image(systemName: "clock.badge.exclamationmark").foregroundStyle(Color.gs(.amber))
                    Text("等待外部工具超时，可手动完成检查")
                        .font(.caption)
                        .foregroundStyle(Color.gs(.amber))
                    Spacer()
                    Button("完成检查") { finishExternalTool(run) }
                        .font(.caption)
                }
            }
        }
        .padding(GSSpacing.s)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    private func openExternalTool(_ conflict: UnmergedEntry) {
        guard let repo = vm.repo else { return }
        let tool = ExternalMergeTool(rawValue: mergeToolRaw) ?? .filemerge
        let template = tool.template ?? mergeToolCustomTemplate
        guard !template.trimmingCharacters(in: .whitespaces).isEmpty else {
            app.toasts.show("请先在设置中配置合并工具命令", isError: true)
            return
        }
        Task {
            do {
                let stages = try await vm.conflictStageContents(path: conflict.path)
                let mergedURL = repo.config.fileURL(conflict.path)
                toolRun = ExternalToolRun(path: conflict.path, state: .running)
                let result = try await ExternalMergeToolLauncher.run(
                    template: template, mergedPath: mergedURL, stages: stages
                )
                // 手动「完成检查」已先写入结果时不再覆盖
                if case .running = toolRun?.state {
                    toolRun?.state = .finished(result)
                }
            } catch {
                toolRun = nil
                app.toasts.show(GitPresenter.text(for: error), isError: true)
            }
        }
    }

    private func finishExternalTool(_ run: ExternalToolRun) {
        guard let repo = vm.repo else { return }
        let count = ExternalMergeToolLauncher.markerCount(
            of: repo.config.fileURL(run.path)
        )
        toolRun?.state = .finished(count == 0 ? .cleared : .stillConflicted(markers: count))
    }

    // MARK: 动作

    private func merge() {
        Task {
            do {
                let outcome = try await vm.merge(ref: vm.mergeRefInput)
                switch outcome {
                case .conflicts:
                    app.toasts.show("存在冲突, 请在列表中解决", isError: true)
                default:
                    // 合并完成提示「立即推送」（EP07-F01）
                    app.toasts.showWithAction(vm.lastMergeOutcomeText ?? "合并完成", actionLabel: "推送") {
                        Task {
                            if let repo = vm.repo {
                                await app.openPushConfirmation(for: [repo])
                            }
                        }
                    }
                }
            } catch {
                app.toasts.show(GitPresenter.text(for: error), isError: true)
            }
        }
    }

    private func resolveConflict(_ conflict: UnmergedEntry, _ resolution: ConflictResolution) {
        Task {
            do {
                try await vm.resolveConflict(path: conflict.path, resolution: resolution)
            } catch {
                app.toasts.show(GitPresenter.text(for: error), isError: true)
            }
        }
    }

    private func markResolved(_ conflict: UnmergedEntry) {
        Task {
            do {
                try await vm.markConflictResolved(path: conflict.path)
                if toolRun?.path == conflict.path { toolRun = nil }
                app.toasts.show("已标记解决 \(conflict.path)")
            } catch {
                app.toasts.show(GitPresenter.text(for: error), isError: true)
            }
        }
    }

    private func commitMerge() {
        Task {
            do {
                _ = try await vm.commit()
                app.toasts.showWithAction("合并完成", actionLabel: "推送") {
                    Task {
                        if let repo = vm.repo {
                            await app.openPushConfirmation(for: [repo])
                        }
                    }
                }
            } catch {
                app.toasts.show(GitPresenter.text(for: error), isError: true)
            }
        }
    }

    private func abortMerge() {
        Task {
            do {
                try await vm.abortMerge()
                app.toasts.show("已中止合并")
            } catch {
                app.toasts.show(GitPresenter.text(for: error), isError: true)
            }
        }
    }
}


// MARK: 冲突行视图(等价于 RepoView.ConflictRow, 这里自带 fileprivate 实现)

fileprivate struct MergeConflictRow: View {
    let conflict: UnmergedEntry
    let onResolve: (ConflictResolution) -> Void
    let onMarkResolved: () -> Void
    let onOpenExternal: () -> Void
    let onBothKeep: () -> Void

    var body: some View {
        HStack(spacing: GSSpacing.s) {
            Text(conflict.code)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.gs(.red))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.gs(.red).opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
            Text(conflict.path)
                .font(.gsMonoSmall)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Menu {
                Button("取当前 (ours)") { onResolve(.ours) }
                Button("取对方 (theirs)") { onResolve(.theirs) }
                Divider()
                Button("两者都保留…") { onBothKeep() }
                Button("用外部工具打开…") { onOpenExternal() }
            } label: {
                Text("处理 ▾")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Button("标记已解决") { onMarkResolved() }.buttonStyle(.bordered)
        }
        .padding(.vertical, 3)
    }
}

// MARK: - 两者都保留（EP07-F03）
// 编辑预览当前带标记的工作区内容，用户确认后写入并 git add；
// 未编辑时写入内容与 `git checkout --conflict=merge` 生成文本一致。

struct BothKeepSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Bindable var vm: RepoViewModel
    let conflict: UnmergedEntry

    @State private var content = ""
    @State private var isLoaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: GSSpacing.m) {
            Text("两者都保留 · \(conflict.path)").font(.headline)
            Text("编辑带冲突标记的合并结果；确认后写入工作区并标记已解决。")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $content)
                .font(.gsMono)
                .frame(minHeight: 280)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.gs(.panelBorder), lineWidth: 1))
            HStack {
                Text("剩余冲突标记 \(markCount) 处")
                    .font(.caption)
                    .foregroundStyle(markCount > 0 ? Color.gs(.amber) : Color.gs(.green))
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("写入并标记解决") { writeAndResolve() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.gs(.accent))
            }
        }
        .padding(GSSpacing.l)
        .frame(width: 640, height: 460)
        .onAppear {
            guard !isLoaded else { return }
            content = vm.readFile(path: conflict.path) ?? ""
            isLoaded = true
        }
    }

    private var markCount: Int {
        content.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.hasPrefix("<<<<<<<") }.count
    }

    private func writeAndResolve() {
        Task {
            do {
                try await vm.writeResolvedContent(path: conflict.path, content: content)
                app.toasts.show("已写入并标记解决 \(conflict.path)")
                dismiss()
            } catch {
                app.toasts.show(GitPresenter.text(for: error), isError: true)
            }
        }
    }
}

// MARK: - Stash 弹窗

struct StashSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Bindable var vm: RepoViewModel

    @State private var stashMessage = ""
    // 待丢弃 stash(触发二次确认)
    @State private var stashPendingDrop: StashInfo?
    // 选中 stash 的 diff（EP07-F04）
    @State private var selectedStash: StashInfo?
    @State private var selectedStashFileID: String?
    @State private var stashFiles: [FileDiff] = []
    @State private var isLoadingDiff = false

    var body: some View {
        VStack(alignment: .leading, spacing: GSSpacing.m) {
            Text("Stash").font(.headline)

            HStack(spacing: GSSpacing.s) {
                TextField("stash 描述(可选)", text: $stashMessage)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
                Button("保存 stash") { saveStash() }
            }

            Divider()
            HSplitView {
                stashList
                    .frame(minWidth: 250, idealWidth: 280, maxWidth: 360)
                stashDiffPane
                    .frame(minWidth: 320, maxWidth: .infinity)
            }
            .frame(minHeight: 240)

            HStack {
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.gs(.accent))
            }
        }
        .padding(GSSpacing.l)
        .frame(width: 760, height: 500)
        // 丢弃 stash 二次确认
        .confirmationDialog(
            "丢弃 stash \"\(stashPendingDrop?.message ?? "")\"?",
            isPresented: Binding(get: { stashPendingDrop != nil }, set: { if !$0 { stashPendingDrop = nil } }),
            titleVisibility: .visible
        ) {
            Button("丢弃", role: .destructive) { dropStash() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("丢弃后该 stash 内容不可恢复。")
        }
        .onChange(of: selectedStash?.id) {
            Task { await loadStashDiff() }
        }
        .onChange(of: vm.stashes.map(\.id)) {
            // pop / drop 后列表变化，清掉已不存在的选中项
            if let selected = selectedStash, !vm.stashes.contains(where: { $0.id == selected.id }) {
                selectedStash = nil
                stashFiles = []
            }
        }
    }

    private var stashList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(vm.stashes) { stash in
                    Button {
                        selectedStash = stash
                    } label: {
                        HStack {
                            Image(systemName: "archivebox")
                                .foregroundStyle(selectedStash?.id == stash.id ? AnyShapeStyle(Color.gs(.accent)) : AnyShapeStyle(.tertiary))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stash.message.isEmpty ? "(无描述)" : stash.message)
                                    .font(.callout)
                                    .lineLimit(1)
                                    .foregroundStyle(.primary)
                                Text(relative(stash.timestamp))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, GSSpacing.s)
                        .padding(.vertical, 5)
                        .background(
                            selectedStash?.id == stash.id ? Color.gs(.accent).opacity(0.1) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Pop（恢复并删除）") { restore(stash, pop: true) }
                        Button("Apply（恢复保留）") { restore(stash, pop: false) }
                        Divider()
                        Button("丢弃…", role: .destructive) { stashPendingDrop = stash }
                    }
                }
                if vm.stashes.isEmpty {
                    Text("暂无 stash").font(.caption).foregroundStyle(.tertiary)
                        .padding(.top, GSSpacing.m)
                }
            }
            .padding(.vertical, 2)
        }
    }

    /// 右侧：文件列表 + diff（`git stash show -p stash@{n}`，EP07-F04）。
    @ViewBuilder
    private var stashDiffPane: some View {
        if let stash = selectedStash {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: GSSpacing.s) {
                    Text("stash@{\(stash.index)}").font(.gsMonoSmall).foregroundStyle(Color.gs(.accent))
                    Spacer()
                    Button("Pop") { restore(stash, pop: true) }.buttonStyle(.link)
                    Button("Apply") { restore(stash, pop: false) }.buttonStyle(.link)
                    Button("丢弃…") { stashPendingDrop = stash }
                        .buttonStyle(.link)
                        .foregroundStyle(Color.gs(.red))
                }
                .padding(.horizontal, GSSpacing.s)
                .padding(.vertical, 6)

                if isLoadingDiff {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("加载 stash diff…").font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(GSSpacing.m)
                } else if stashFiles.isEmpty {
                    EmptyStateView(title: "无内容差异", hint: "该 stash 没有可展示的改动")
                } else {
                    ForEach(stashFiles) { file in
                        Button {
                            selectedStashFileID = file.id
                        } label: {
                            HStack(spacing: 6) {
                                Text(file.kind.rawValue)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Color.gs(.amber))
                                Text(file.path)
                                    .font(.gsMonoSmall)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer(minLength: 4)
                                Text("+\(file.additions) −\(file.deletions)")
                                    .font(.gsMonoSmall)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, GSSpacing.s)
                            .padding(.vertical, 3)
                            .background(
                                selectedStashFileID == file.id ? Color.primary.opacity(0.06) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 4)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Divider().padding(.vertical, 4)
                    if let file = stashFiles.first(where: { $0.id == selectedStashFileID }) ?? stashFiles.first {
                        DiffTextView(file: file)
                    }
                }
            }
        } else {
            EmptyStateView(title: "未选择 stash", hint: "在左侧选择一条 stash 查看内容 diff")
        }
    }

    private func loadStashDiff() async {
        guard let index = selectedStash?.index else { return }
        isLoadingDiff = true
        defer { isLoadingDiff = false }
        stashFiles = (try? await vm.stashDiff(index: index)) ?? []
        selectedStashFileID = stashFiles.first?.id
    }

    // MARK: 动作

    private func saveStash() {
        Task {
            do {
                try await vm.stashSave(message: stashMessage.isEmpty ? nil : stashMessage)
                stashMessage = ""
                app.toasts.show("已保存 stash")
            } catch {
                app.toasts.show(GitPresenter.text(for: error), isError: true)
            }
        }
    }

    private func restore(_ stash: StashInfo, pop: Bool) {
        Task {
            do {
                try await vm.stashRestore(index: stash.index, pop: pop)
                await loadStashDiff()
            } catch {
                app.toasts.show(GitPresenter.text(for: error), isError: true)
            }
        }
    }

    private func dropStash() {
        guard let stash = stashPendingDrop else { return }
        Task {
            do {
                try await vm.stashDrop(index: stash.index)
                app.toasts.show("已丢弃 stash")
            } catch {
                app.toasts.show(GitPresenter.text(for: error), isError: true)
            }
        }
    }

    private func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Tag 弹窗

struct TagSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Bindable var vm: RepoViewModel
    @State private var newTagName = ""
    @State private var newTagMessage = ""
    @State private var pushAfterCreate = false
    @State private var tagPendingDelete: TagInfo?
    @State private var tagPendingRemoteDelete: TagInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: GSSpacing.m) {
            Text("Tag").font(.headline)
            HStack(spacing: GSSpacing.s) {
                TextField("tag 名(如 v1.2.0)", text: $newTagName)
                    .textFieldStyle(.roundedBorder).frame(width: 160)
                TextField("附注信息(留空创建轻量 tag)", text: $newTagMessage)
                    .textFieldStyle(.roundedBorder).frame(width: 200)
                Button("创建") { createTag() }
                    .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Toggle("创建后同时推送到 origin（EP07-F05）", isOn: $pushAfterCreate)
                .font(.caption)
            Divider()
            tagList
            HStack { Spacer(); Button("完成") { dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(Color.gs(.accent)) }
        }
        .padding(GSSpacing.l)
        .frame(width: 560, height: 460)
        .confirmationDialog("删除 tag \"\(tagPendingDelete?.name ?? "")\"?", isPresented: Binding(get: { tagPendingDelete != nil }, set: { if !$0 { tagPendingDelete = nil } }), titleVisibility: .visible) {
            Button("删除", role: .destructive) { deleteTag() }
            Button("取消", role: .cancel) {}
        }
        // 删除远端 tag：`git push origin --delete <tag>`（非 force），强确认
        .confirmationDialog("删除远端 tag \"\(tagPendingRemoteDelete?.name ?? "")\"?", isPresented: Binding(get: { tagPendingRemoteDelete != nil }, set: { if !$0 { tagPendingRemoteDelete = nil } }), titleVisibility: .visible) {
            Button("删除远端 tag", role: .destructive) { deleteRemoteTag() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将从远端 origin 移除该 tag；本地 tag 保留。")
        }
    }
    private var tagList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(vm.tags) { tag in
                    HStack {
                        Image(systemName: "tag").foregroundStyle(Color.gs(.accent))
                        Text(tag.name).font(.callout.weight(.medium))
                        Text(tag.shortSHA).font(.gsMonoSmall).foregroundStyle(.tertiary)
                        if tag.isAnnotated { Text("annotated").font(.caption2).foregroundStyle(.tertiary) }
                        Spacer()
                        Button("推送") { pushTag(tag) }.buttonStyle(.link)
                        Button("删除远端…") { tagPendingRemoteDelete = tag }
                            .buttonStyle(.link)
                        Button("删除…") { tagPendingDelete = tag }
                            .buttonStyle(.link).foregroundStyle(Color.gs(.red))
                    }
                    .padding(.vertical, 3)
                }
                if vm.tags.isEmpty { Text("暂无 tag").font(.caption).foregroundStyle(.tertiary) }
            }
        }
        .frame(minHeight: 200)
    }

    private func createTag() {
        Task {
            do {
                try await vm.createTag(name: newTagName, message: newTagMessage.isEmpty ? nil : newTagMessage)
                let name = newTagName
                newTagName = ""; newTagMessage = ""
                if pushAfterCreate {
                    try await vm.pushTag(name: name)
                    app.toasts.show("tag \(name) 已创建并推送")
                } else {
                    app.toasts.show("tag \(name) 已创建")
                }
            } catch { app.toasts.show(GitPresenter.text(for: error), isError: true) }
        }
    }

    private func pushTag(_ tag: TagInfo) {
        Task {
            do {
                try await vm.pushTag(name: tag.name)
                app.toasts.show("tag \(tag.name) 已推送")
            } catch { app.toasts.show(GitPresenter.text(for: error), isError: true) }
        }
    }

    private func deleteRemoteTag() {
        guard let tag = tagPendingRemoteDelete else { return }
        Task {
            do {
                try await vm.deleteRemoteTag(name: tag.name)
                app.toasts.show("远端 tag \(tag.name) 已删除")
            } catch { app.toasts.show(GitPresenter.text(for: error), isError: true) }
        }
    }

    private func deleteTag() {
        guard let tag = tagPendingDelete else { return }
        Task {
            do {
                try await vm.deleteTag(name: tag.name)
                app.toasts.show("已删除 tag \(tag.name)")
            } catch { app.toasts.show(GitPresenter.text(for: error), isError: true) }
        }
    }
}
// MARK: - 导入 mgit 清单弹窗

struct ImportManifestSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var isImporting = false

    var body: some View {
        VStack(alignment: .leading, spacing: GSSpacing.m) {
            Text("导入 mgit 清单").font(.headline)
            Text("每行一个仓库本地路径, 逐个加入当前工作区。支持 ~ 开头的用户目录。")
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(.gsMono)
                .frame(minHeight: 220)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.gs(.panelBorder), lineWidth: 1))
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button { importManifest() } label: {
                    if isImporting { ProgressView().controlSize(.small) } else { Text("导入") }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Color.gs(.accent))
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isImporting)
            }
        }
        .padding(GSSpacing.l)
        .frame(width: 520, height: 420)
    }
    private func importManifest() {
        let paths = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !paths.isEmpty else { return }
        isImporting = true
        Task {
            var added = 0
            for path in paths {
                let error = await app.addRepo(path: path)
                if error == nil { added += 1 }
            }
            isImporting = false
            app.toasts.show("已导入 \(added) / \(paths.count) 个仓库")
            dismiss()
        }
    }
}
