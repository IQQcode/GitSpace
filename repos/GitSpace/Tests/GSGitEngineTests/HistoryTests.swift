import Testing
import Foundation
import GSGitEngine
import GSTestSupport

/// 历史与 blame 能力（EP03-F03/F04、EP02-F04）：等价性基准 = git CLI 原始输出。
@Suite("History & Blame")
struct HistoryTests {

    // MARK: Blame

    @Test func blameMatchesPorcelainOutput() async throws {
        let repo = try FixtureRepo.make(prefix: "blame")
        try FixtureRepo.write(repo, "sample.txt", "alpha\nbeta\n")
        try FixtureRepo.commitAll(repo, "first")
        try FixtureRepo.write(repo, "sample.txt", "alpha\nbeta changed\n")
        try FixtureRepo.commitAll(repo, "second")

        let engine = FixtureRepo.engine(repo)
        let result = try await engine.blame(rev: "HEAD", path: "sample.txt")

        // 基准：直接解析 porcelain 输出得到 行号→sha
        let raw = try GitShell.run(repo, "blame", "--porcelain", "HEAD", "--", "sample.txt")
        let expected = Self.parsePorcelainLineMap(raw)
        #expect(result.lines.count == expected.count)
        for line in result.lines {
            #expect(line.sha == expected[line.lineNumber], "第 \(line.lineNumber) 行 sha 不一致")
            #expect(line.content == Self.parseContentMap(raw)[line.lineNumber])
        }
        // 元数据：两个提交都可查
        #expect(result.commits.count == 2)
        let first = try GitShell.run(repo, "rev-list", "--max-parents=0", "HEAD")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(result.commits[first]?.summary == "first")
        #expect(result.commits[first]?.authorName == "Tester")
    }

    @Test func blameWorktreeAttributesUncommittedToZeroSHA() async throws {
        let repo = try FixtureRepo.make(prefix: "blame-worktree")
        try FixtureRepo.write(repo, "a.txt", "committed\n")
        try FixtureRepo.commitAll(repo, "base")
        try FixtureRepo.write(repo, "a.txt", "committed\nuncommitted\n")

        let engine = FixtureRepo.engine(repo)
        let result = try await engine.blame(rev: nil, path: "a.txt")
        #expect(result.lines.count == 2)
        #expect(result.lines[1].sha == String(repeating: "0", count: 40))
    }

    /// porcelain 输出 → [行号: sha]（测试内基准解析）。
    private static func parsePorcelainLineMap(_ text: String) -> [Int: String] {
        var map: [Int: String] = [:]
        var currentSHA = ""
        var lineNumber = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("\t") {
                lineNumber += 1
                map[lineNumber] = currentSHA
            } else {
                let tokens = line.split(separator: " ")
                if tokens.count >= 3, tokens[0].count == 40,
                   Int(tokens[1]) != nil, Int(tokens[2]) != nil {
                    currentSHA = String(tokens[0])
                }
            }
        }
        return map
    }

    private static func parseContentMap(_ text: String) -> [Int: String] {
        var map: [Int: String] = [:]
        var lineNumber = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("\t") {
                lineNumber += 1
                map[lineNumber] = String(line.dropFirst())
            }
        }
        return map
    }

    // MARK: 文件历史（--follow）

    @Test func fileHistoryFollowsRename() async throws {
        let repo = try FixtureRepo.make(prefix: "follow")
        try FixtureRepo.write(repo, "old.txt", "v1\n")
        try FixtureRepo.commitAll(repo, "create old")
        try GitShell.run(repo, "mv", "old.txt", "new.txt")
        try FixtureRepo.commitAll(repo, "rename")
        try FixtureRepo.write(repo, "new.txt", "v1\nv2\n")
        try FixtureRepo.commitAll(repo, "edit new")

        let engine = FixtureRepo.engine(repo)
        let history = try await engine.fileHistory(path: "new.txt")

        let expected = try GitShell.run(repo, "log", "--follow", "--format=%H", "--", "new.txt")
            .split(separator: "\n").map(String.init)
        #expect(history.map(\.sha) == expected)
        #expect(history.count == 3) // 创建 + 重命名 + 修改
        #expect(history.map(\.subject) == ["edit new", "rename", "create old"])
    }

    @Test func fileChangeAtAndShowContentMatchGitShow() async throws {
        let repo = try FixtureRepo.make(prefix: "changeat")
        try FixtureRepo.write(repo, "a.txt", "one\n")
        try FixtureRepo.commitAll(repo, "first")
        let secondSHA = try GitShell.run(repo, "rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)
        try FixtureRepo.write(repo, "a.txt", "one\ntwo\n")
        try FixtureRepo.commitAll(repo, "second")
        let thirdSHA = try GitShell.run(repo, "rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)

        let engine = FixtureRepo.engine(repo)
        let diffs = try await engine.fileChangeAt(sha: thirdSHA, path: "a.txt")
        #expect(diffs.count == 1)
        #expect(diffs[0].hunks.count == 1)
        #expect(diffs[0].hunks[0].lines.contains { $0.origin == .add && $0.text == "two" })

        // showFileContent ≡ git show <rev>:<path>
        let content = try await engine.showFileContent(rev: secondSHA, path: "a.txt")
        let expected = try GitShell.run(repo, "show", "\(secondSHA):a.txt")
        #expect(content == expected)
        #expect(content == "one\n")
    }

    // MARK: 包含于

    @Test func refsContainingMatchesForEachRef() async throws {
        let repo = try FixtureRepo.make(prefix: "contains")
        try FixtureRepo.write(repo, "a.txt", "1\n")
        try FixtureRepo.commitAll(repo, "base")
        try GitShell.run(repo, "branch", "feature")
        try GitShell.run(repo, "tag", "v1.0")
        try FixtureRepo.write(repo, "a.txt", "2\n")
        try FixtureRepo.commitAll(repo, "ahead") // HEAD 不含在 feature/v1.0 上

        let engine = FixtureRepo.engine(repo)
        let baseSHA = try GitShell.run(repo, "rev-parse", "HEAD~").trimmingCharacters(in: .whitespacesAndNewlines)
        let headSHA = try GitShell.run(repo, "rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)

        let baseRefs = try await engine.refsContaining(sha: baseSHA)
        #expect(baseRefs.localBranches.contains("main"))
        #expect(baseRefs.localBranches.contains("feature"))
        #expect(baseRefs.tags == ["v1.0"])

        let headRefs = try await engine.refsContaining(sha: headSHA)
        #expect(headRefs.localBranches == ["main"])
        #expect(headRefs.tags.isEmpty)
    }

    // MARK: 配置与日志

    @Test func commitTemplateReadsConfigAndFile() async throws {
        let repo = try FixtureRepo.make(prefix: "template")
        try FixtureRepo.write(repo, "tpl.txt", "[Story-xxx] 标题\n\n正文\n")
        try GitShell.run(repo, "config", "commit.template", "tpl.txt")

        let engine = FixtureRepo.engine(repo)
        let template = try await engine.commitTemplate()
        #expect(template == "[Story-xxx] 标题\n\n正文\n")

        let none = try FixtureRepo.make(prefix: "template-none")
        // 本地置空，屏蔽全局 ~/.gitconfig 里可能存在的 commit.template
        try GitShell.run(none, "config", "commit.template", "")
        let engineNone = FixtureRepo.engine(none)
        #expect(try await engineNone.commitTemplate() == nil)
    }

    @Test func recentCommitSubjectsMatchesGitLog() async throws {
        let repo = try FixtureRepo.make(prefix: "subjects")
        for i in 1...3 {
            try FixtureRepo.write(repo, "f\(i).txt", "\(i)\n")
            try FixtureRepo.commitAll(repo, "commit \(i)")
        }
        let engine = FixtureRepo.engine(repo)
        let subjects = try await engine.recentCommitSubjects(limit: 20)
        #expect(subjects == ["commit 3", "commit 2", "commit 1"])
    }

    // MARK: 冲突三路 stage

    @Test func conflictStageContentsMatchGitShow() async throws {
        let (_, engine) = try FixtureRepo.makeConflictRepo()
        _ = try? await engine.merge(ref: "feature", style: .auto)
        let status = try await engine.status()
        #expect(!status.unmerged.isEmpty)

        let stages = try await engine.conflictStageContents(path: "conflict.txt")
        #expect(stages.base == "shared line\nmain only\n")
        #expect(stages.ours == "main changed the shared line\nmain only\n")
        #expect(stages.theirs == "feature changed the shared line\nmain only\n")
    }
}

/// 词级差异（EP03-F02）与解析器扩展的单元断言。
@Suite("WordDiff & Parsers")
struct WordDiffAndParserTests {

    @Test func wordDiffTrimsCommonPrefixAndSuffix() {
        let oldText = "let value = computeA()"
        let newText = "let value = computeB()"
        let (oldSeg, newSeg) = WordDiff.segments(old: oldText, new: newText)
        // 差异区间应只覆盖 A/B
        #expect(String(oldText[oldSeg.range!]) == "A")
        #expect(String(newText[newSeg.range!]) == "B")
    }

    @Test func wordDiffSkipsWholeLineChanges() {
        // 整行新增（old 为空）不做词级高亮
        #expect(WordDiff.segments(old: "", new: "new line").old.range == nil)
        #expect(WordDiff.segments(old: "", new: "new line").new.range == nil)
        // 完全相同
        #expect(WordDiff.segments(old: "same", new: "same").old.range == nil)
    }

    @Test func wordDiffHandlesChineseCharacters() {
        let oldText = "修复入口缺陷"
        let newText = "修复出口缺陷"
        let (oldSeg, newSeg) = WordDiff.segments(old: oldText, new: newText)
        #expect(String(oldText[oldSeg.range!]) == "入")
        #expect(String(newText[newSeg.range!]) == "出")
    }

    @Test func diffParserAssignsLineNumbers() async throws {
        let (repo, _) = try FixtureRepo.makeMultiHunkRepo()
        let files = DiffParser.parse(try GitShell.run(repo, "diff", "--no-color"))
        let firstHunk = files[0].hunks[0]
        // hunk 1 改第 2 行，上下文 3 行 → hunk 从第 1 行开始（@@ -1,7 +1,7 @@）
        #expect(firstHunk.header.hasPrefix("@@ -1,"))
        let del = firstHunk.lines.first { $0.origin == .del }
        let add = firstHunk.lines.first { $0.origin == .add }
        let contexts = firstHunk.lines.filter { $0.origin == .context }
        #expect(del?.oldNumber == 2)
        #expect(del?.newNumber == nil)
        #expect(add?.newNumber == 2)
        #expect(add?.oldNumber == nil)
        // 改动前的 context 在第 1 行，改动后的 context 从第 3 行顺延
        #expect(contexts.first?.oldNumber == 1)
        #expect(contexts.first?.newNumber == 1)
        #expect(contexts[1].oldNumber == 3)
        #expect(contexts[1].newNumber == 3)
    }

    @Test func commitLogParserExtractsCommitterFields() async throws {
        let repo = try FixtureRepo.make(prefix: "committer")
        try FixtureRepo.write(repo, "a.txt", "1\n")
        try FixtureRepo.commitAll(repo, "c1")
        let engine = FixtureRepo.engine(repo)
        let commits = try await engine.commits(limit: 10, since: nil)
        #expect(commits.count == 1)
        #expect(commits[0].committerName == "Tester")
        #expect(commits[0].committerEmail == "tester@example.com")
        #expect(!commits[0].hasDistinctCommitter)
    }
}
