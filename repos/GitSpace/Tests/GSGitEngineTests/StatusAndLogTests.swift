import Testing
import Foundation
import GSGitEngine
import GSTestSupport

/// 状态与提交历史：引擎输出必须与 git CLI 基准逐项一致（MRD 10.4-3）。
@Suite("Status & Log")
struct StatusAndLogTests {
    @Test func statusMatchesPorcelainV2() async throws {
        let repo = try FixtureRepo.make(prefix: "status")
        try FixtureRepo.write(repo, "a.txt", "one\n")
        try FixtureRepo.commitAll(repo, "first")
        try FixtureRepo.write(repo, "a.txt", "one\ntwo\n")
        try FixtureRepo.write(repo, "b.txt", "new file\n")
        try GitShell.run(repo, "mv", "a.txt", "a-renamed.txt")

        let engine = FixtureRepo.engine(repo)
        let status = try await engine.status()

        #expect(status.branch == "main")
        #expect(status.ahead == 0 && status.behind == 0)
        #expect(status.staged.count == 1) // rename 已进 index
        #expect(status.unstaged.contains { $0.path == "a-renamed.txt" })
        #expect(status.untracked.map(\.path) == ["b.txt"])

        // 与 git 原始 porcelain 记录逐项比对
        let raw = try GitShell.run(repo, "status", "--porcelain=v2", "--untracked-files=all", "-z")
        let records = raw.split(separator: Character("\u{0}"), omittingEmptySubsequences: true).map(String.init)
        let untrackedFromGit = records.filter { $0.hasPrefix("? ") }.map { String($0.dropFirst(2)) }.sorted()
        #expect(status.untracked.map(\.path).sorted() == untrackedFromGit)
    }

    @Test func branchAheadBehindFromUpstream() async throws {
        let repo = try FixtureRepo.make(prefix: "ahead")
        try FixtureRepo.write(repo, "a.txt", "one\n")
        try FixtureRepo.commitAll(repo, "first")

        let remoteURL = repo.deletingLastPathComponent().appendingPathComponent("origin.git")
        try GitShell.run(repo, "clone", "--bare", repo.path, remoteURL.path)
        try GitShell.run(repo, "remote", "add", "origin", remoteURL.path)
        try GitShell.run(repo, "push", "-u", "origin", "main")
        try FixtureRepo.write(repo, "a.txt", "one\ntwo\n")
        try FixtureRepo.commitAll(repo, "second")
        try GitShell.run(repo, "fetch", "origin")

        let engine = FixtureRepo.engine(repo)
        let status = try await engine.status()
        #expect(status.upstream == "origin/main")
        #expect(status.ahead == 1)
        #expect(status.behind == 0)
    }

    @Test func commitLogOrderAndFields() async throws {
        let repo = try FixtureRepo.make(prefix: "log")
        try FixtureRepo.write(repo, "a.txt", "1\n")
        try FixtureRepo.commitAll(repo, "commit one")
        try FixtureRepo.write(repo, "a.txt", "1\n2\n")
        try FixtureRepo.commitAll(repo, "commit two")
        try GitShell.run(repo, "branch", "feature/x")

        let engine = FixtureRepo.engine(repo)
        let commits = try await engine.commits(limit: 10, since: nil)
        #expect(commits.count == 2)
        #expect(commits[0].subject == "commit two")
        #expect(commits[1].subject == "commit one")
        #expect(commits[1].sha.count == 40)
        #expect(commits[1].authorEmail == "tester@example.com")
        #expect(!commits[1].isMerge)
        // --all 后装饰里应能看到 feature/x
        #expect(commits.contains { $0.decorations.contains("feature/x") })
    }

    @Test func mergeCommitMarkedAsMerge() async throws {
        let repo = try FixtureRepo.make(prefix: "merge")
        try FixtureRepo.write(repo, "base.txt", "base\n")
        try FixtureRepo.commitAll(repo, "base")
        try GitShell.run(repo, "checkout", "-b", "feature")
        try FixtureRepo.write(repo, "f.txt", "f\n")
        try FixtureRepo.commitAll(repo, "feature commit")
        try GitShell.run(repo, "checkout", "main")

        let engine = FixtureRepo.engine(repo)
        let outcome = try await engine.merge(ref: "feature", style: .noFastForward)
        guard case .merged = outcome else {
            Issue.record("预期生成合并提交，实际 \(outcome)")
            return
        }
        let commits = try await engine.commits(limit: 10, since: nil)
        #expect(commits.first?.isMerge == true)
        #expect(commits.first?.parents.count == 2)
    }
}
