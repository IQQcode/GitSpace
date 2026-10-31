import Foundation

// MARK: - 历史与 blame（EP03-F03 / F04、EP02-F04）
// 只读命令：数据一律来自 git CLI 输出，解析失败不猜（TechStack §10-3）。

extension GitRepository {
    /// blame（EP03-F03）：rev 为 nil 时 blame 工作区内容。
    /// 每行归属与 `git blame --porcelain <rev> -- <path>` 一致。
    public func blame(rev: String?, path: String) async throws -> BlameResult {
        var arguments = ["blame", "--porcelain"]
        if let rev, !rev.isEmpty { arguments.append(rev) }
        arguments += ["--", path]
        let output = try await runner.run(directory: root, arguments: arguments, options: .quick)
        return BlameParser.parse(output.stdout)
    }

    /// 文件历史（EP03-F04）：--follow 识别重命名，重命名前的历史也在内。
    public func fileHistory(path: String, limit: Int = 200) async throws -> [CommitInfo] {
        let arguments = [
            "log", "--follow", "--no-color", "--date-order",
            "-n", String(limit),
            "--pretty=format:\(CommitLogParser.prettyFormat)",
            "--", path
        ]
        let output = try await runner.run(directory: root, arguments: arguments, options: .quick)
        return CommitLogParser.parse(output.stdout)
    }

    /// 某提交对该文件的改动（EP03-F04 右栏 diff）。
    public func fileChangeAt(sha: String, path: String) async throws -> [FileDiff] {
        let arguments = ["show", "--format=", "--no-color", "-M", sha, "--", path]
        let output = try await runner.run(directory: root, arguments: arguments, options: .quick)
        return DiffParser.parse(output.stdout)
    }

    /// 读取某版本文件内容（`git show <rev>:<path>`）。
    public func showFileContent(rev: String, path: String) async throws -> String {
        let output = try await runner.run(
            directory: root,
            arguments: ["show", "\(rev):\(path)"],
            options: .quick
        )
        return output.stdout
    }

    /// 工作区与某版本的指定文件 diff（「与当前版本比较」）。
    public func diffAgainstRevision(rev: String, path: String) async throws -> [FileDiff] {
        let output = try await runner.run(
            directory: root,
            arguments: ["diff", "--no-color", rev, "--", path],
            options: .quick
        )
        return DiffParser.parse(output.stdout)
    }

    /// 「包含于」（EP02-F04）：`git for-each-ref --contains` 一次取全部分支与 tag。
    public func refsContaining(sha: String) async throws -> ContainsRefs {
        let output = try await runner.run(
            directory: root,
            arguments: ["for-each-ref", "--contains", sha, "--format=%(refname)"],
            options: .quick
        )
        var locals: [String] = []
        var remotes: [String] = []
        var tagNames: [String] = []
        for line in output.stdout.split(separator: "\n", omittingEmptySubsequences: true) {
            let refname = String(line)
            if refname.hasPrefix("refs/heads/") {
                locals.append(String(refname.dropFirst("refs/heads/".count)))
            } else if refname.hasPrefix("refs/remotes/") {
                let short = String(refname.dropFirst("refs/remotes/".count))
                if short != "HEAD" { remotes.append(short) }
            } else if refname.hasPrefix("refs/tags/") {
                tagNames.append(String(refname.dropFirst("refs/tags/".count)))
            }
        }
        return ContainsRefs(localBranches: locals, remoteBranches: remotes, tags: tagNames)
    }

    /// 本仓最近 N 条提交标题（EP04-F02 历史下拉）。
    public func recentCommitSubjects(limit: Int = 20) async throws -> [String] {
        let output = try await runner.run(
            directory: root,
            arguments: ["log", "-n", String(limit), "--format=%s"],
            options: .quick
        )
        return output.stdout
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
    }

    /// 读取 `git config commit.template`（EP04-F02）；相对路径按仓根解析。
    public func commitTemplate() async throws -> String? {
        let output = try await runner.runRaw(
            directory: root,
            arguments: ["config", "--get", "commit.template"],
            options: .quick
        )
        guard output.succeeded else { return nil }
        let configured = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !configured.isEmpty else { return nil }
        let url = configured.hasPrefix("/")
            ? URL(fileURLWithPath: configured)
            : root.appendingPathComponent(configured)
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// 冲突文件的三路 stage 内容（EP07-F02 外部工具 / EP07-F03 两者都保留共用）。
    /// 单侧新增的文件缺少对应 stage，返回 nil。
    public func conflictStageContents(path: String) async throws -> (base: String?, ours: String?, theirs: String?) {
        func stage(_ number: Int) async -> String? {
            guard
                let output = try? await runner.runRaw(
                    directory: root,
                    arguments: ["show", ":\(number):\(path)"],
                    options: .quick
                ),
                output.succeeded
            else { return nil }
            return output.stdout
        }
        return (await stage(1), await stage(2), await stage(3))
    }
}

/// `git blame --porcelain` 输出解析器。
/// 格式：每行输出 `<40位sha> <orig> <final> [count]`，提交元数据头只在首次出现时跟随，
/// 内容行以 `\t` 开头。同一提交的连续行合并为区段（isGroupStart）。
enum BlameParser {
    static func parse(_ text: String) -> BlameResult {
        var commits: [String: BlameCommitInfo] = [:]
        var lines: [BlameLine] = []
        var currentSHA: String?
        var currentBoundary = false
        var pendingMetadata: [String: String] = [:]

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.hasPrefix("\t") {
                guard let sha = currentSHA else { continue }
                let isGroupStart = !(lines.last?.sha == sha)
                let lineNumber = lines.count + 1
                lines.append(BlameLine(
                    lineNumber: lineNumber,
                    content: String(line.dropFirst()),
                    sha: sha,
                    isGroupStart: isGroupStart
                ))
                continue
            }

            let tokens = line.split(separator: " ", omittingEmptySubsequences: true)
            if tokens.count >= 3, tokens[0].count == 40, tokens[0].allSatisfy(\.isHexDigit),
               Int(tokens[1]) != nil, Int(tokens[2]) != nil {
                // 新的一行记录：先落盘上一条提交元数据
                if let sha = currentSHA, commits[sha] == nil {
                    commits[sha] = makeCommitInfo(sha: sha, metadata: pendingMetadata, isBoundary: currentBoundary)
                }
                currentSHA = String(tokens[0])
                // 若该 sha 已有元数据（后续行复用），重置 pending 供可能的新头使用
                currentBoundary = false
                pendingMetadata = [:]
                continue
            }

            // 提交元数据头：`<key> [value]`，boundary 无值
            let spaceIndex = line.firstIndex(of: " ")
            let key = spaceIndex.map { String(line[..<$0]) } ?? line
            let value = spaceIndex.map { String(line[line.index(after: $0)...]) } ?? ""
            pendingMetadata[key] = value
            if key == "boundary" { currentBoundary = true }
        }
        if let sha = currentSHA, commits[sha] == nil {
            commits[sha] = makeCommitInfo(sha: sha, metadata: pendingMetadata, isBoundary: currentBoundary)
        }
        return BlameResult(lines: lines, commits: commits)
    }

    private static func makeCommitInfo(sha: String, metadata: [String: String], isBoundary: Bool) -> BlameCommitInfo {
        BlameCommitInfo(
            sha: sha,
            shortSHA: String(sha.prefix(7)),
            authorName: metadata["author"] ?? "",
            authorTimestamp: Int(metadata["author-time"] ?? "") ?? 0,
            summary: metadata["summary"] ?? "",
            isBoundary: isBoundary
        )
    }
}
