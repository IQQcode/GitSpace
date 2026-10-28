import Foundation

/// unified diff 解析器：以 `diff --git` / `--- / +++` 头定位，不依赖行内容猜测（TechStack §5.3）。
/// 输出保留原始行，供 hunk 暂存管线逐字重组 patch。
public enum DiffParser {
    public static func parse(_ text: String) -> [FileDiff] {
        guard !text.isEmpty else { return [] }

        var files: [FileDiff] = []
        var headerLines: [String] = []
        var currentPath = ""
        var currentOriginalPath: String?
        var currentKind: FileChangeKind = .modified
        var isBinary = false
        var hunks: [DiffHunk] = []
        var hunkHeader: String?
        var hunkLines: [DiffLine] = []

        func closeHunk() {
            if let header = hunkHeader {
                hunks.append(DiffHunk(id: hunks.count, header: header, lines: hunkLines))
            }
            hunkHeader = nil
            hunkLines = []
        }

        func closeFile() {
            closeHunk()
            guard !currentPath.isEmpty else { return }
            files.append(FileDiff(
                path: currentPath,
                originalPath: currentOriginalPath,
                kind: currentKind,
                headerLines: headerLines,
                hunks: hunks,
                isBinary: isBinary
            ))
            headerLines = []
            currentPath = ""
            currentOriginalPath = nil
            currentKind = .modified
            isBinary = false
            hunks = []
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)

            if line.hasPrefix("diff --git ") {
                closeFile()
                let (old, new) = parsePaths(line)
                currentOriginalPath = old != new ? old : nil
                currentPath = new
                headerLines = [line]
                continue
            }

            if line.hasPrefix("@@") {
                closeHunk()
                hunkHeader = line
                continue
            }

            if hunkHeader != nil {
                // hunk 体内只接受四类合法行
                switch line.first {
                case "+", "-", " ", "\\":
                    hunkLines.append(DiffLine(raw: line))
                default:
                    break // 未知行忽略，绝不猜
                }
                continue
            }

            // 文件头区域
            if line.hasPrefix("new file mode") {
                currentKind = .added
            } else if line.hasPrefix("deleted file mode") {
                currentKind = .deleted
            } else if line.hasPrefix("rename from ") {
                currentKind = .renamed
                currentOriginalPath = String(line.dropFirst("rename from ".count))
            } else if line.hasPrefix("rename to ") {
                currentPath = String(line.dropFirst("rename to ".count))
            } else if line.hasPrefix("Binary files") {
                isBinary = true
            }
            if !currentPath.isEmpty {
                headerLines.append(line)
            }
        }
        closeFile()
        return files
    }

    /// "diff --git a/x b/x" → (x, x)；带引号与空格路径做尽力解析。
    static func parsePaths(_ line: String) -> (old: String, new: String) {
        let body = line.dropFirst("diff --git ".count)
        guard let bRange = body.range(of: " b/") else {
            let fallback = String(body).replacingOccurrences(of: "\"", with: "")
            return (fallback, fallback)
        }
        var old = String(body[body.index(body.startIndex, offsetBy: 2)..<bRange.lowerBound])
        var new = String(body[bRange.upperBound...])
        old = old.replacingOccurrences(of: "\"", with: "")
        new = new.replacingOccurrences(of: "\"", with: "")
        return (old, new)
    }
}
