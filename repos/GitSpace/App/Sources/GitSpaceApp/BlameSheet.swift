import SwiftUI
import GSFeatures
import GSGitEngine
import GSDesignKit

/// 文件工具请求（Blame / 文件历史，sheet(item:) 用）；rev 非 nil 表示从指定提交开始。
struct FileToolRequest: Identifiable {
    let id = UUID()
    let path: String
    var rev: String? = nil
}

/// Blame 视图（EP03-F03）：左列短 SHA/作者/相对时间（同提交连续行只在首行显示），
/// 右列行号与内容；行右键「Blame 上一版本」追溯，后退/前进记录路径；点击行跳转时间线。
struct BlameSheet: View {
    @Environment(AppModel.self) private var app
    @Bindable var vm: RepoViewModel
    let request: FileToolRequest
    let onOpenCommit: (String) -> Void

    @State private var history: [String?]  // rev 栈；nil = 工作区
    @State private var historyIndex = 0
    @State private var result: BlameResult?
    @State private var isLoading = false
    @State private var hasLoaded = false

    private var currentRev: String? {
        history.indices.contains(historyIndex) ? history[historyIndex] : nil
    }

    init(vm: RepoViewModel, request: FileToolRequest, onOpenCommit: @escaping (String) -> Void) {
        self.vm = vm
        self.request = request
        self.onOpenCommit = onOpenCommit
        _history = State(initialValue: [request.rev])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: GSSpacing.s) {
            header
            Divider()
            if isLoading {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("加载 blame…").font(.caption).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let result {
                blameContent(result)
            } else {
                EmptyStateView(title: "无法加载 blame", hint: "该文件可能不存在于此版本")
            }
        }
        .padding(GSSpacing.l)
        .frame(width: 900, height: 640)
        .task {
            if !hasLoaded {
                hasLoaded = true
                await load()
            }
        }
    }

    private var header: some View {
        HStack(spacing: GSSpacing.s) {
            Text("Blame：\(app.selectedRepo?.displayName ?? "—") / \(request.path)")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            Text("@ \(currentRev.map { String($0.prefix(7)) } ?? "工作区")")
                .font(.gsMonoSmall)
                .foregroundStyle(Color.gs(.accent))
            Spacer()
            Button {
                guard historyIndex > 0 else { return }
                historyIndex -= 1
                Task { await load() }
            } label: {
                Image(systemName: "chevron.backward")
            }
            .buttonStyle(.borderless)
            .disabled(historyIndex == 0)
            .help("后退（追溯路径）")
            Button {
                guard historyIndex < history.count - 1 else { return }
                historyIndex += 1
                Task { await load() }
            } label: {
                Image(systemName: "chevron.forward")
            }
            .buttonStyle(.borderless)
            .disabled(historyIndex >= history.count - 1)
            .help("前进")
            Button("完成") { dismissSheet() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Color.gs(.accent))
        }
    }

    @ViewBuilder
    private func blameContent(_ result: BlameResult) -> some View {
        if result.lines.isEmpty {
            EmptyStateView(title: "空文件", hint: "该版本下文件没有内容")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(result.lines, id: \.lineNumber) { line in
                        BlameRow(
                            line: line,
                            commit: result.commits[line.sha],
                            onTap: { onOpenCommit(line.sha) },
                            onBlameParent: { blameParent(of: line) }
                        )
                    }
                }
            }
        }
    }

    private func blameParent(of line: BlameLine) {
        let parentRev = line.sha.prefix(7) + "^"
        // 去重连续追加
        history = Array(history.prefix(historyIndex + 1)) + [String(parentRev)]
        historyIndex = history.count - 1
        Task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            result = try await vm.blame(rev: currentRev, path: request.path)
        } catch {
            result = BlameResult(lines: [], commits: [:])
            app.toasts.show(GitPresenter.text(for: error), isError: true)
        }
    }

    @Environment(\.dismiss) private var dismiss
    private func dismissSheet() { dismiss() }
}

/// 单行：左侧信息列（组首行才显示）+ 行号 + 内容。
private struct BlameRow: View {
    let line: BlameLine
    let commit: BlameCommitInfo?
    let onTap: () -> Void
    let onBlameParent: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // 信息列
            ZStack(alignment: .leading) {
                Rectangle().fill(commitColor.opacity(0.55))
                if line.isGroupStart, let commit {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(commit.shortSHA)  \(commit.authorName)  \(relative(commit.authorTimestamp))")
                            .font(.gsMonoSmall)
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .padding(.horizontal, 5)
                }
            }
            .frame(width: 210, height: 17)
            // 行号
            Text("\(line.lineNumber)")
                .font(.gsMonoSmall)
                .foregroundStyle(.tertiary)
                .frame(width: 46, alignment: .trailing)
                .padding(.trailing, 6)
            // 内容
            Text(line.content.isEmpty ? " " : line.content)
                .font(.gsMonoSmall)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 17)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .help(commit.map { "\($0.shortSHA) \($0.authorName)：\($0.summary)" } ?? "")
        .contextMenu {
            Button("Blame 上一版本（\(line.sha.prefix(7))^）") { onBlameParent() }
            Button("在时间线中查看此提交") { onTap() }
        }
    }

    /// 按 SHA 着色：越新的提交越深（用提交时间参与色相偏移的简易映射）。
    private var commitColor: Color {
        guard let commit else { return Color.gs(.textMuted) }
        let hue = Double(abs(commit.sha.hashValue % 1000)) / 1000.0
        let depth = commit.isBoundary ? 0.5 : 1.0
        return Color(hue: hue, saturation: 0.45 * depth, brightness: 0.72 + 0.18 * (1 - hue))
    }

    private func relative(_ timestamp: Int) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(
            for: Date(timeIntervalSince1970: TimeInterval(timestamp)),
            relativeTo: Date()
        )
    }
}

// MARK: - 文件历史（EP03-F04）

/// 文件历史：左栏修改此文件的提交（--follow 含重命名前历史），
/// 右栏该提交对此文件的 diff；动作：与当前版本比较 / 取回此版本 / Blame 此版本。
struct FileHistorySheet: View {
    @Environment(AppModel.self) private var app
    @Bindable var vm: RepoViewModel
    let request: FileToolRequest
    let onOpenCommit: (String) -> Void
    let onOpenBlame: (String, String) -> Void

    @State private var history: [CommitInfo] = []
    @State private var selected: CommitInfo?
    @State private var selectedFile: FileDiff?
    @State private var compareAgainstCurrent = false
    @State private var compareFiles: [FileDiff] = []
    @State private var isLoading = false
    @State private var pendingRestore: CommitInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: GSSpacing.s) {
            Text("文件历史：\(request.path)")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            Divider()
            if isLoading {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("加载历史…").font(.caption).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if history.isEmpty {
                EmptyStateView(title: "没有历史", hint: "该文件还没有提交记录")
            } else {
                HSplitView {
                    commitList.frame(minWidth: 300, idealWidth: 340, maxWidth: 420)
                    diffPane.frame(minWidth: 420, maxWidth: .infinity)
                }
                actionBar
            }
        }
        .padding(GSSpacing.l)
        .frame(width: 980, height: 640)
        .task { await load() }
        .onChange(of: selected?.id) {
            Task { await loadSelectedChange() }
        }
        .confirmationDialog(
            "取回 \"\(request.path)\" 到 \(selected.map { String($0.shortSHA) } ?? "") 版本？",
            isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
            titleVisibility: .visible
        ) {
            Button("取回此版本", role: .destructive) { restoreSelected() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将用该版本内容覆盖当前工作区文件（等价 git restore --source）。")
        }
    }

    private var commitList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(history) { commit in
                    Button {
                        compareAgainstCurrent = false
                        selected = commit
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(commit.subject)
                                .font(.callout.weight(selected?.id == commit.id ? .semibold : .regular))
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                Text(commit.shortSHA).font(.gsMonoSmall).foregroundStyle(Color.gs(.accent))
                                Text(commit.authorName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                Text(relative(commit.authorTimestamp)).font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.horizontal, GSSpacing.s)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            selected?.id == commit.id ? Color.gs(.accent).opacity(0.1) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private var diffPane: some View {
        if compareAgainstCurrent {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("与当前工作区版本比较").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Button("返回此提交的改动") { compareAgainstCurrent = false }
                        .buttonStyle(.link).font(.caption)
                }
                .padding(.horizontal, GSSpacing.s)
                if let file = compareFiles.first {
                    DiffFileView(file: file)
                } else {
                    EmptyStateView(title: "无差异", hint: "该版本与当前工作区内容一致")
                }
            }
        } else if let file = selectedFile {
            DiffFileView(file: file)
        } else if selected != nil {
            EmptyStateView(title: "无改动", hint: "该提交没有改变此文件内容")
        } else {
            EmptyStateView(title: "未选择版本", hint: "在左侧选择一个版本查看它对该文件的改动")
        }
    }

    private var actionBar: some View {
        HStack(spacing: GSSpacing.s) {
            if let commit = selected {
                Text("\(commit.shortSHA) · \(commit.subject)")
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("与当前版本比较") { compareToCurrent(commit) }
                    .font(.caption)
                Button("Blame 此版本") { onOpenBlame(commit.sha, request.path) }
                    .font(.caption)
                Button("取回此版本…", role: .destructive) { pendingRestore = commit }
                    .font(.caption)
                    .foregroundStyle(Color.gs(.red))
            } else {
                Spacer()
            }
        }
        .padding(.top, GSSpacing.xs)
    }

    // MARK: 动作

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        history = (try? await vm.fileHistory(path: request.path)) ?? []
        selected = history.first
    }

    private func loadSelectedChange() async {
        guard let commit = selected else { return }
        selectedFile = (try? await vm.fileChangeAt(sha: commit.sha, path: request.path))?.first
    }

    private func compareToCurrent(_ commit: CommitInfo) {
        Task {
            compareFiles = (try? await vm.diffAgainstRevision(rev: commit.sha, path: request.path)) ?? []
            compareAgainstCurrent = true
        }
    }

    private func restoreSelected() {
        guard let commit = pendingRestore else { return }
        Task {
            do {
                try await vm.restoreFileFromRevision(rev: commit.sha, path: request.path)
                app.toasts.show("已取回 \(request.path) 的 \(commit.shortSHA) 版本")
            } catch {
                app.toasts.show(GitPresenter.text(for: error), isError: true)
            }
        }
    }

    private func relative(_ timestamp: Int) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(
            for: Date(timeIntervalSince1970: TimeInterval(timestamp)),
            relativeTo: Date()
        )
    }
}
