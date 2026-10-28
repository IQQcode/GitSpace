import SwiftUI
import GSFeatures
import GSDesignKit

/// 多仓状态总览（MRD 10.6 流程三/四）：统计卡 + 逐仓表格 + 批量操作条。
struct StatusView: View {
    @Environment(AppModel.self) private var app
    let onRunBatch: (BatchAction, [ManagedRepo]) -> Void
    @State private var selection = Set<String>()
    @State private var expanded = true

    var selectedRepos: [ManagedRepo] {
        app.repos.filter { selection.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: GSSpacing.m) {
                    statStrip
                    repoTable
                }
                .padding(GSSpacing.m)
                .padding(.bottom, 64)
            }
            .overlay(alignment: .bottom) {
                if !selection.isEmpty {
                    bulkBar
                }
            }
        }
    }

    private var statStrip: some View {
        HStack(spacing: GSSpacing.s) {
            StatCard(title: "纳管仓库", value: "\(app.repoCount)", unit: "个", color: nil)
            StatCard(title: "工作区干净", value: "\(app.cleanCount)", unit: "个", color: .green)
            StatCard(title: "待同步 / 未推送", value: "\(app.pendingSyncCount)", unit: "个", color: .amber)
            StatCard(title: "需要处理", value: "\(app.attentionCount)", unit: "个", color: app.attentionCount > 0 ? .red : .textMuted)
        }
    }

    private var repoTable: some View {
        VStack(spacing: 0) {
            panelHead
            Grid(horizontalSpacing: GSSpacing.s, verticalSpacing: 0) {
                tableHeader
                Divider().gridCellUnsizedAxes([.horizontal])
                ForEach(app.repos) { repo in
                    StatusRow(
                        repo: repo,
                        isSelected: selection.contains(repo.id),
                        onToggle: { toggle(repo) },
                        onFetch: { onRunBatch(.fetch, [repo]) },
                        onPull: { onRunBatch(.pull, [repo]) }
                    )
                    Divider().gridCellUnsizedAxes([.horizontal])
                }
            }
        }
        .overlay {
            if app.repos.isEmpty {
                EmptyStateView(title: "还没有仓库", hint: "点击左侧「添加仓库」或「扫描父目录」开始纳管")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    private var panelHead: some View {
        HStack(spacing: GSSpacing.s) {
            Text("仓库状态总览").font(.callout.weight(.semibold))
            Text("一屏看清每个仓库的分支、同步与未提交改动").font(.caption).foregroundStyle(.tertiary)
            Spacer()
            Button("选中待同步") {
                selection = Set(app.repos.filter { repo in
                    guard let status = repo.status else { return false }
                    return status.dirtyCount > 0 || status.ahead > 0 || status.behind > 0 || status.hasConflicts
                }.map(\.id))
            }
            .buttonStyle(.link)
            Button("取消选择") { selection = [] }
                .buttonStyle(.link)
        }
        .padding(.horizontal, GSSpacing.m)
        .padding(.vertical, GSSpacing.s)
        .background(Color.primary.opacity(0.03))
    }

    private var tableHeader: some View {
        GridRow {
            CheckBoxView(isOn: Binding(
                get: { selection.count == app.repos.count && !app.repos.isEmpty },
                set: { on in selection = on ? Set(app.repos.map(\.id)) : [] }
            ))
            .frame(maxWidth: 34)
            headerText("仓库", alignment: .leading)
            headerText("当前分支")
            headerText("同步")
            headerText("工作区")
            headerText("未推送")
            headerText("最近 Fetch")
            headerText("操作")
        }
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.03))
    }

    private func headerText(_ title: String, alignment: Alignment = .center) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: alignment)
    }

    private func toggle(_ repo: ManagedRepo) {
        if selection.contains(repo.id) {
            selection.remove(repo.id)
        } else {
            selection.insert(repo.id)
        }
    }

    private var bulkBar: some View {
        HStack(spacing: GSSpacing.s) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(Color.gs(.accent))
            Text("已选择 \(selection.count) 个仓库")
                .font(.callout.weight(.medium))
            Spacer()
            Button("批量 Fetch") { onRunBatch(.fetch, selectedRepos) }
            Button("批量 Pull") { onRunBatch(.pull, selectedRepos) }
            Button("批量 Push") { onRunBatch(.push, selectedRepos) }
                .buttonStyle(.borderedProminent)
                .tint(Color.gs(.accent))
        }
        .padding(.horizontal, GSSpacing.m)
        .padding(.vertical, GSSpacing.s)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.gs(.accent).opacity(0.5), lineWidth: 1)
        )
        .padding(GSSpacing.m)
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
    }
}

private struct StatusRow: View {
    @Environment(AppModel.self) private var app
    let repo: ManagedRepo
    let isSelected: Bool
    let onToggle: () -> Void
    let onFetch: () -> Void
    let onPull: () -> Void

    var body: some View {
        GridRow {
            CheckBoxView(isOn: .constant(isSelected), onToggle: onToggle)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Circle().fill(GSPalette.color(forSlot: repo.colorSlot)).frame(width: 7, height: 7)
                    Text(repo.displayName).font(.callout.weight(.semibold))
                }
                Text(repo.config.path)
                    .font(.gsMonoSmall)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            branchCell
            syncCell
            worktreeCell
            unpushedCell
            fetchedCell
            actionCell
        }
        .padding(.vertical, 8)
        .background(isSelected ? Color.gs(.accent).opacity(0.07) : Color.clear)
    }

    private var branchCell: some View {
        Group {
            if let status = repo.status {
                Text(status.branch ?? "(detached HEAD)")
                    .font(.gsMonoSmall)
                    .foregroundColor(status.detached ? Color.gs(.amber) : Color.gs(.accent))
                    .lineLimit(1)
            } else {
                Text("—").foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var syncCell: some View {
        Group {
            if let status = repo.status {
                if status.ahead > 0 || status.behind > 0 {
                    HStack(spacing: 6) {
                        Text("↑\(status.ahead)").font(.gsMonoSmall).foregroundStyle(Color.gs(.green))
                        Text("↓\(status.behind)").font(.gsMonoSmall).foregroundStyle(Color.gs(.amber))
                    }
                } else {
                    Text("已同步").font(.caption).foregroundStyle(.tertiary)
                }
            } else {
                Text("—").foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var worktreeCell: some View {
        Group {
            if let status = repo.status {
                if status.hasConflicts {
                    pill("⚡︎ 冲突中", color: .red)
                } else if status.dirtyCount > 0 {
                    pill("● \(status.dirtyCount) 个未提交", color: .amber)
                } else {
                    pill("✓ 干净", color: .green)
                }
            } else if repo.errorText != nil {
                pill("读取失败", color: .red)
            } else {
                ProgressView().controlSize(.mini)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var unpushedCell: some View {
        Group {
            if let status = repo.status {
                if status.upstream == nil {
                    Text("无上游").font(.caption).foregroundStyle(.tertiary)
                } else if status.ahead > 0 {
                    Text("\(status.ahead) 条").font(.gsMonoSmall).foregroundStyle(.primary)
                } else {
                    Text("—").foregroundStyle(.tertiary)
                }
            } else {
                Text("—").foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var fetchedCell: some View {
        Text(relativeText)
            .font(.gsMonoSmall)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
    }

    private var relativeText: String {
        guard let date = repo.lastFetched ?? repo.lastStatusUpdate else { return "—" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private var actionCell: some View {
        HStack(spacing: 4) {
            Button("Fetch", action: onFetch).buttonStyle(.link)
            Button("Pull", action: onPull).buttonStyle(.link)
            Button("访达") {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: repo.config.path)
            }
            .buttonStyle(.link)
        }
        .font(.caption)
        .frame(maxWidth: .infinity)
    }

    private func pill(_ text: String, color: GSColor) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(Color.gs(color))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.gs(color).opacity(0.13), in: Capsule())
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let unit: String
    let color: GSColor?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.tertiary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(color.map { Color.gs($0) } ?? Color.primary)
                Text(unit).font(.caption).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(GSSpacing.m)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
}

/// 原型样式的复选框（Grid 表格用）。
struct CheckBoxView: View {
    @Binding var isOn: Bool
    var onToggle: (() -> Void)?

    var body: some View {
        Button {
            isOn.toggle()
            onToggle?()
        } label: {
            Image(systemName: isOn ? "checkmark.square.fill" : "square")
                .foregroundStyle(isOn ? Color.gs(.accent) : Color.secondary)
        }
        .buttonStyle(.plain)
    }
}
