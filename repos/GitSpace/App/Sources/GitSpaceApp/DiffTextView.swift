import SwiftUI
import AppKit
import GSGitEngine
import GSDesignKit

/// diff 渲染（AppKit NSTextView 承载，TechStack §4.3：万行级 diff 用 TextKit 保性能）。
/// 行内红绿高亮用 NSAttributedString；hunk 头与文件头用令牌色。
struct DiffTextView: NSViewRepresentable {
    let file: FileDiff

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isRichText = false
        textView.drawsBackground = false
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 10, height: 8)

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let attributed = NSMutableAttributedString()
        let bodyFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

        func append(_ line: String, foreground: NSColor, background: NSColor?) {
            var attributes: [NSAttributedString.Key: Any] = [.font: bodyFont, .foregroundColor: foreground]
            if let background {
                attributes[.backgroundColor] = background
            }
            attributed.append(NSAttributedString(string: line + "\n", attributes: attributes))
        }

        for headerLine in file.headerLines {
            append(headerLine, foreground: .tertiaryLabelColor, background: nil)
        }
        for hunk in file.hunks {
            append(hunk.header, foreground: .controlAccentColor, background: NSColor.controlAccentColor.withAlphaComponent(0.10))
            for line in hunk.lines {
                switch line.origin {
                case .add:
                    append(line.raw, foreground: NSColor.systemGreen, background: NSColor.systemGreen.withAlphaComponent(0.10))
                case .del:
                    append(line.raw, foreground: NSColor.systemRed, background: NSColor.systemRed.withAlphaComponent(0.09))
                case .context:
                    append(line.raw, foreground: .secondaryLabelColor, background: nil)
                case .meta:
                    append(line.raw, foreground: .tertiaryLabelColor, background: nil)
                }
            }
        }
        if attributed.length == 0 {
            append("(无内容差异)", foreground: .tertiaryLabelColor, background: nil)
        }
        textView.textStorage?.setAttributedString(attributed)
    }
}
