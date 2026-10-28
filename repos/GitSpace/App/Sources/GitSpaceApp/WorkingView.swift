import SwiftUI
import GSFeatures
import GSGitEngine
import GSDesignKit

/// 改动视图：未暂存 / 已暂存两栏 + diff（文件级与块级暂存）+ 提交（MRD 10.6 流程五）。
struct WorkingView: View {
    @Environment(AppModel.self) private var app
    @Bindable var vm: RepoViewModel
    @State private var hunkSelection = Set<Int>()
    @State private var pendingDiscard: DiscardRequest?
    @State private var isCommitting = false

    struct DiscardRequest: Identifiable {
        let path: String
        let kind: RepoViewModel.DiscardKind
        var id: String { path + kind.rawValue }
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
            "丢弃 \"\(pendingDiscard?.path ?? "")\" 的改动？",
            isPresented: Binding(get: { pendingDiscard != nil }, set: { if !$0 { pendingDiscard = nil } }),
            titleVisibility: .visible
        ) {
            Button("丢弃（不可撤销）", role: .destructive) {
                guard let request = pendingDiscard else { return }
                Task {
                    do { try await vm.discard(path: request.path, kind: request.kind) }
                    catch { app.toasts.show(GitPresenter.text(for: error), isError: true) }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("该操作将把文件恢复到 HEAD 版本或删除未跟踪文件。")
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
                            pendingDiscard = DiscardRequest(
                                path: entry.path,
                                kind: (entry.indexKind != nil) ? .stagedAndWorktree : .worktree
                            )
                        })
                    ) {
                        vm.select(path: entry.path, side: .unstaged)
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
                            pendingDiscard = DiscardRequest(path: entry.path, kind: .untracked)
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
                    DiffTextView(file: file)
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

    // MARK: 提交栏

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
                TextEditor(text: $vm.message)
                    .font(.callout)
                    .scrollContentBackground(.hidden)
                    .frame(height: 56)
                    .padding(6)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .topLeading) {
                        if vm.message.isEmpty {
                            Text("提交信息（支持多行；历史建议在 P1 接入）")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .padding(12)
                                .allowsHitTesting(false)
                        }
                    }
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
                Button {
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
                } label: {
                    Label(
                        vm.isMergeInProgress ? "完成合并提交" : (vm.amend ? "Amend 提交" : "提交"),
                        systemImage: "arrow.up.circle.fill"
                    )
                }
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
