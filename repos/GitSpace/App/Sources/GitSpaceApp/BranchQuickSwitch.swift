import SwiftUI
import GSFeatures
import GSGitEngine
import GSDesignKit

// 分支快速切换（Story-1031 UX 补齐）：
// 侧栏仓库行与提交视图头部的分支名点击即弹出本组件；
// 本地分支单击切换（脏工作区引导 stash），远程分支检出，底部进完整分支管理。

/// 分支快速切换弹层（popover 承载，按需加载分支列表）。
struct BranchQuickSwitchPopover: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let repo: ManagedRepo

    @State private var locals: [BranchInfo] = []
    @State private var remotes: [RemoteBranchInfo] = []
    @State private var isLoading = true
    @State private var pendingStashSwitch: String?

    private var currentBranch: String? { repo.status?.branch }

    var body: some View {
        VStack(alignment: .leading, spacing: GSSpacing.s) {
            HStack(spacing: GSSpacing.s) {
                Text("切换分支")
                    .font(.headline)
                Text(repo.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if dirtyHint {
                    Label("有未提交改动", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.gs(.amber))
                }
            }

            if isLoading {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("加载分支…").font(.caption).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(locals) { branch in
                            row(
                                title: branch.name,
                                isCurrent: branch.isCurrent,
                                subtitle: branch.upstream.map { "→ \($0)" },
                                ahead: branch.ahead,
                                behind: branch.behind
                            ) {
                                switchTo(branch.name)
                            }
                        }
                        if !remotes.isEmpty {
                            Divider().padding(.vertical, GSSpacing.xs)
                            Text("远程分支（检出为本地并建立 upstream）")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, GSSpacing.s)
                            ForEach(remotes) { remote in
                                row(
                                    title: remote.name,
                                    isCurrent: false,
                                    subtitle: nil,
                                    ahead: 0,
                                    behind: 0
                                ) {
                                    checkoutRemote(remote)
                                }
                            }
                        }
                        if locals.isEmpty && remotes.isEmpty {
                            Text("没有分支").font(.caption).foregroundStyle(.tertiary)
                                .padding(GSSpacing.m)
                        }
                    }
                }
                .frame(maxHeight: 260)
            }

            Divider()
            HStack {
                Spacer()
                Button("管理分支…") {
                    openFullBranchSheet()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(GSSpacing.m)
        .frame(width: 380)
        .task { await load() }
        .confirmationDialog(
            "工作区有未提交改动，切换到 \"\(pendingStashSwitch ?? "")\"？",
            isPresented: Binding(get: { pendingStashSwitch != nil }, set: { if !$0 { pendingStashSwitch = nil } }),
            titleVisibility: .visible
        ) {
            Button("stash 后切换") { stashThenSwitch() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("会先把当前改动保存到 stash，再切换分支。")
        }
    }

    private var dirtyHint: Bool {
        !(repo.status?.isClean ?? true)
    }

    private func row(
        title: String, isCurrent: Bool, subtitle: String?,
        ahead: Int, behind: Int,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
        } label: {
            HStack(spacing: GSSpacing.s) {
                Image(systemName: isCurrent ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isCurrent ? Color.gs(.green) : Color.secondary.opacity(0.4))
                Text(title)
                    .font(.gsMonoSmall.weight(isCurrent ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let subtitle {
                    Text(subtitle)
                        .font(.gsMonoSmall)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                if ahead > 0 || behind > 0 {
                    Text("↑\(ahead) ↓\(behind)")
                        .font(.gsMonoSmall)
                        .foregroundStyle(Color.gs(.amber))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, GSSpacing.s)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.001), in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isCurrent)
    }

    // MARK: 动作

    private func load() async {
        guard let engine = repo.engine else {
            isLoading = false
            return
        }
        async let localsTask = try? engine.localBranches()
        async let remotesTask = try? engine.remoteBranches()
        locals = (await localsTask) ?? []
        remotes = (await remotesTask) ?? []
        isLoading = false
    }

    private func switchTo(_ name: String) {
        guard let engine = repo.engine else { return }
        Task {
            do {
                try await engine.switchBranch(name: name)
                await app.refresh(repo)
                app.toasts.show("已切换到 \(name)")
                dismiss()
            } catch let error as GitError {
                if case .uncommittedChanges = error {
                    pendingStashSwitch = name
                } else {
                    app.toasts.show(GitPresenter.text(for: error), isError: true)
                }
            } catch {
                app.toasts.show(GitPresenter.text(for: error), isError: true)
            }
        }
    }

    private func stashThenSwitch() {
        guard let name = pendingStashSwitch, let engine = repo.engine else { return }
        pendingStashSwitch = nil
        Task {
            do {
                try await engine.stashPush(message: "GitSpace: 切换分支自动暂存")
                try await engine.switchBranch(name: name)
                await app.refresh(repo)
                app.toasts.show("已 stash 并切换到 \(name)")
                dismiss()
            } catch {
                app.toasts.show(GitPresenter.text(for: error), isError: true)
            }
        }
    }

    private func checkoutRemote(_ remote: RemoteBranchInfo) {
        guard let engine = repo.engine else { return }
        Task {
            do {
                try await engine.checkoutRemoteBranch(remote)
                await app.refresh(repo)
                app.toasts.show("已检出 \(remote.branchName)")
                dismiss()
            } catch let error as GitError {
                if case .uncommittedChanges = error {
                    app.toasts.show("工作区有未提交改动，检出远程分支前请先提交或 stash", isError: true)
                } else {
                    app.toasts.show(GitPresenter.text(for: error), isError: true)
                }
            } catch {
                app.toasts.show(GitPresenter.text(for: error), isError: true)
            }
        }
    }

    private func openFullBranchSheet() {
        app.selectedRepoPath = repo.id
        app.activeSheet = .branch
        dismiss()
    }
}

/// 分支名标签（可点击打开快速切换）。
struct BranchQuickSwitchLabel: View {
    @Environment(AppModel.self) private var app
    let repo: ManagedRepo
    var showsChevron = true

    @State private var showsPopover = false

    var body: some View {
        Button {
            showsPopover = true
        } label: {
            HStack(spacing: 3) {
                Text(repo.status?.branch ?? (repo.errorText != nil ? "读取失败" : "…"))
                    .font(.gsMonoSmall)
                    .foregroundStyle(repo.errorText != nil ? Color.gs(.red) : Color.gs(.accent))
                    .lineLimit(1)
                if showsChevron {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("点击切换分支")
        .popover(isPresented: $showsPopover, arrowEdge: .bottom) {
            BranchQuickSwitchPopover(repo: repo)
        }
    }
}
