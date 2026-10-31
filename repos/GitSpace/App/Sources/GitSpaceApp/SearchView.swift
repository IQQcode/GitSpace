import SwiftUI
import GSFeatures
import GSIndex
import GSGitEngine
import GSDesignKit

/// 聚合检索视图：跨全部仓库按卡片号 / 提交信息 / 作者检索，按仓库分组展示并可生成 CR 清单。
struct SearchView: View {
    @Environment(AppModel.self) private var app
    @Bindable var timeline: TimelineModel
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            resultList
        }
    }

    // 顶部搜索条：放大镜 + 输入框 + 生成 CR 清单按钮
    private var searchBar: some View {
        HStack(spacing: GSSpacing.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("按卡片号 / 提交信息 / 作者检索", text: $query)
                .textFieldStyle(.roundedBorder)
            Spacer()
            Button("生成 CR 清单") { generateCRList() }
                .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, GSSpacing.m)
        .padding(.vertical, GSSpacing.s)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    // 结果区：空态与按仓库分组的命中列表
    @ViewBuilder
    private var resultList: some View {
        let keyword = query.trimmingCharacters(in: .whitespaces)
        if keyword.isEmpty {
            EmptyStateView(
                title: "输入关键字检索",
                hint: "支持卡片号 / 提交信息 / 作者，跨全部仓库"
            )
        } else {
            let hits = timeline.commits.filter(matches)
            if hits.isEmpty {
                EmptyStateView(
                    title: "没有匹配的提交",
                    hint: "换个关键字或检查仓库是否已加载"
                )
            } else {
                let grouped = Dictionary(grouping: hits, by: \.repoName)
                List {
                    ForEach(grouped.keys.sorted(), id: \.self) { repoName in
                        Section {
                            ForEach(grouped[repoName] ?? []) { commit in
                                CommitRow(commit: commit)
                            }
                        } header: {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(GSPalette.color(forName: repoName))
                                    .frame(width: 6, height: 6)
                                Text(repoName)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }
    // 检索命中判定：拼接关键信息做大小写不敏感包含匹配
    func matches(_ c: TimelineCommit) -> Bool {
        let kw = query.trimmingCharacters(in: .whitespaces)
        guard !kw.isEmpty else { return false }
        let hay = [c.commit.subject, c.commit.body, c.commit.authorName, c.commit.shortSHA, c.repoName].joined(separator: " ")
        return hay.localizedCaseInsensitiveContains(kw)
    }

    // 生成 CR 清单：命中项逐条拼接后写入系统剪贴板
    private func generateCRList() {
        let hits = timeline.commits.filter(matches)
        let lines = hits.map { commit in
            "\(commit.repoName)  \(commit.commit.shortSHA)  \(commit.commit.subject)"
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        app.toasts.show("已复制 CR 清单（\(hits.count) 条）")
    }
}
