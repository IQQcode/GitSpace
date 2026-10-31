import Testing
import Foundation
import GSGitEngine
import GSInfra
import GSTestSupport

/// bisect / cherry-pick / revert 等价性（Story-1031-mcp：基准 = 手工 git CLI）。
@Suite("VCS: Bisect & Pick")
struct VCSTests {
    /// 10 个提交的线性链；第 7 个提交注入 bug（feature.txt 含 buggy 行），其余提交只加无关文件。
    /// 返回按提交顺序排列的 SHA（c1…c10）。
    private func makeLinearRepo() throws -> (repo: URL, engine: GitRepository, shas: [String]) {
        let repo = try FixtureRepo.make(prefix: "vcs")
        try FixtureRepo.write(repo, "stable.txt", "stable\n")
        try FixtureRepo.commitAll(repo, "c1")
        var shas = [try GitShell.run(repo, "rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)]
        for i in 2...10 {
            try FixtureRepo.write(repo, "noise\(i).txt", "noise \(i)\n")
            if i == 7 {
                try FixtureRepo.write(repo, "feature.txt", "buggy line\n")
            }
            try FixtureRepo.commitAll(repo, "c\(i)")
            shas.append(try GitShell.run(repo, "rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return (repo, FixtureRepo.engine(repo), shas)
    }

    @Test func bisectLocatesFirstBadCommitAndResetRestoresHead() async throws {
        let (repo, engine, shas) = try makeLinearRepo()
        let headBefore = try await engine.currentSHA()

        _ = try await engine.bisectStart(bad: shas[9], good: shas[0])
        var log = try await engine.bisectLog()
        var rounds = 0
        while !log.contains("first bad commit") {
            rounds += 1
            #expect(rounds <= 10, "二分迭代超出预期轮数")
            if rounds > 10 { break }
            // bisect 检出中间提交后按 feature.txt 内容判好坏（与人工流程一致）
            let isBad = (try? FixtureRepo.read(repo, "feature.txt"))?.contains("buggy") == true
            log = try await engine.bisectMark(isBad ? .bad : .good)
        }

        #expect(log.contains(shas[6]), "bisect log 应指向 c7 的 SHA")
        try await engine.bisectReset()
        #expect(try await engine.currentSHA() == headBefore, "reset 后 HEAD 应回到二分前位置")
    }

    @Test func bisectStartRejectsDirtyWorktree() async throws {
        let (repo, engine, shas) = try makeLinearRepo()
        let headBefore = try await engine.currentSHA()
        try FixtureRepo.write(repo, "dirty.txt", "uncommitted\n")

        await #expect(throws: GitError.self) {
            _ = try await engine.bisectStart(bad: shas[9], good: shas[0])
        }
        #expect(try await engine.currentSHA() == headBefore)
    }

    @Test func cherryPickAppliesCommitWithCliEquivalence() async throws {
        let repo = try FixtureRepo.make(prefix: "pick")
        try FixtureRepo.write(repo, "a.txt", "base\n")
        try FixtureRepo.commitAll(repo, "base")
        try GitShell.run(repo, "checkout", "-b", "feature")
        try FixtureRepo.write(repo, "feature.txt", "picked content\n")
        try FixtureRepo.commitAll(repo, "feat: add feature")
        let featureSHA = try GitShell.run(repo, "rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)
        try GitShell.run(repo, "checkout", "main")

        let engine = FixtureRepo.engine(repo)
        let outcome = try await engine.cherryPick(sha: featureSHA)

        guard case .merged(let newSHA) = outcome else {
            Issue.record("cherry-pick 应成功，实际 \(outcome)")
            return
        }
        // 与 CLI 基准等价：文件内容与提交标题一致
        #expect(try FixtureRepo.read(repo, "feature.txt") == "picked content\n")
        let subject = try GitShell.run(repo, "log", "--format=%s", "-1").trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(subject == "feat: add feature")
        let engineHead = try await engine.currentSHA()
        #expect(newSHA == engineHead)
    }

    @Test func cherryPickConflictReturnsConflictsAndAbortRestores() async throws {
        let (repo, engine) = try FixtureRepo.makeConflictRepo()
        // makeConflictRepo 停在 main；摘取 feature 上的冲突提交
        let featureTip = try GitShell.run(repo, "rev-parse", "feature").trimmingCharacters(in: .whitespacesAndNewlines)
        let headBefore = try await engine.currentSHA()

        let outcome = try await engine.cherryPick(sha: featureTip)
        guard case .conflicts(let entries) = outcome else {
            Issue.record("应返回冲突，实际 \(outcome)")
            return
        }
        #expect(!entries.isEmpty)

        try await engine.abortPick()
        #expect(try await engine.currentSHA() == headBefore, "abort 后 HEAD 应回到摘取前")
        #expect(try await engine.status().isClean)
    }

    @Test func revertCreatesReverseCommit() async throws {
        let repo = try FixtureRepo.make(prefix: "revert")
        try FixtureRepo.write(repo, "a.txt", "one\n")
        try FixtureRepo.commitAll(repo, "first")
        try FixtureRepo.write(repo, "b.txt", "two\n")
        try FixtureRepo.commitAll(repo, "second")
        let secondSHA = try GitShell.run(repo, "rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)

        let engine = FixtureRepo.engine(repo)
        let headBefore = try await engine.currentSHA()
        let outcome = try await engine.revert(sha: secondSHA)

        guard case .merged(let newSHA) = outcome else {
            Issue.record("revert 应成功，实际 \(outcome)")
            return
        }
        // 提交数 +1、父提交为 revert 前 HEAD、被撤销的文件消失（与 CLI 等价）
        let log = try await engine.commits(limit: 5, since: nil)
        #expect(log.count == 3)
        #expect(log[0].sha == newSHA)
        #expect(log[0].parents.first == headBefore)
        #expect(log[0].subject == "Revert \"second\"")
        #expect(!FileManager.default.fileExists(atPath: repo.appendingPathComponent("b.txt").path))
    }

    @Test func writesAreRecordedInOperationLog() async throws {
        let repo = try FixtureRepo.make(prefix: "vcslog")
        try FixtureRepo.write(repo, "a.txt", "one\n")
        try FixtureRepo.commitAll(repo, "first")
        try FixtureRepo.write(repo, "b.txt", "two\n")
        try FixtureRepo.commitAll(repo, "second")
        let secondSHA = try GitShell.run(repo, "rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)
        let firstSHA = try GitShell.run(repo, "rev-parse", "HEAD~1").trimmingCharacters(in: .whitespacesAndNewlines)

        let logDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitspace-opslog-\(UUID().uuidString)", isDirectory: true)
        let logger = OperationLog(directory: logDir)
        guard let engine = GitRepository(path: repo, operationLogger: logger) else {
            Issue.record("fixture 仓初始化失败")
            return
        }

        // 顺序敏感：bisect 需要干净区，pick -n 会留下暂存改动，故 bisect 在前
        _ = try await engine.bisectStart(bad: nil, good: firstSHA)
        _ = try await engine.bisectMark(.bad)
        try await engine.bisectReset()

        _ = try await engine.revert(sha: secondSHA)
        // revert 已撤销 b.txt，摘回 secondSHA 是非空摘取；-n 成功后改动留在暂存区（无需 abort）
        _ = try await engine.cherryPick(sha: secondSHA, noCommit: true)

        let entries = await logger.recentEntries()
        for action in ["revert", "cherry-pick", "bisect.start", "bisect.mark", "bisect.reset"] {
            #expect(entries.contains { $0.action == action && $0.result == "success" }, "缺少 \(action) 的成功留痕")
        }
    }
}
