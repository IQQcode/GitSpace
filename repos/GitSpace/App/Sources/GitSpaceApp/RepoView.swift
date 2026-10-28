import SwiftUI
import GSFeatures
import GSGitEngine
import GSDesignKit

/// 分支 / 合并与冲突 / stash / tag（MRD 10.2-D/E/F）。
struct RepoView: View {
    @Environment(AppModel.self) private var app
    @Bindable var vm: RepoViewModel
    @State private var newBranchName = ""
    @State private var newBranchFrom = ""
    @State private var newTagName = ""
    @State private var newTagMessage = ""
    @State private var stashMessage = ""
    @State private var branchPendingDelete: BranchInfo?
    @State private var tagPendingDelete: TagInfo?
    @State private var stashPendingDrop: StashInfo?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GSSpacing.l) {
                mergeSection
                branchSection
                stashSection
                tagSection
            }
            .padding(GSSpacing.l)
        }
        .confirmationDialog(
            "删除分支 \"\(branchPendingDelete?.name ?? "")\"？",
            isPresented: Binding(get: { branchPendingDelete != nil }, set: { if !$0 { branchPendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("删除已合并分支（-d）", role: .destructive) { deleteBranch(force: false) }
            Button("强制删除未合并分支（-D）", role: .destructive) { deleteBranch(force: true) }
            Button("取消", role: .cancel) {}
        } message: {
            Text("未合并分支强制删除后，其提交只能通过 reflog 找回。")
        }
        .confirmationDialog(
            "删除 tag \"\(tagPendingDelete?.name ?? "")\"？",
            isPresented: Binding(get: { tagPendingDelete != nil }, set: { if !$0 { tagPendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                guard let tag = tagPendingDelete else { return }
                Task { try? await vm.deleteTag(name: tag.name) }
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog(
            "丢弃 stash \"\(stashPendingDrop?.message ?? "")\"？",
            isPresented: Binding(get: { stashPendingDrop != nil }, set: { if !$0 { stashPendingDrop = nil } }),
            titleVisibility: .visible
        ) {
            Button("丢弃", role: .destructive) {
                guard let stash = stashPendingDrop else { return }
                Task { try? await vm.stashDrop(index: stash.index) }
            }
            Button("取消", role: .cancel) {}
        }
    }

    // MARK: - 合并与冲突

    private var mergeSection: some View {
        Section {
            if vm.isMergeInProgress {
                ForEach(vm.unmergedEntries) { conflict in
                    ConflictRow(conflict: conflict) { resolution in
                        Task {
                            do { try await vm.resolveConflict(path: conflict.path, resolution: resolution) }
                            catch { app.toasts.show(GitPresenter.text(for: error), isError: true) }
                        }
                    } onMarkResolved: {
                        Task {
                            do { try await vm.markConflictResolved(path: conflict.path) }
                            catch { app.toasts.show(GitPresenter.text(for: error), isError: true) }
                        }
                    }
                }
                HStack {
                    if vm.canCommitMerge {
                        Button("完成合并提交") {
                            Task {
                                do {
                                    _ = try await vm.commit()
                                    app.toasts.show("合并完成")
                                } catch {
                                    app.toasts.show(GitPresenter.text(for: error), isError: true)
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.gs(.accent))
                    } else {
                        Text("解决全部冲突后才能提交（当前 \(vm.unmergedEntries.count) 个未解决）")
                            .font(.caption)
                            .foregroundStyle(Color.gs(.amber))
                    }
                    Spacer()
                    Button("中止合并", role: .destructive) {
                        Task { try? await vm.abortMerge() }
                    }
                }
            } else {
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
                    Toggle("no-ff（生成合并提交）", isOn: $vm.mergeNoFF)
                        .font(.caption)
                    Button("合并") {
                        Task {
                            do {
                                let outcome = try await vm.merge(ref: vm.mergeRefInput)
                                switch outcome {
                                case .conflicts:
                                    app.toasts.show("存在冲突，请在列表中解决", isError: true)
                                default:
                                    app.toasts.show(vm.lastMergeOutcomeText ?? "合并完成")
                                }
                            } catch {
                                app.toasts.show(GitPresenter.text(for: error), isError: true)
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.gs(.accent))
                    .disabled(vm.mergeRefInput.isEmpty || vm.isDetached)
                }
            }
        } header: {
            sectionTitle("合并与冲突", systemImage: "arrow.triangle.merge")
        }
    }

    private var mergeCandidates: [String] {
        vm.branches.filter { !$0.isCurrent }.map(\.name)
            + vm.remoteBranches.map(\.name)
    }

    private struct ConflictRow: View {
        let conflict: UnmergedEntry
        let onResolve: (ConflictResolution) -> Void
        let onMarkResolved: () -> Void

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
                Button("取当前 (ours)") { onResolve(.ours) }.buttonStyle(.link)
                Button("取对方 (theirs)") { onResolve(.theirs) }.buttonStyle(.link)
                Button("生成合并标记") { onResolve(.mergeMarkers) }.buttonStyle(.link)
                Button("标记已解决") { onMarkResolved() }.buttonStyle(.bordered)
            }
            .padding(.vertical, 3)
        }
    }

    // MARK: - 分支

    private var branchSection: some View {
        Section {
            HStack(spacing: GSSpacing.s) {
                TextField("新分支名（如 feature/task-123）", text: $newBranchName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
                Picker("基于", selection: $newBranchFrom) {
                    Text("当前 HEAD").tag("")
                    ForEach(vm.branches, id: \.name) { branch in
                        Text(branch.name).tag(branch.name)
                    }
                }
                .frame(width: 180)
                Button("创建并切换") {
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
                .disabled(newBranchName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.bottom, GSSpacing.xs)

            ForEach(vm.branches) { branch in
                BranchRow(
                    branch: branch,
                    onSwitch: {
                        Task {
                            do {
                                try await vm.switchBranch(name: branch.name)
                            } catch is RepoViewModel.SwitchBlocker {
                                app.toasts.show("工作区有未提交改动：请先提交或 stash（已在改动页可 stash）", isError: true)
                            } catch {
                                app.toasts.show(GitPresenter.text(for: error), isError: true)
                            }
                        }
                    },
                    onRename: {
                        Task {
                            do {
                                try await vm.renameBranch(oldName: branch.name, newName: renamedCandidate(branch.name))
                            } catch {
                                app.toasts.show(GitPresenter.text(for: error), isError: true)
                            }
                        }
                    },
                    onDelete: { branchPendingDelete = branch }
                )
            }

            if !vm.remoteBranches.isEmpty {
                Divider().padding(.vertical, GSSpacing.xs)
                Text("远程分支（检出为本地并建立 upstream）")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                ForEach(vm.remoteBranches) { remote in
                    HStack {
                        Text(remote.name).font(.gsMonoSmall)
                        Spacer()
                        Button("检出") {
                            Task {
                                do { try await vm.checkoutRemoteBranch(remote) }
                                catch { app.toasts.show(GitPresenter.text(for: error), isError: true) }
                            }
                        }
                        .buttonStyle(.link)
                    }
                    .padding(.vertical, 2)
                }
            }
        } header: {
            sectionTitle("分支（\(vm.branches.count) 本地 / \(vm.remoteBranches.count) 远程）", systemImage: "arrow.triangle.branch")
        }
    }

    private func renamedCandidate(_ name: String) -> String {
        // 简单重命名：追加 -renamed；正式重命名弹窗在 P1
        name + "-renamed"
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

    private struct BranchRow: View {
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

    // MARK: - stash

    private var stashSection: some View {
        Section {
            HStack(spacing: GSSpacing.s) {
                TextField("stash 描述（可选）", text: $stashMessage)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
                Button("保存 stash") {
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
            }
            .padding(.bottom, GSSpacing.xs)

            ForEach(vm.stashes) { stash in
                HStack {
                    Image(systemName: "archivebox")
                        .foregroundStyle(.tertiary)
                    Text(stash.message.isEmpty ? "(无描述)" : stash.message)
                        .font(.callout)
                        .lineLimit(1)
                    Text(relative(stash.timestamp))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button("Pop") {
                        Task {
                            do { try await vm.stashRestore(index: stash.index, pop: true) }
                            catch { app.toasts.show(GitPresenter.text(for: error), isError: true) }
                        }
                    }
                    .buttonStyle(.link)
                    Button("Apply") {
                        Task {
                            do { try await vm.stashRestore(index: stash.index, pop: false) }
                            catch { app.toasts.show(GitPresenter.text(for: error), isError: true) }
                        }
                    }
                    .buttonStyle(.link)
                    Button("丢弃…") { stashPendingDrop = stash }
                        .buttonStyle(.link)
                        .foregroundStyle(Color.gs(.red))
                }
                .padding(.vertical, 3)
            }
            if vm.stashes.isEmpty {
                Text("暂无 stash").font(.caption).foregroundStyle(.tertiary)
            }
        } header: {
            sectionTitle("Stash", systemImage: "archivebox")
        }
    }

    // MARK: - tag

    private var tagSection: some View {
        Section {
            HStack(spacing: GSSpacing.s) {
                TextField("tag 名（如 v1.2.0）", text: $newTagName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                TextField("附注信息（留空创建轻量 tag）", text: $newTagMessage)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
                Button("创建") {
                    Task {
                        do {
                            try await vm.createTag(
                                name: newTagName,
                                message: newTagMessage.isEmpty ? nil : newTagMessage
                            )
                            newTagName = ""
                            newTagMessage = ""
                            app.toasts.show("tag 已创建")
                        } catch {
                            app.toasts.show(GitPresenter.text(for: error), isError: true)
                        }
                    }
                }
                .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.bottom, GSSpacing.xs)

            ForEach(vm.tags) { tag in
                HStack {
                    Image(systemName: "tag")
                        .foregroundStyle(Color.gs(.accent))
                    Text(tag.name).font(.callout.weight(.medium))
                    Text(tag.shortSHA).font(.gsMonoSmall).foregroundStyle(.tertiary)
                    if tag.isAnnotated {
                        Text("annotated").font(.caption2).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button("删除…") { tagPendingDelete = tag }
                        .buttonStyle(.link)
                        .foregroundStyle(Color.gs(.red))
                }
                .padding(.vertical, 3)
            }
            if vm.tags.isEmpty {
                Text("暂无 tag").font(.caption).foregroundStyle(.tertiary)
            }
        } header: {
            sectionTitle("Tag", systemImage: "tag")
        }
    }

    private func sectionTitle(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.gs(.accent))
            Text(title)
                .font(.subheadline.weight(.semibold))
        }
    }

    private func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
