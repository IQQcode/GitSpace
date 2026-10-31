import Testing
import Foundation
import GSGitEngine
import GSTestSupport

/// 丢弃补齐与写操作（EP04-F01、EP02-F03、EP07-F01/F05）：等价性基准 = git CLI。
@Suite("Discard & History Writes")
struct DiscardAndSyncTests {

    // MARK: 块级丢弃（EP04-F01）

    @Test func discardHunksRevertsOnlySelectedHunks() async throws {
        let (repo, engine) = try FixtureRepo.makeMultiHunkRepo()
        // 丢弃 hunk 0 与 2，保留 hunk 1：文件内容 = 基线 + 仅第 10 行修改
        let worktreeDiff = DiffParser.parse(try GitShell.run(repo, "diff", "--no-color"))
        let file = worktreeDiff[0]

        try await engine.discardHunks(of: file, hunkIDs: [0, 2])

        let content = try FixtureRepo.read(repo, "sample.txt")
        var expected = (1...20).map { "line \($0)" }
        expected[9] = "line 10 modified"
        #expect(content == expected.joined(separator: "\n") + "\n")

        // 剩余 diff 只含 hunk 1
        let remaining = DiffParser.parse(try GitShell.run(repo, "diff", "--no-color"))
        #expect(remaining.count == 1)
        #expect(remaining[0].hunks.count == 1)
        #expect(remaining[0].hunks[0].patchText() == file.hunks[1].patchText())
    }

    // MARK: 快照撤销（EP04-F01）

    @Test func discardThenUndoRestoresContent() async throws {
        let repo = try FixtureRepo.make(prefix: "undo")
        try FixtureRepo.write(repo, "a.txt", "base\n")
        try FixtureRepo.commitAll(repo, "base")
        try FixtureRepo.write(repo, "a.txt", "base\nchanged\n")
        // 丢弃前的工作区内容（含改动）——快照应捕获它
        let beforeDiscard = try FixtureRepo.read(repo, "a.txt")

        let engine = FixtureRepo.engine(repo)
        // 丢弃前快照
        let snapshot = try await engine.stashCreate(message: "GitSpace 丢弃快照")
        #expect(snapshot != nil)
        // 丢弃
        try await engine.discard(.worktree(path: "a.txt"))
        #expect(try FixtureRepo.read(repo, "a.txt") == "base\n")
        // 撤销：文件内容哈希与丢弃前一致（改动被找回）
        try await engine.restoreFromSnapshot(sha: snapshot!, paths: ["a.txt"])
        #expect(try FixtureRepo.read(repo, "a.txt") == beforeDiscard)
        #expect(try FixtureRepo.read(repo, "a.txt") == "base\nchanged\n")
    }

    @Test func stashCreateReturnsNilWhenNothingToSnapshot() async throws {
        let repo = try FixtureRepo.make(prefix: "snapshot-empty")
        try FixtureRepo.write(repo, "a.txt", "base\n")
        try FixtureRepo.commitAll(repo, "base")
        // 纯未跟踪改动：stash create 不覆盖，返回空
        try FixtureRepo.write(repo, "untracked.txt", "new\n")

        let engine = FixtureRepo.engine(repo)
        let snapshot = try await engine.stashCreate(message: "x")
        #expect(snapshot == nil)
    }

    @Test func discardUntrackedMovesFileToTrash() async throws {
        let repo = try FixtureRepo.make(prefix: "trash")
        try FixtureRepo.write(repo, "a.txt", "base\n")
        try FixtureRepo.commitAll(repo, "base")
        let target = repo.appendingPathComponent("untracked.txt")
        try "temp\n".write(to: target, atomically: true, encoding: .utf8)

        let engine = FixtureRepo.engine(repo)
        try await engine.discard(.untracked(path: "untracked.txt"))
        #expect(!FileManager.default.fileExists(atPath: target.path))
    }

    // MARK: 检出提交（EP02-F03）

    @Test func checkoutDetachedEntersDetachedHEADAndRejectsDirty() async throws {
        let repo = try FixtureRepo.make(prefix: "detach")
        try FixtureRepo.write(repo, "a.txt", "1\n")
        try FixtureRepo.commitAll(repo, "c1")
        let firstSHA = try GitShell.run(repo, "rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)
        try FixtureRepo.write(repo, "a.txt", "2\n")
        try FixtureRepo.commitAll(repo, "c2")

        let engine = FixtureRepo.engine(repo)
        try await engine.checkoutDetached(sha: firstSHA)
        let status = try await engine.status()
        #expect(status.detached)
        #expect(status.headSHA == firstSHA)

        // 脏区拒绝
        try GitShell.run(repo, "checkout", "main")
        try FixtureRepo.write(repo, "a.txt", "dirty\n")
        await #expect(throws: GitError.self) {
            try await engine.checkoutDetached(sha: firstSHA)
        }
    }

    // MARK: 合并信息（EP07-F01）

    @Test func mergeWithCustomMessageWritesMergeCommitMessage() async throws {
        let repo = try FixtureRepo.make(prefix: "merge-msg")
        try FixtureRepo.write(repo, "a.txt", "base\n")
        try FixtureRepo.commitAll(repo, "base")
        try GitShell.run(repo, "checkout", "-b", "feature")
        try FixtureRepo.write(repo, "feature.txt", "feature\n")
        try FixtureRepo.commitAll(repo, "feature work")
        try GitShell.run(repo, "checkout", "main")
        try FixtureRepo.write(repo, "main.txt", "main\n")
        try FixtureRepo.commitAll(repo, "main work")

        let engine = FixtureRepo.engine(repo)
        let outcome = try await engine.merge(ref: "feature", style: .noFastForward, message: "自定义合并信息")
        guard case .merged = outcome else {
            Issue.record("应产生合并提交，实际 \(outcome)")
            return
        }
        let message = try GitShell.run(repo, "log", "-1", "--format=%B")
        #expect(message.trimmingCharacters(in: .whitespacesAndNewlines) == "自定义合并信息")
    }

    @Test func mergeWithoutMessageKeepsDefaultSubject() async throws {
        let repo = try FixtureRepo.make(prefix: "merge-default")
        try FixtureRepo.write(repo, "a.txt", "base\n")
        try FixtureRepo.commitAll(repo, "base")
        try GitShell.run(repo, "checkout", "-b", "feature")
        try FixtureRepo.write(repo, "feature.txt", "feature\n")
        try FixtureRepo.commitAll(repo, "feature work")
        try GitShell.run(repo, "checkout", "main")

        let engine = FixtureRepo.engine(repo)
        _ = try await engine.merge(ref: "feature", style: .noFastForward)
        let subject = try GitShell.run(repo, "log", "-1", "--format=%s")
        #expect(subject.contains("Merge branch 'feature'"))
    }

    // MARK: Tag 推送（EP07-F05，本地 bare origin）

    @Test func pushTagAndDeleteRemoteTagRoundtrip() async throws {
        let repo = try FixtureRepo.make(prefix: "tagpush")
        try FixtureRepo.write(repo, "a.txt", "1\n")
        try FixtureRepo.commitAll(repo, "base")
        try GitShell.run(repo, "tag", "-a", "v1.0.0", "-m", "release 1")

        // 本地 bare 仓作为 origin
        let bareURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitspace-tests/origin-\(UUID().uuidString).git")
        try GitShell.run(bareURL.deletingLastPathComponent(), "init", "--bare", bareURL.path)
        try GitShell.run(repo, "remote", "add", "origin", bareURL.path)

        let engine = FixtureRepo.engine(repo)
        try await engine.pushTag(name: "v1.0.0")
        let listed = try GitShell.run(repo, "ls-remote", "--tags", "origin")
        #expect(listed.contains("refs/tags/v1.0.0"))

        try await engine.deleteRemoteTag(name: "v1.0.0")
        let listedAfter = try GitShell.run(repo, "ls-remote", "--tags", "origin")
        #expect(!listedAfter.contains("refs/tags/v1.0.0"))
    }
}
