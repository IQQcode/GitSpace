import SwiftUI
import AppKit
import GSGitEngine
import GSDesignKit

// Diff 渲染重构（EP03-F01/F02）：文件标题栏 + 统一/并排切换 + 行号 + 词级高亮 + 改动导航。
// 万行级 diff 用 NSTextView 承载（TechStack §4.3）；并排两列同步滚动。

// MARK: - SwiftUI 外壳

/// 文件 diff 视图：标题栏（路径/增删/模式变化）+ 统一或并排正文 + 改动导航状态条。
struct DiffFileView: View {
    let file: FileDiff
    @AppStorage("diffViewMode") private var viewMode = DiffViewMode.unified.rawValue
    @State private var scrollRequest = DiffScrollRequest()

    var body: some View {
        VStack(spacing: 0) {
            DiffFileHeaderBar(file: file)
            if file.isBinary {
                EmptyStateView(title: "二进制文件", hint: "图片 diff 在 P1 支持（MRD 10.1）")
            } else if file.hunks.isEmpty {
                EmptyStateView(title: "无内容差异", hint: "该文件只有元数据变化（如权限）")
            } else if viewMode == DiffViewMode.split.rawValue {
                SplitDiffContainer(file: file, scrollRequest: $scrollRequest)
            } else {
                UnifiedDiffTextView(file: file, scrollRequest: $scrollRequest)
            }
            DiffNavigationBar(
                totalCount: file.hunks.count,
                currentIndex: $scrollRequest.hunkIndex,
                onPrevious: { scrollTo(-1) },
                onNext: { scrollTo(+1) }
            )
        }
    }

    private func scrollTo(_ delta: Int) {
        let count = file.hunks.count
        guard count > 0 else { return }
        let next = (scrollRequest.hunkIndex + delta + count) % count
        scrollRequest = DiffScrollRequest(hunkIndex: next)
    }
}

struct DiffScrollRequest: Equatable {
    var hunkIndex: Int = 0
    var token = UUID()
}

enum DiffViewMode: String, CaseIterable {
    case unified
    case split
}

/// 文件标题栏：取代原始 diff 头部行（EP03-F02 头部噪音治理）。
struct DiffFileHeaderBar: View {
    let file: FileDiff
    @AppStorage("diffViewMode") private var viewMode = DiffViewMode.unified.rawValue

    private var modeChangeText: String? {
        let old = file.headerLines.first { $0.hasPrefix("old mode ") }?
            .dropFirst("old mode ".count)
        let new = file.headerLines.first { $0.hasPrefix("new mode ") }?
            .dropFirst("new mode ".count)
        guard let old, let new, old != new else { return nil }
        return "\(old) → \(new)"
    }

    var body: some View {
        HStack(spacing: GSSpacing.s) {
            Text(file.kind.rawValue)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(statusColor)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(statusColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
            Text(pathText)
                .font(.gsMonoSmall)
                .lineLimit(1)
                .truncationMode(.middle)
            if let modeChangeText {
                Text("模式 \(modeChangeText)")
                    .font(.caption2)
                    .foregroundStyle(Color.gs(.purple))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.gs(.purple).opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            }
            Spacer()
            Text("+\(file.additions)").font(.gsMonoSmall).foregroundStyle(Color.gs(.green))
            Text("−\(file.deletions)").font(.gsMonoSmall).foregroundStyle(Color.gs(.red))
            Picker("", selection: $viewMode) {
                Text("统一").tag(DiffViewMode.unified.rawValue)
                Text("并排").tag(DiffViewMode.split.rawValue)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 110)
            .help("统一 / 并排视图（记住偏好，EP03-F01）")
        }
        .padding(.horizontal, GSSpacing.m)
        .padding(.vertical, GSSpacing.s)
        .background(Color.primary.opacity(0.03))
    }

    private var pathText: String {
        if let original = file.originalPath {
            return "\(original) → \(file.path)"
        }
        return file.path
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

/// 底部状态条：改动计数 + 上/下一处（快捷键 ⌘↑↓ 属 EP03-F05，批次 B）。
struct DiffNavigationBar: View {
    let totalCount: Int
    @Binding var currentIndex: Int
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: GSSpacing.s) {
            Text(totalCount > 0 ? "第 \(min(currentIndex + 1, totalCount)) / \(totalCount) 处改动" : "无改动块")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
            Button {
                onPrevious()
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(totalCount == 0)
            .help("上一处改动")
            Button {
                onNext()
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(totalCount == 0)
            .help("下一处改动")
        }
        .padding(.horizontal, GSSpacing.m)
        .padding(.vertical, 4)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .top) { Divider() }
    }
}

// MARK: - 共享渲染

enum DiffRenderer {
    static var font: NSFont { .monospacedSystemFont(ofSize: 11, weight: .regular) }
    static let gutterWidth = 5

    static var wordHighlightOld: NSColor { NSColor.systemRed.withAlphaComponent(0.30) }
    static var wordHighlightNew: NSColor { NSColor.systemGreen.withAlphaComponent(0.32) }
    static var fillerBackground: NSColor { NSColor.separatorColor.withAlphaComponent(0.10) }

    static func style(for origin: DiffLine.Origin) -> (foreground: NSColor, background: NSColor?) {
        switch origin {
        case .add: return (NSColor.systemGreen, NSColor.systemGreen.withAlphaComponent(0.10))
        case .del: return (NSColor.systemRed, NSColor.systemRed.withAlphaComponent(0.09))
        case .context: return (NSColor.secondaryLabelColor, nil)
        case .meta: return (NSColor.tertiaryLabelColor, nil)
        }
    }

    /// 行号槽位文本（nil → 空白）。
    static func gutter(_ number: Int?, width: Int = gutterWidth) -> String {
        guard let number else { return String(repeating: " ", count: width + 1) }
        return String(number).leftPadded(toWidth: width) + " "
    }

    /// 配对算法（EP03-F01）：del/add 相邻配对，单侧空白填充对齐。
    static func splitRows(for hunks: [DiffHunk]) -> [(old: DiffLine?, new: DiffLine?)] {
        var rows: [(old: DiffLine?, new: DiffLine?)] = []
        var pendingDels: [DiffLine] = []
        var pendingAdds: [DiffLine] = []

        func flush() {
            let pairCount = min(pendingDels.count, pendingAdds.count)
            for i in 0..<pairCount {
                rows.append((pendingDels[i], pendingAdds[i]))
            }
            for i in pairCount..<pendingDels.count {
                rows.append((pendingDels[i], nil))
            }
            for i in pairCount..<pendingAdds.count {
                rows.append((nil, pendingAdds[i]))
            }
            pendingDels = []
            pendingAdds = []
        }

        for hunk in hunks {
            for line in hunk.lines {
                switch line.origin {
                case .del:
                    pendingDels.append(line)
                case .add:
                    pendingAdds.append(line)
                case .context, .meta:
                    flush()
                    rows.append((line, line))
                }
            }
        }
        flush()
        return rows
    }

    /// hunk 内 del/add 配对的词级区间（按 hunk 内行索引）。
    /// 整行增删（另一侧为空）时 WordDiff 返回 nil，不做词级高亮。
    static func wordRanges(for hunk: DiffHunk) -> [Int: (old: Range<String.Index>?, new: Range<String.Index>?)] {
        var result: [Int: (old: Range<String.Index>?, new: Range<String.Index>?)] = [:]
        var pendingDels: [Int] = []
        var pendingAdds: [Int] = []

        func flush() {
            let pairCount = min(pendingDels.count, pendingAdds.count)
            for i in 0..<pairCount {
                let delIndex = pendingDels[i]
                let addIndex = pendingAdds[i]
                let segments = WordDiff.segments(old: hunk.lines[delIndex].text, new: hunk.lines[addIndex].text)
                result[delIndex] = (segments.old.range, nil)
                result[addIndex] = (nil, segments.new.range)
            }
            pendingDels = []
            pendingAdds = []
        }

        for (index, line) in hunk.lines.enumerated() {
            switch line.origin {
            case .del:
                pendingDels.append(index)
            case .add:
                pendingAdds.append(index)
            case .context, .meta:
                flush()
            }
        }
        flush()
        return result
    }
}

private extension String {
    func leftPadded(toWidth width: Int) -> String {
        count >= width ? self : String(repeating: " ", count: width - count) + self
    }
}

// MARK: - 统一视图

struct UnifiedDiffTextView: NSViewRepresentable {
    let file: FileDiff
    @Binding var scrollRequest: DiffScrollRequest

    func makeNSView(context: Context) -> NSScrollView {
        let textView = Self.makeTextView()
        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.drawsBackground = false
        context.coordinator.render(file: file, into: textView)
        context.coordinator.fileID = file.id
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if context.coordinator.fileID != file.id {
            context.coordinator.render(file: file, into: textView)
            context.coordinator.fileID = file.id
        }
        if context.coordinator.scrollToken != scrollRequest.token {
            context.coordinator.scrollToken = scrollRequest.token
            context.coordinator.scrollToHunk(scrollRequest.hunkIndex, in: textView)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    static func makeTextView() -> NSTextView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isRichText = false
        textView.drawsBackground = false
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 10, height: 8)
        return textView
    }

    final class Coordinator {
        var fileID = ""
        var scrollToken = UUID()
        /// 每个 hunk 起始字符位置（UTF-16 偏移），用于导航滚动。
        var hunkOffsets: [Int] = []

        func render(file: FileDiff, into textView: NSTextView) {
            let attributed = NSMutableAttributedString()
            var offsets: [Int] = []
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 1

            func append(_ text: String, foreground: NSColor, background: NSColor? = nil) {
                var attributes: [NSAttributedString.Key: Any] = [
                    .font: DiffRenderer.font,
                    .foregroundColor: foreground,
                    .paragraphStyle: paragraph
                ]
                if let background { attributes[.backgroundColor] = background }
                attributed.append(NSAttributedString(string: text, attributes: attributes))
            }

            if file.hunks.isEmpty {
                append("(无内容差异)", foreground: .tertiaryLabelColor)
            }
            for hunk in file.hunks {
                offsets.append(attributed.length)
                append(hunk.header + "\n", foreground: .controlAccentColor, background: NSColor.controlAccentColor.withAlphaComponent(0.10))
                let wordRanges = DiffRenderer.wordRanges(for: hunk)
                for (index, line) in hunk.lines.enumerated() {
                    let gutter = DiffRenderer.gutter(line.oldNumber) + DiffRenderer.gutter(line.newNumber) + "│ "
                    let style = DiffRenderer.style(for: line.origin)
                    append(gutter, foreground: .tertiaryLabelColor)
                    let contentStart = attributed.length
                    append(line.text + "\n", foreground: style.foreground, background: style.background)
                    if let highlight = wordRanges[index], line.origin == .del, let range = highlight.old {
                        applyWord(range, in: line.text, from: contentStart, color: DiffRenderer.wordHighlightOld, to: attributed)
                    }
                    if let highlight = wordRanges[index], line.origin == .add, let range = highlight.new {
                        applyWord(range, in: line.text, from: contentStart, color: DiffRenderer.wordHighlightNew, to: attributed)
                    }
                }
            }
            hunkOffsets = offsets
            textView.textStorage?.setAttributedString(attributed)
        }

        private func applyWord(
            _ range: Range<String.Index>,
            in text: String,
            from start: Int,
            color: NSColor,
            to attributed: NSMutableAttributedString
        ) {
            let nsRange = NSRange(range, in: text)
            attributed.addAttribute(
                .backgroundColor,
                value: color,
                range: NSRange(location: start + nsRange.location, length: nsRange.length)
            )
        }

        func scrollToHunk(_ index: Int, in textView: NSTextView) {
            guard hunkOffsets.indices.contains(index) else { return }
            textView.setSelectedRange(NSRange(location: hunkOffsets[index], length: 0))
            textView.scrollRangeToVisible(NSRange(location: hunkOffsets[index], length: 0))
        }
    }
}

// MARK: - 并排视图

/// 并排两列（EP03-F01）：两列放同一个外层 NSScrollView，行数与行高一致，天然同步滚动；
/// 单侧空白填充对齐、词级高亮。macOS 27 SDK 已移除 NSScrollViewDelegate，故不再做双滚动视同步。
struct SplitDiffContainer: NSViewRepresentable {
    let file: FileDiff
    @Binding var scrollRequest: DiffScrollRequest

    func makeNSView(context: Context) -> NSScrollView {
        let oldColumn = UnifiedDiffTextView.makeTextView()
        let newColumn = UnifiedDiffTextView.makeTextView()
        let stack = NSStackView(views: [oldColumn, newColumn])
        stack.orientation = .horizontal
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false

        let layout = context.coordinator.render(file: file, oldColumn: oldColumn, newColumn: newColumn)
        apply(layout: layout, stack: stack, oldColumn: oldColumn, newColumn: newColumn)

        let scrollView = NSScrollView()
        scrollView.documentView = stack
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        context.coordinator.scrollView = scrollView
        context.coordinator.fileID = file.id
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let stack = scrollView.documentView as? NSStackView,
              let oldColumn = stack.arrangedSubviews.first as? NSTextView,
              let newColumn = stack.arrangedSubviews.last as? NSTextView else { return }
        if context.coordinator.fileID != file.id {
            let layout = context.coordinator.render(file: file, oldColumn: oldColumn, newColumn: newColumn)
            apply(layout: layout, stack: stack, oldColumn: oldColumn, newColumn: newColumn)
            context.coordinator.fileID = file.id
        }
        if context.coordinator.scrollToken != scrollRequest.token {
            context.coordinator.scrollToken = scrollRequest.token
            context.coordinator.scrollToHunk(scrollRequest.hunkIndex)
        }
    }

    /// 统一两列宽度 = 两列内容最大宽度；高度按行数一致排布。
    private func apply(layout: SplitLayout, stack: NSStackView, oldColumn: NSTextView, newColumn: NSTextView) {
        let columnWidth = max(layout.maxColumnWidth, 320)
        for constraint in stack.constraints { constraint.isActive = false }
        NSLayoutConstraint.activate([
            oldColumn.widthAnchor.constraint(equalToConstant: columnWidth),
            newColumn.widthAnchor.constraint(equalToConstant: columnWidth),
            oldColumn.heightAnchor.constraint(equalTo: newColumn.heightAnchor)
        ])
        oldColumn.textContainer?.widthTracksTextView = true
        newColumn.textContainer?.widthTracksTextView = true
        oldColumn.textContainer?.containerSize = NSSize(width: columnWidth, height: .greatestFiniteMagnitude)
        newColumn.textContainer?.containerSize = NSSize(width: columnWidth, height: .greatestFiniteMagnitude)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    struct SplitLayout {
        var maxColumnWidth: CGFloat = 0
        /// hunk 头行索引（两列行数一致）。
        var hunkRowIndexes: [Int] = []
        var rowHeight: CGFloat = 0
    }

    final class Coordinator {
        var fileID = ""
        var scrollToken = UUID()
        var scrollView: NSScrollView?
        var layout = SplitLayout()

        /// 构建两列 attributed 文本并返回布局信息。
        func render(file: FileDiff, oldColumn: NSTextView, newColumn: NSTextView) -> SplitLayout {
            let oldAttr = NSMutableAttributedString()
            let newAttr = NSMutableAttributedString()
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 1
            var hunkRowIndexes: [Int] = []
            var rowIndex = 0
            var maxChars = 0

            func append(_ attributed: NSMutableAttributedString, _ text: String, foreground: NSColor, background: NSColor? = nil) {
                var attributes: [NSAttributedString.Key: Any] = [
                    .font: DiffRenderer.font,
                    .foregroundColor: foreground,
                    .paragraphStyle: paragraph
                ]
                if let background { attributes[.backgroundColor] = background }
                attributed.append(NSAttributedString(string: text, attributes: attributes))
            }

            typealias WordExtra = (range: Range<String.Index>, color: NSColor)

            func appendRow(old: DiffLine?, new: DiffLine?, oldExtra: WordExtra? = nil, newExtra: WordExtra? = nil) {
                // 旧列
                let oldGutter = DiffRenderer.gutter(old?.oldNumber)
                if let old {
                    let style = DiffRenderer.style(for: old.origin)
                    let contentStart = oldAttr.length + oldGutter.utf16.count
                    append(oldAttr, oldGutter, foreground: .tertiaryLabelColor)
                    append(oldAttr, old.text + "\n", foreground: style.foreground, background: style.background)
                    if let extra = oldExtra {
                        applyWord(extra, in: old.text, from: contentStart, to: oldAttr)
                    }
                    maxChars = max(maxChars, oldGutter.utf16.count + old.text.utf16.count)
                } else {
                    append(oldAttr, oldGutter, foreground: .tertiaryLabelColor)
                    append(oldAttr, " \n", foreground: .tertiaryLabelColor, background: DiffRenderer.fillerBackground)
                }
                // 新列
                let newGutter = DiffRenderer.gutter(new?.newNumber)
                if let new {
                    let style = DiffRenderer.style(for: new.origin)
                    let contentStart = newAttr.length + newGutter.utf16.count
                    append(newAttr, newGutter, foreground: .tertiaryLabelColor)
                    append(newAttr, new.text + "\n", foreground: style.foreground, background: style.background)
                    if let extra = newExtra {
                        applyWord(extra, in: new.text, from: contentStart, to: newAttr)
                    }
                    maxChars = max(maxChars, newGutter.utf16.count + new.text.utf16.count)
                } else {
                    append(newAttr, newGutter, foreground: .tertiaryLabelColor)
                    append(newAttr, " \n", foreground: .tertiaryLabelColor, background: DiffRenderer.fillerBackground)
                }
                rowIndex += 1
            }

            func flushPairs(_ dels: inout [(DiffLine, WordExtra?)], _ adds: inout [(DiffLine, WordExtra?)]) {
                let pairCount = min(dels.count, adds.count)
                for i in 0..<pairCount {
                    appendRow(old: dels[i].0, new: adds[i].0, oldExtra: dels[i].1, newExtra: adds[i].1)
                }
                for i in pairCount..<dels.count {
                    appendRow(old: dels[i].0, new: nil, oldExtra: dels[i].1)
                }
                for i in pairCount..<adds.count {
                    appendRow(old: nil, new: adds[i].0, newExtra: adds[i].1)
                }
                dels = []
                adds = []
            }

            for hunk in file.hunks {
                hunkRowIndexes.append(rowIndex)
                // hunk 头行：旧列显示 header，新列占位空行（两列行数一致）
                append(oldAttr, hunk.header + "\n", foreground: .controlAccentColor, background: NSColor.controlAccentColor.withAlphaComponent(0.10))
                append(newAttr, "\n", foreground: .tertiaryLabelColor)
                rowIndex += 1

                let wordRanges = DiffRenderer.wordRanges(for: hunk)
                var pendingDels: [(DiffLine, WordExtra?)] = []
                var pendingAdds: [(DiffLine, WordExtra?)] = []
                for (index, line) in hunk.lines.enumerated() {
                    switch line.origin {
                    case .del:
                        pendingDels.append((line, wordRanges[index]?.old.map { ($0, DiffRenderer.wordHighlightOld) }))
                    case .add:
                        pendingAdds.append((line, wordRanges[index]?.new.map { ($0, DiffRenderer.wordHighlightNew) }))
                    case .context, .meta:
                        flushPairs(&pendingDels, &pendingAdds)
                        appendRow(old: line, new: line)
                    }
                }
                flushPairs(&pendingDels, &pendingAdds)
            }

            oldColumn.textStorage?.setAttributedString(oldAttr)
            newColumn.textStorage?.setAttributedString(newAttr)

            let charWidth = ("M" as NSString).size(withAttributes: [.font: DiffRenderer.font]).width
            let rowHeight = ceil(DiffRenderer.font.ascender - DiffRenderer.font.descender) + 1
            let layout = SplitLayout(
                maxColumnWidth: CGFloat(maxChars) * charWidth + 24,
                hunkRowIndexes: hunkRowIndexes,
                rowHeight: rowHeight
            )
            self.layout = layout
            return layout
        }

        private func applyWord(
            _ extra: (range: Range<String.Index>, color: NSColor),
            in text: String,
            from start: Int,
            to attributed: NSMutableAttributedString
        ) {
            let nsRange = NSRange(extra.range, in: text)
            attributed.addAttribute(
                .backgroundColor,
                value: extra.color,
                range: NSRange(location: start + nsRange.location, length: nsRange.length)
            )
        }

        /// 行高一致 → 行索引可直接换算 y 偏移。
        func scrollToHunk(_ index: Int) {
            guard let scrollView,
                  layout.hunkRowIndexes.indices.contains(index) else { return }
            let y = CGFloat(layout.hunkRowIndexes[index]) * layout.rowHeight
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }
}
