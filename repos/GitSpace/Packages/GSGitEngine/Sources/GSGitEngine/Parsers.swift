import Foundation

/// `git status --porcelain=v2 --branch -z` 解析器。
/// 冲突列表、未提交列表与 git 输出逐项一致（MRD 10.4-3 / 10.4-12 的解析侧保障）。
enum StatusParser {
    static func parse(_ data: Data, isMergeInProgress: Bool = false) -> RepoStatus {
        var status = RepoStatus(isMergeInProgress: isMergeInProgress)
        let tokens = data.split(separator: 0, omittingEmptySubsequences: true)
            .map { String(decoding: $0, as: UTF8.self) }

        var entries: [ChangeEntry] = []
        var i = 0
        while i < tokens.count {
            let token = tokens[i]
            if token.hasPrefix("# branch.oid ") {
                status.headSHA = String(token.dropFirst("# branch.oid ".count))
            } else if token.hasPrefix("# branch.head ") {
                let value = String(token.dropFirst("# branch.head ".count))
                if value == "(detached)" {
                    status.detached = true
                    status.branch = nil
                } else {
                    status.branch = value
                }
            } else if token.hasPrefix("# branch.upstream ") {
                status.upstream = String(token.dropFirst("# branch.upstream ".count))
            } else if token.hasPrefix("# branch.ab ") {
                let value = String(token.dropFirst("# branch.ab ".count))
                if let plus = value.firstIndex(of: "+") {
                    status.ahead = Int(value[value.index(after: plus)...].prefix(while: \.isNumber)) ?? 0
                }
                if let minus = value.firstIndex(of: "-") {
                    status.behind = Int(value[value.index(after: minus)...].prefix(while: \.isNumber)) ?? 0
                }
            } else if token.hasPrefix("1 ") {
                // 1 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <path>
                let parts = token.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: false)
                if parts.count == 9 {
                    let xy = String(parts[1])
                    let path = String(parts[8])
                    entries.append(ChangeEntry(
                        path: path,
                        indexKind: kind(xy.first),
                        worktreeKind: kind(xy.dropFirst().first)
                    ))
                }
            } else if token.hasPrefix("2 ") {
                // 2 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <X><score> <path><NUL><origPath>
                let parts = token.split(separator: " ", maxSplits: 9, omittingEmptySubsequences: false)
                if parts.count == 10, i + 1 < tokens.count {
                    let xy = String(parts[1])
                    let path = String(parts[9])
                    let originalPath = tokens[i + 1]
                    entries.append(ChangeEntry(
                        path: path,
                        originalPath: originalPath,
                        indexKind: kind(xy.first),
                        worktreeKind: kind(xy.dropFirst().first)
                    ))
                    i += 1
                }
            } else if token.hasPrefix("u ") {
                // u <XY> <sub> <m1> <m2> <m3> <mW> <h1> <h2> <h3> <path>
                let parts = token.split(separator: " ", maxSplits: 10, omittingEmptySubsequences: false)
                if parts.count == 11 {
                    let xy = String(parts[1])
                    let path = String(parts[10])
                    status.unmerged.append(UnmergedEntry(path: path, code: xy))
                }
            } else if token.hasPrefix("? ") {
                entries.append(ChangeEntry(path: String(token.dropFirst(2)), isUntracked: true))
            }
            // "! "（ignored）与其他未知记录跳过
            i += 1
        }

        status.staged = entries.filter { $0.indexKind != nil && $0.indexKind != .unmerged }
        status.unstaged = entries.filter { !$0.isUntracked && $0.worktreeKind != nil && $0.worktreeKind != .unmerged }
        status.untracked = entries.filter { $0.isUntracked }
        return status
    }

    private static func kind(_ character: Character?) -> FileChangeKind? {
        guard let character, character != ".", character != " " else { return nil }
        return FileChangeKind(rawValue: String(character).uppercased())
    }
}

/// `git log --pretty=format:` 自定义分隔符格式解析器。
enum CommitLogParser {
    static let fieldSeparator: Character = "\u{1f}"
    static let recordSeparator: Character = "\u{1e}"

    /// H, h, an, ae, at, ct, P, D(decorations), s, b
    public static let prettyFormat = "%H%x1f%h%x1f%an%x1f%ae%x1f%at%x1f%ct%x1f%P%x1f%D%x1f%s%x1f%b%x1e"

    static func parse(_ text: String) -> [CommitInfo] {
        var commits: [CommitInfo] = []
        for record in text.split(separator: recordSeparator, omittingEmptySubsequences: true) {
            var body = record[...]
            if body.hasPrefix("\n") { body = body.dropFirst() }
            let fields = body.split(separator: fieldSeparator, omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 10, !fields[0].isEmpty else { continue }
            let parents = fields[6].split(separator: " ").map(String.init)
            commits.append(CommitInfo(
                sha: fields[0],
                shortSHA: fields[1].isEmpty ? String(fields[0].prefix(7)) : fields[1],
                authorName: fields[2],
                authorEmail: fields[3],
                authorTimestamp: Int(fields[4]) ?? 0,
                committerTimestamp: Int(fields[5]) ?? 0,
                parents: parents,
                decorations: parseDecorations(fields[7]),
                subject: fields[8],
                body: fields[9]
            ))
        }
        return commits
    }

    /// "HEAD -> master, origin/master, tag: v1.0" → ["HEAD -> master", "origin/master", "tag: v1.0"]
    static func parseDecorations(_ raw: String) -> [String] {
        guard !raw.isEmpty else { return [] }
        return raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

/// `git for-each-ref --format=%00分隔` 解析器。
enum RefParser {
    static func parseRecords(_ text: String) -> [[String]] {
        text.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.split(separator: "\u{0}", omittingEmptySubsequences: false).map(String.init) }
    }

    static func parseLocalBranches(_ text: String) -> [BranchInfo] {
        parseRecords(text).compactMap { fields in
            guard fields.count >= 8, fields[0].hasPrefix("refs/heads/") else { return nil }
            let track = fields[5]
            var ahead = 0, behind = 0
            if let range = track.range(of: "ahead ") {
                ahead = Int(track[range.upperBound...].prefix(while: \.isNumber)) ?? 0
            }
            if let range = track.range(of: "behind ") {
                behind = Int(track[range.upperBound...].prefix(while: \.isNumber)) ?? 0
            }
            return BranchInfo(
                name: fields[1],
                fullName: fields[0],
                isCurrent: fields[6] == "*",
                upstream: fields[4].isEmpty ? nil : fields[4].replacingOccurrences(of: "refs/remotes/", with: ""),
                ahead: ahead,
                behind: behind,
                upstreamGone: track == "gone",
                headSHA: fields[2],
                subject: fields.count > 7 ? fields[7] : ""
            )
        }
    }

    static func parseRemoteBranches(_ text: String) -> [RemoteBranchInfo] {
        parseRecords(text).compactMap { fields in
            guard fields.count >= 6, fields[0].hasPrefix("refs/remotes/") else { return nil }
            let rest = String(fields[0].dropFirst("refs/remotes/".count))
            guard let slash = rest.firstIndex(of: "/") else { return nil }
            let remote = String(rest[..<slash])
            let branch = String(rest[rest.index(after: slash)...])
            if branch == "HEAD" { return nil }
            return RemoteBranchInfo(
                name: rest,
                fullName: fields[0],
                remoteName: remote,
                branchName: branch,
                headSHA: fields[2],
                subject: fields.count > 5 ? fields[5] : ""
            )
        }
    }

    static func parseTags(_ text: String) -> [TagInfo] {
        parseRecords(text).compactMap { fields in
            guard fields.count >= 6, fields[0].hasPrefix("refs/tags/") else { return nil }
            return TagInfo(
                name: String(fields[0].dropFirst("refs/tags/".count)),
                shortSHA: fields[1],
                dateText: fields[2],
                subject: fields[3],
                isAnnotated: fields[5] == "tag"
            )
        }
    }

    static func parseStashes(_ text: String) -> [StashInfo] {
        var result: [StashInfo] = []
        for record in text.split(separator: CommitLogParser.recordSeparator, omittingEmptySubsequences: true) {
            var body = record[...]
            if body.hasPrefix("\n") { body = body.dropFirst() }
            let fields = body.split(separator: CommitLogParser.fieldSeparator, omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 3 else { continue }
            guard let match = fields[0].firstMatch(of: /stash@\{(\d+)\}/) else { continue }
            let index = Int(match.1) ?? 0
            result.append(StashInfo(
                ref: fields[0],
                index: index,
                message: fields[2],
                timestamp: Date(timeIntervalSince1970: Double(Int(fields[1]) ?? 0))
            ))
        }
        return result
    }
}
