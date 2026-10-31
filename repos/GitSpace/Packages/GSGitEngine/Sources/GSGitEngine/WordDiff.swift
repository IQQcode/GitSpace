import Foundation

/// 行内词级差异（EP03-F02）：裁掉公共前缀与后缀，剩余区间即真正改动的部分。
/// 整行新增或删除（另一侧为空）时不做词级高亮（EP03 交互规格）。
public enum WordDiff {
    public struct Segment: Sendable, Equatable {
        /// 以 String.Index 表示的差异区间（nil 表示该行无行内差异）。
        public let range: Range<String.Index>?

        public static let none = Segment(range: nil)
    }

    /// 计算两行的行内差异区间。入参为去掉 +/- 前缀后的行内容。
    public static func segments(old: String, new: String) -> (old: Segment, new: Segment) {
        // 空行对非空行 = 整行增删，不做词级高亮
        guard !old.isEmpty, !new.isEmpty, old != new else {
            return (.none, .none)
        }
        let prefix = old.commonPrefix(with: new).count
        // 后缀长度受前缀约束，避免区间交叠（标准库无 commonSuffix，用反转求公共前缀）
        let remainingOld = old.count - prefix
        let remainingNew = new.count - prefix
        guard remainingOld > 0 || remainingNew > 0 else {
            return (.none, .none)
        }
        let oldTail = String(old.dropFirst(prefix))
        let newTail = String(new.dropFirst(prefix))
        let suffix = String(oldTail.reversed()).commonPrefix(with: String(newTail.reversed())).count
        let oldDiffLength = oldTail.count - suffix
        let newDiffLength = newTail.count - suffix
        guard oldDiffLength > 0 || newDiffLength > 0 else {
            return (.none, .none)
        }

        func range(in text: String, start: Int, length: Int) -> Range<String.Index> {
            let startIndex = text.index(text.startIndex, offsetBy: start)
            let endIndex = text.index(startIndex, offsetBy: length)
            return startIndex..<endIndex
        }

        let oldSegment = oldDiffLength > 0
            ? Segment(range: range(in: old, start: prefix, length: oldDiffLength))
            : .none
        let newSegment = newDiffLength > 0
            ? Segment(range: range(in: new, start: prefix, length: newDiffLength))
            : .none
        return (oldSegment, newSegment)
    }
}
