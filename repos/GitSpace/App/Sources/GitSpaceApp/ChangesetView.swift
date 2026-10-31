import SwiftUI
import GSFeatures
import GSIndex
import GSGitEngine
import GSDesignKit

/// 变更集视图：按卡片号聚合跨仓提交，左侧卡片列表，右侧卡片详情与交付清单。
struct ChangesetView: View {
    @Environment(AppModel.self) private var app
    @Bindable var timeline: TimelineModel
    var onOpenTimeline: (String) -> Void
    @State private var groups: [CardGroup] = []
    @State private var selectedCard: String?

    var body: some View {
        VStack(spacing: 0) {
            // 时间窗口截断时聚合可能不完整，顶部给出 amber 提示
            if !timeline.truncatedRepos.isEmpty {
                truncationBanner
            }
            HSplitView {
                cardList
                    .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
                detailPanel
                    .frame(minWidth: 360, idealWidth: 420, maxWidth: 520, maxHeight: .infinity)
            }
        }
        // 以提交数为键做缓存式重算，数量变化时才重新聚合
        .task(id: timeline.commits.count) {
            groups = CardAggregator.group(timeline.commits)
        }
    }

    // 截断提示条：仓名用顿号连接
    private var truncationBanner: some View {
        HStack(spacing: GSSpacing.s) {
            Image(systemName: "clock.badge.exclamationmark")
            Text("已按时间窗口截断：\(timeline.truncatedRepos.joined(separator: "、"))，卡片聚合可能不全")
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(Color.gs(.amber))
        .padding(.horizontal, GSSpacing.m)
        .padding(.vertical, 6)
        .background(Color.gs(.amber).opacity(0.1))
    }
    // 左侧：按卡片号聚合的卡片列表
    private var cardList: some View {
        List(selection: $selectedCard) {
            ForEach(groups) { group in
                CardGroupRow(group: group)
                    .tag(group.card)
            }
        }
        .listStyle(.plain)
        .overlay {
            if groups.isEmpty {
                EmptyStateView(
                    title: "暂无变更集",
                    hint: "添加仓库并刷新后，这里按卡片号聚合跨仓提交"
                )
            }
        }
    }

    // 右侧：选中卡片的跨仓提交详情
    private var detailPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let card = selectedCard,
               let group = groups.first(where: { $0.card == card }) {
                detailHeader(group: group)
                Divider()
                List {
                    ForEach(group.commits) { commit in
                        CommitRow(commit: commit)
                    }
                }
                .listStyle(.plain)
            } else {
                EmptyStateView(
                    title: "未选择卡片",
                    hint: "在左侧选择一个卡片号查看其跨仓提交"
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    // 详情头部：卡片号与汇总行，以及两个链接操作
    private func detailHeader(group: CardGroup) -> some View {
        VStack(alignment: .leading, spacing: GSSpacing.s) {
            Text(group.card.isEmpty ? "未关联卡片" : group.card)
                .font(.headline)
            Text("涉及 \(group.repoNames.count) 仓 · \(group.commits.count) 提交 · \(group.authorCount) 作者")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: GSSpacing.m) {
                Button("复制交付清单") { copyManifest(group: group) }
                    .buttonStyle(.link)
                Button("在时间线中查看") { onOpenTimeline(group.card) }
                    .buttonStyle(.link)
                    .disabled(group.card.isEmpty)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(GSSpacing.m)
    }

    // 把该卡片下每条提交拼成交付清单，首行为标题，写入系统剪贴板
    private func copyManifest(group: CardGroup) {
        let title = "交付清单 " + (group.card.isEmpty ? "未关联卡片" : group.card)
        let lines = group.commits.map { commit in
            "\(commit.repoName)  \(commit.commit.shortSHA)  \(commit.commit.subject)"
        }
        let text = ([title] + lines).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        app.toasts.show("已复制交付清单（\(group.commits.count) 条）")
    }
}

// MARK: - 卡片行

/// 单个卡片聚合行：卡片号与相对时间，以及涉及仓库的色点与计数。
fileprivate struct CardGroupRow: View {
    let group: CardGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(group.card.isEmpty ? "未关联卡片" : group.card)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(group.card.isEmpty ? Color.gs(.textMuted) : Color.primary)
                    .lineLimit(1)
                Spacer()
                Text(CommitRow.relative(group.latestTimestamp))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            HStack(spacing: 5) {
                ForEach(Array(group.repoNames.prefix(5)), id: \.self) { name in
                    Circle()
                        .fill(GSPalette.color(forName: name))
                        .frame(width: 6, height: 6)
                }
                Text("\(group.repoNames.count) 仓 · \(group.commits.count) 提交")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
