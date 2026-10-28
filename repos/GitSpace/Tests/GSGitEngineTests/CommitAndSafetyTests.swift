import Testing
import Foundation
import GSGitEngine
import GSTestSupport

/// 提交链路（MRD 10.4-10）与安全闸（MRD 10.2-G / 10.4-4）。
@Suite("Commit & Safety")
struct CommitAndSafetyTests {
    @Test func commitAdvancesHeadOnce() async throws {
        let repo = try FixtureRepo.make(prefix: "commit")
        try FixtureRepo.write(repo, "a.txt", "one\n")
        try FixtureRepo.commitAll(repo, "base")

        let engine = FixtureRepo.engine(repo)
        let headBefore = try await engine.currentSHA()
        try await engine.stageFiles(["a.txt"])
        try FixtureRepo.write(repo, "b.txt", "new\n")
        try await engine.stageFiles(["b.txt"])
        let sha = try await engine.commit(message: "feat: add b\n\n详细描述", amend: false)

        #expect(sha != headBefore)
        let status = try await engine.status()
        #expect(status.isClean)
        let log = try await engine.commits(limit: 5, since: nil)
        #expect(log.first?.subject == "feat: add b")
        #expect(log.first?.body.contains("详细描述") == true)
    }

    @Test func amendKeepsParentUnchanged() async throws {
        let repo = try FixtureRepo.make(prefix: "amend")
        try FixtureRepo.write(repo, "a.txt", "one\n")
        try FixtureRepo.commitAll(repo, "base")
        try FixtureRepo.write(repo, "b.txt", "b\n")
        try FixtureRepo.commitAll(repo, "to amend")

        let engine = FixtureRepo.engine(repo)
        let log = try await engine.commits(limit: 5, since: nil)
        let grandparent = log[1].sha
        let originalParent = log[0].sha

        try FixtureRepo.write(repo, "c.txt", "c\n")
        try await engine.stageFiles(["c.txt"])
        let newSHA = try await engine.commit(message: "amended", amend: true)

        #expect(newSHA != originalParent) // 提交被改写
        let logAfter = try await engine.commits(limit: 5, since: nil)
        #expect(logAfter[0].subject == "amended")
        #expect(logAfter[0].parents.first == grandparent) // 父提交不变（MRD 10.4-10）
    }

    @Test func emptyCommitRejected() async throws {
        let repo = try FixtureRepo.make(prefix: "emptycommit")
        try FixtureRepo.write(repo, "a.txt", "one\n")
        try FixtureRepo.commitAll(repo, "base")

        let engine = FixtureRepo.engine(repo)
        do {
            _ = try await engine.commit(message: "should fail", amend: false)
            Issue.record("暂存区为空不应产生提交")
        } catch let error as GitError {
            guard case .nothingToCommit = error else {
                Issue.record("应为 nothingToCommit，实际 \(error)")
                return
            }
        }
    }

    @Test func hookFailureSurfacesRawOutputAndNoCommit() async throws {
        let (repo, engine) = try FixtureRepo.makeHookRepo()
        let headBefore = try await engine.currentSHA()
        try await engine.stageFiles(["a.txt"])

        do {
            _ = try await engine.commit(message: "blocked by hook", amend: false)
            Issue.record("钩子失败应抛错")
        } catch let error as GitError {
            guard case .hookFailed(let output) = error else {
                Issue.record("应为 hookFailed，实际 \(error)")
                return
            }
            #expect(output.contains("hook says no"))
        }
        #expect(try await engine.currentSHA() == headBefore) // 提交未产生
        let status = try await engine.status()
        #expect(status.staged.count == 1) // 改动仍在暂存区
    }

    // MARK: 安全闸

    @Test func forcePushNeverAllowed() throws {
        #expect(throws: GitError.self) {
            try GitProcessRunner.validate(["push", "--force", "origin", "main"])
        }
        #expect(throws: GitError.self) {
            try GitProcessRunner.validate(["push", "--force-with-lease"])
        }
        #expect(throws: GitError.self) {
            try GitProcessRunner.validate(["push", "-f", "origin", "main"])
        }
        // 正常 push 放行
        try GitProcessRunner.validate(["push", "origin", "main"])
        try GitProcessRunner.validate(["push"])
    }

    @Test func resetHardAndCleanDenied() throws {
        #expect(throws: GitError.self) {
            try GitProcessRunner.validate(["reset", "--hard", "HEAD~1"])
        }
        #expect(throws: GitError.self) {
            try GitProcessRunner.validate(["clean", "-fd"])
        }
        #expect(throws: GitError.self) {
            try GitProcessRunner.validate(["tag", "-f", "v1"])
        }
    }

    @Test func nonFastForwardPushRejectedByGitNotSilenced() async throws {
        let repo = try FixtureRepo.make(prefix: "push")
        try FixtureRepo.write(repo, "a.txt", "one\n")
        try FixtureRepo.commitAll(repo, "first")

        let remoteURL = repo.deletingLastPathComponent().appendingPathComponent("origin.git")
        try GitShell.run(repo, "clone", "--bare", repo.path, remoteURL.path)
        try GitShell.run(repo, "remote", "add", "origin", remoteURL.path)
        try GitShell.run(repo, "push", "-u", "origin", "main")

        // 模拟他人在远端推进
        let shadow = repo.deletingLastPathComponent().appendingPathComponent("shadow")
        try GitShell.run(repo.deletingLastPathComponent(), "clone", remoteURL.path, shadow.path)
        try FixtureRepo.write(shadow, "shadow.txt", "someone else\n")
        try FixtureRepo.commitAll(shadow, "upstream commit")
        try GitShell.run(shadow, "push", "origin", "main")

        // 本地继续提交后 push：被拒（非快进），引擎原样抛错且不重试不 force
        try FixtureRepo.write(repo, "local.txt", "local\n")
        try FixtureRepo.commitAll(repo, "local commit")

        let engine = FixtureRepo.engine(repo)
        do {
            try await engine.push()
            Issue.record("非快进 push 应被远端拒绝")
        } catch let error as GitError {
            guard case .nonFastForward = error else {
                Issue.record("应归类为 nonFastForward，实际 \(error)")
                return
            }
        }
    }

    @Test func stashRoundtrip() async throws {
        let repo = try FixtureRepo.make(prefix: "stash")
        try FixtureRepo.write(repo, "a.txt", "one\n")
        try FixtureRepo.commitAll(repo, "base")
        try FixtureRepo.write(repo, "a.txt", "one\ntwo\n")

        let engine = FixtureRepo.engine(repo)
        try await engine.stashPush(message: "wip: two lines")
        var status = try await engine.status()
        #expect(status.isClean)

        let stashes = try await engine.stashes()
        #expect(stashes.count == 1)
        // %gs 的完整 reflog 主题形如 "On main: wip: two lines"
        #expect(stashes[0].message.contains("wip: two lines"))
        #expect(stashes[0].index == 0)

        try await engine.stashRestore(index: 0, mode: .pop)
        status = try await engine.status()
        #expect(status.unstaged.count == 1)
        #expect(try await engine.stashes().isEmpty)
    }

    @Test func tagsCreateListDelete() async throws {
        let repo = try FixtureRepo.make(prefix: "tag")
        try FixtureRepo.write(repo, "a.txt", "one\n")
        try FixtureRepo.commitAll(repo, "base")

        let engine = FixtureRepo.engine(repo)
        try await engine.createTag(name: "v0.1.0", message: nil)
        try await engine.createTag(name: "v0.2.0", message: "release note")

        let tags = try await engine.tags()
        #expect(tags.count == 2)
        #expect(tags.contains { $0.name == "v0.1.0" && !$0.isAnnotated })
        #expect(tags.contains { $0.name == "v0.2.0" && $0.isAnnotated })

        try await engine.deleteTag(name: "v0.1.0")
        #expect(try await engine.tags().count == 1)
    }
}
