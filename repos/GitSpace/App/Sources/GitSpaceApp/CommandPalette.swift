import SwiftUI
import GSDesignKit

// MARK: - 命令模型

/// 命令面板里的单条命令，与具体业务解耦：宿主负责构造并注入 label/shortcut/action。
struct PaletteCommand: Identifiable {
    let id = UUID()
    /// 列表中展示的命令名称。
    let label: String
    /// 右侧展示的快捷键提示（可空），例如 "⌘K"。
    let shortcut: String?
    /// 命令被触发时执行的动作。视图默认运行在 @MainActor，故此处用 @MainActor 闭包。
    let action: @MainActor () -> Void
}

// MARK: - 命令面板

/// 与业务解耦的命令面板：输入命令回车执行的弹层（对齐交互稿）。
/// 宿主以 overlay 挂载，并通过 isPresented 控制显隐。
struct CommandPaletteView: View {
    /// 全量命令，由宿主注入。
    let commands: [PaletteCommand]
    /// 搜索输入，受宿主绑定。
    @Binding var query: String
    /// 面板显隐，受宿主绑定。
    @Binding var isPresented: Bool
    /// 当前高亮行索引。
    @State private var highlight = 0
    /// 输入框焦点态。
    @FocusState private var focused: Bool

    /// 过滤后的命令：query 去空为空则返回全部，否则按 label 不区分大小写包含匹配。
    private var filtered: [PaletteCommand] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if keyword.isEmpty { return commands }
        return commands.filter { $0.label.localizedCaseInsensitiveContains(keyword) }
    }

    var body: some View {
        ZStack {
            // 底层：半透明遮罩铺满，点击空白处关闭面板
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            // 上层：居中卡片
            card
        }
    }

    // 卡片主体：三段式（搜索栏，命令列表，底部提示）
    private var card: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            commandList
            Divider()
            footer
        }
        .frame(width: 560)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 24, y: 8)
    }

    // 顶部搜索栏：放大镜图标 + 输入框 + 右侧 Esc 胶囊
    private var searchBar: some View {
        HStack(spacing: GSSpacing.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("输入命令，回车执行…", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($focused)
                // 键盘：下移高亮，并钳制在有效范围内
                .onKeyPress(.downArrow) {
                    highlight = min(highlight + 1, max(0, filtered.count - 1))
                    return .handled
                }
                // 键盘：上移高亮，下界为 0
                .onKeyPress(.upArrow) {
                    highlight = max(highlight - 1, 0)
                    return .handled
                }
                // 键盘：回车执行当前高亮命令并关闭
                .onKeyPress(.return) {
                    if filtered.indices.contains(highlight) {
                        filtered[highlight].action()
                        isPresented = false
                    }
                    return .handled
                }
                // 键盘：Esc 关闭面板
                .onKeyPress(.escape) {
                    isPresented = false
                    return .handled
                }
            Text("Esc")
                .font(.gsMonoSmall)
                .foregroundStyle(.secondary)
                .padding(.horizontal, GSSpacing.s)
                .padding(.vertical, GSSpacing.xs)
                .background(Color.primary.opacity(0.08), in: Capsule())
        }
        .padding(.horizontal, GSSpacing.m)
        .padding(.vertical, GSSpacing.m)
        // 输入变化时重置高亮到首行
        .onChange(of: query) { highlight = 0 }
        // 面板出现即聚焦输入框
        .onAppear { focused = true }
    }

    // 命令列表：可滚动，支持高亮与整行点击执行；无匹配时显示空态文案
    private var commandList: some View {
        ScrollView {
            if filtered.isEmpty {
                // 空结果占位
                Text("没有匹配的命令")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, GSSpacing.xl)
            } else {
                VStack(spacing: 2) {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, command in
                        commandRow(index: index, command: command)
                    }
                }
                .padding(GSSpacing.xs)
            }
        }
        .frame(maxHeight: 360)
    }

    // 单条命令行：左图标 + 命令名 + 右快捷键胶囊；高亮行着色，整行可点击
    private func commandRow(index: Int, command: PaletteCommand) -> some View {
        HStack(spacing: GSSpacing.s) {
            Image(systemName: "command")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(command.label)
            Spacer()
            if let shortcut = command.shortcut {
                Text(shortcut)
                    .font(.gsMonoSmall)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, GSSpacing.s)
                    .padding(.vertical, GSSpacing.xs)
                    .background(Color.primary.opacity(0.08), in: Capsule())
            }
        }
        .padding(.horizontal, GSSpacing.s)
        .padding(.vertical, GSSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(index == highlight ? Color.gs(.accent).opacity(0.15) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            command.action()
            isPresented = false
        }
    }

    // 底部提示栏：操作快捷键说明
    private var footer: some View {
        HStack(spacing: GSSpacing.m) {
            hint(key: "↑↓", text: "选择")
            hint(key: "↵", text: "执行")
            hint(key: "Esc", text: "关闭")
            Spacer()
        }
        .padding(.horizontal, GSSpacing.m)
        .padding(.vertical, GSSpacing.s)
    }

    // 单条提示：快捷键符号 + 文案
    private func hint(key: String, text: String) -> some View {
        HStack(spacing: GSSpacing.xs) {
            Text(key).font(.gsMonoSmall)
            Text(text).font(.caption)
        }
        .foregroundStyle(.secondary)
    }
}
