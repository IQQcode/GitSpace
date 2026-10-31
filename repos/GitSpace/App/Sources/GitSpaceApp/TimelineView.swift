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
                CommitRow(commit: commit)
                    .tag(commit.id)
            }
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
}

struct CommitRow: View {
    let commit: TimelineCommit

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
                if let ref = commit.commit.primaryRef {
                    Text(ref)
                        .font(.gsMonoSmall)
                        .foregroundStyle(Color.gs(.accent))
                        .lineLimit(1)
                }
            }
            .frame(width: 170, alignment: .leading)
        }
        .frame(height: GSGraph.rowHeight)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let commit = timeline.selectedCommit {
                header(commit: commit)
                Divider()
                fileList(commit: commit)
                if let file = timeline.selectedFiles.first(where: { $0.id == selectedFileID })
                    ?? timeline.selectedFiles.first {
                    Divider()
                    DiffTextView(file: file)
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
            if !commit.commit.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(commit.commit.body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(6)
            }
        }
        .padding(GSSpacing.m)
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
