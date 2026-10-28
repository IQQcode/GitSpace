import Testing
import Foundation
import GSGitEngine
import GSTestSupport

/// 分支 / 合并 / 冲突（MRD 10.4-11、10.4-12）。
@Suite("Branch & Merge")
struct BranchMergeTests {
    @Test func createSwitchDeleteBranch() async throws {
        let repo = try FixtureRepo.make(prefix: "branch")
        try FixtureRepo.write(repo, "a.txt", "one\n")
        try FixtureRepo.commitAll(repo, "first")

        let engine = FixtureRepo.engine(repo)
        // switch -c 创建并切换到新分支
        try await engine.createBranch(name: "feature/test", from: nil)
        var branches = try await engine.localBranches()
        #expect(branches.contains { $0.name == "feature/test" && $0.isCurrent })

        try await engine.switchBranch(name: "main")
        branches = try await engine.localBranches()
        #expect(branches.first { $0.isCurrent }?.name == "main")
        #expect(branches.contains { $0.name == "feature/test" && !$0.isCurrent })

        // 已合并分支 -d 直接删除成功
        try await engine.deleteBranch(name: "feature/test", force: false)
        branches = try await engine.localBranches()
        #expect(!branches.contains { $0.name == "feature/test" })
    }

    @Test func dirtyWorkspaceBlocksSwitch() async throws {
        let repo = try FixtureRepo.make(prefix: "dirty")
        try FixtureRepo.write(repo, "a.txt", "one\n")
        try FixtureRepo.commitAll(repo, "first")
        try GitShell.run(repo, "branch", "other")
        try FixtureRepo.write(repo, "a.txt", "dirty\n")

        let engine = FixtureRepo.engine(repo)
        do {
            try await engine.switchBranch(name: "other")
            Issue.record("脏工作区切换应被阻止（MRD 10.4-11）")
        } catch let error as GitError {
            guard case .uncommittedChanges = error else {
                Issue.record("应归类为 uncommittedChanges，实际 \(error)")
                return
            }
        }
        // stash 后切换成功
        try await engine.stashPush(message: "auto")
        try await engine.switchBranch(name: "other")
        let status = try await engine.status()
        #expect(status.branch == "other")
    }

    @Test func deleteUnmergedBranchRequiresForce() async throws {
        let repo = try FixtureRepo.make(prefix: "unmerged")
        try FixtureRepo.write(repo, "a.txt", "one\n")
        try FixtureRepo.commitAll(repo, "first")
        try GitShell.run(repo, "checkout", "-b", "orphan")
        try FixtureRepo.write(repo, "b.txt", "orphan\n")
        try FixtureRepo.commitAll(repo, "orphan commit")
        try GitShell.run(repo, "checkout", "main")

        let engine = FixtureRepo.engine(repo)
        do {
            try await engine.deleteBranch(name: "orphan", force: false)
            Issue.record("-d 应被 git 拒绝")
        } catch {
            // 预期失败
        }
        try await engine.deleteBranch(name: "orphan", force: true)
        let branches = try await engine.localBranches()
        #expect(!branches.contains { $0.name == "orphan" })
    }

    @Test func renameBranch() async throws {
        let repo = try FixtureRepo.make(prefix: "rename")
        try FixtureRepo.write(repo, "a.txt", "one\n")
        try FixtureRepo.commitAll(repo, "first")
        try GitShell.run(repo, "branch", "old-name")

        let engine = FixtureRepo.engine(repo)
        try await engine.renameBranch(oldName: "old-name", newName: "new-name")
        let branches = try await engine.localBranches()
        #expect(branches.contains { $0.name == "new-name" })
        #expect(!branches.contains { $0.name == "old-name" })
    }

    @Test func checkoutRemoteBranchSetsUpstream() async throws {
        let repo = try FixtureRepo.make(prefix: "remote")
        try FixtureRepo.write(repo, "a.txt", "one\n")
        try FixtureRepo.commitAll(repo, "first")
        let remoteURL = repo.deletingLastPathComponent().appendingPathComponent("origin.git")
        try GitShell.run(repo, "clone", "--bare", repo.path, remoteURL.path)
        try GitShell.run(repo, "remote", "add", "origin", remoteURL.path)
        try GitShell.run(repo, "push", "-u", "origin", "main")
        try GitShell.run(repo, "push", "origin", "main:refs/heads/remote-feature")
        try GitShell.run(repo, "fetch", "origin")

        let engine = FixtureRepo.engine(repo)
        let remotes = try await engine.remoteBranches()
        let target = try #require(remotes.first { $0.branchName == "remote-feature" })
        try await engine.checkoutRemoteBranch(target)

        let status = try await engine.status()
        #expect(status.branch == "remote-feature")
        #expect(status.upstream == "origin/remote-feature")
    }

    // MARK: 合并与冲突

    @Test func conflictListMatchesGitPorcelain() async throws {
        let (repo, engine) = try FixtureRepo.makeConflictRepo()

        let outcome = try await engine.merge(ref: "feature")
        guard case .conflicts(let entries) = outcome else {
            Issue.record("预期冲突，实际 \(outcome)")
            return
        }
        #expect(entries.map(\.path) == ["conflict.txt"])
        #expect(entries.allSatisfy { $0.code == "UU" })

        // 与 git status porcelain v2 的 u 记录逐项一致（MRD 10.4-12）
        let raw = try GitShell.run(repo, "status", "--porcelain=v2", "-z")
        let records = raw.split(separator: Character("\u{0}"), omittingEmptySubsequences: true).map(String.init)
        let gitUnmerged = records.filter { $0.hasPrefix("u ") }.compactMap { record -> String? in
            let parts = record.split(separator: " ", maxSplits: 10, omittingEmptySubsequences: false)
            return parts.count == 11 ? String(parts[10]) : nil
        }
        #expect(entries.map(\.path) == gitUnmerged)
    }

    @Test func oursTheirsMatchGitCheckout() async throws {
        let (repo, engine) = try FixtureRepo.makeConflictRepo()
        _ = try await engine.merge(ref: "feature")

        try await engine.resolveConflict(path: "conflict.txt", resolution: .ours)
        let oursContent = try FixtureRepo.read(repo, "conflict.txt")

        // git 基准：checkout --ours 的结果
        try GitShell.run(repo, "checkout", "--ours", "--", "conflict.txt")
        let gitOurs = try FixtureRepo.read(repo, "conflict.txt")
        #expect(oursContent == gitOurs)
        #expect(oursContent.contains("main changed the shared line"))
    }

    @Test func abortMergeRestoresPreMergeState() async throws {
        let (repo, engine) = try FixtureRepo.makeConflictRepo()
        let headBefore = try await engine.currentSHA()

        _ = try await engine.merge(ref: "feature")
        try await engine.abortMerge()

        let status = try await engine.status()
        #expect(status.unmerged.isEmpty)
        #expect(!status.isMergeInProgress)
        #expect(status.isClean)
        #expect(try await engine.currentSHA() == headBefore)

        // reflog 校验：HEAD 未前进（MRD 10.4-12）
        let reflog = try GitShell.run(repo, "reflog", "-n", "3", "--format=%H")
        #expect(reflog.contains(headBefore))
    }

    @Test func fullConflictResolutionFlow() async throws {
        let (repo, engine) = try FixtureRepo.makeConflictRepo()
        let outcome = try await engine.merge(ref: "feature")
        guard case .conflicts = outcome else {
            Issue.record("预期冲突")
            return
        }

        try await engine.resolveConflict(path: "conflict.txt", resolution: .theirs)
        try await engine.markConflictResolved(path: "conflict.txt")

        var status = try await engine.status()
        #expect(status.unmerged.isEmpty)
        #expect(status.isMergeInProgress)
        #expect(!status.staged.isEmpty)

        _ = try await engine.commitMerge()
        status = try await engine.status()
        #expect(status.isClean)
        #expect(!status.isMergeInProgress)
        let content = try FixtureRepo.read(repo, "conflict.txt")
        #expect(content.contains("feature changed the shared line"))
    }
}
