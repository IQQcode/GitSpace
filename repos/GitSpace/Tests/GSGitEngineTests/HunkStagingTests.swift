import Testing
import Foundation
import GSGitEngine
import GSTestSupport

/// 块级暂存管线（TechStack §5.3 / MRD 10.4-10）：
/// 1) 解析-重组 roundtrip 与 git 原始 diff 逐字一致；
/// 2) 选中 hunk 暂存后，`git diff --cached` 与"原始 diff 过滤选中 hunk"一致。
@Suite("Hunk Staging")
struct HunkStagingTests {
    @Test func diffRoundtripPreservesPatchText() async throws {
        let (repo, engine) = try FixtureRepo.makeMultiHunkRepo()
        // 再加一个文件，保证多文件多 hunk
        try FixtureRepo.write(repo, "other/second.txt", "a\nb\n")
        try GitShell.run(repo, "add", "other/second.txt")

        let original = try GitShell.run(repo, "diff", "--no-color")
        guard original.contains("diff --git") else {
            Issue.record("fixture 应产生 diff")
            return
        }
        let files = DiffParser.parse(original)
        #expect(files.count == 1)
        #expect(files[0].hunks.count == 3)
        #expect(files[0].additions == 3)
        #expect(files[0].deletions == 3)

        let rebuilt = files[0].fullPatch().flatMap { String(data: $0, encoding: .utf8) }
        #expect(rebuilt == original)
        _ = engine // 引擎可构造性
    }

    @Test func stagedResultEqualsFilteredPatch() async throws {
        let (repo, engine) = try FixtureRepo.makeMultiHunkRepo()
        let original = try GitShell.run(repo, "diff", "--no-color")
        let files = DiffParser.parse(original)
        let file = files[0]
        let selected: Set<Int> = [0, 2]
        let expectedPatch = file.patch(selectingHunkIDs: selected)
            .flatMap { String(data: $0, encoding: .utf8) }

        try await engine.stageHunks(of: file, hunkIDs: selected)

        let cached = try GitShell.run(repo, "diff", "--cached")
        // index 行的 blob 哈希与暂存前的 worktree blob 不同，语义比对时剔除
        #expect(stripIndexLines(cached) == stripIndexLines(expectedPatch))

        // 剩余未暂存 = 未选中的 hunk
        let remaining = try GitShell.run(repo, "diff")
        let remainingFiles = DiffParser.parse(remaining)
        #expect(remainingFiles.count == 1)
        #expect(remainingFiles[0].hunks.count == 1)
        #expect(remainingFiles[0].hunks[0].patchText() == file.hunks[1].patchText())

        // 状态侧：1 个文件进暂存区
        let status = try await engine.status()
        #expect(status.staged.count == 1)
        #expect(status.unstaged.count == 1)
    }

    private func stripIndexLines(_ text: String?) -> String {
        (text ?? "")
            .split(separator: "\n")
            .filter { !$0.hasPrefix("index ") }
            .joined(separator: "\n")
    }

    @Test func unstageHunksReversesSelection() async throws {
        let (repo, engine) = try FixtureRepo.makeMultiHunkRepo()
        try GitShell.run(repo, "add", "-A")

        let cached = try GitShell.run(repo, "diff", "--cached")
        let files = DiffParser.parse(cached)
        let file = files[0]
        #expect(file.hunks.count == 3)

        // 从暂存区撤掉 hunk 1：相当于 add -p 里 unstage 该块
        try await engine.unstageHunks(of: file, hunkIDs: [1])

        let cachedAfter = try GitShell.run(repo, "diff", "--cached")
        let filesAfter = DiffParser.parse(cachedAfter)
        #expect(filesAfter.count == 1)
        #expect(filesAfter[0].hunks.count == 2)
        #expect(filesAfter[0].hunks.map(\.header) == [file.hunks[0].header, file.hunks[2].header])

        let unstaged = DiffParser.parse(try GitShell.run(repo, "diff"))
        #expect(unstaged.count == 1)
        #expect(unstaged[0].hunks.count == 1)
        #expect(unstaged[0].hunks[0].patchText() == file.hunks[1].patchText())
    }

    @Test func stageWholeFileMatchesGitAdd() async throws {
        let (repo, engine) = try FixtureRepo.makeMultiHunkRepo()
        try await engine.stageFiles(["sample.txt"])
        let cached = try GitShell.run(repo, "diff", "--cached")
        let status = try await engine.status()
        #expect(status.staged.count == 1)
        #expect(status.unstaged.isEmpty)
        #expect(cached.contains("diff --git a/sample.txt"))
    }
}
