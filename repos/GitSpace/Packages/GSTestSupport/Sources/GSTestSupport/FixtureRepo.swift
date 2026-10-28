import Foundation
import GSGitEngine

/// git fixture 仓生成器（TechStack §13：可产出指定拓扑/冲突/钩子场景的临时仓库）。
public enum FixtureRepo {
    /// 创建一个带 main 分支与首次提交的临时仓库。
    @discardableResult
    public static func make(prefix: String = "repo") throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitspace-tests", isDirectory: true)
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let repo = root.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try GitShell.run(repo, "init", "-b", "main")
        try GitShell.run(repo, "config", "user.name", "Tester")
        try GitShell.run(repo, "config", "user.email", "tester@example.com")
        return repo
    }

    public static func write(_ repo: URL, _ relativePath: String, _ content: String) throws {
        let url = repo.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    public static func read(_ repo: URL, _ relativePath: String) throws -> String {
        try String(contentsOf: repo.appendingPathComponent(relativePath), encoding: .utf8)
    }

    public static func commitAll(_ repo: URL, _ message: String) throws {
        try GitShell.run(repo, "add", "-A")
        try GitShell.run(repo, "commit", "-m", message)
    }

    public static func engine(_ repo: URL) -> GitRepository {
        guard let engine = GitRepository(path: repo, operationLogger: nil) else {
            fatalError("fixture 仓初始化失败：\(repo.path)")
        }
        return engine
    }

    /// 多 hunk 场景：20 行文件在第 2 / 10 / 18 行分别改动（相距 >3 行上下文，保证拆成 3 个 hunk）。
    @discardableResult
    public static func makeMultiHunkRepo() throws -> (repo: URL, engine: GitRepository) {
        let repo = try make(prefix: "multihunk")
        let base = (1...20).map { "line \($0)" }.joined(separator: "\n") + "\n"
        try write(repo, "sample.txt", base)
        try commitAll(repo, "base")

        var lines = base.split(separator: "\n").map(String.init)
        lines[1] = "line 2 modified"
        lines[9] = "line 10 modified"
        lines[17] = "line 18 modified"
        try write(repo, "sample.txt", lines.joined(separator: "\n") + "\n")
        return (repo, engine(repo))
    }

    /// 冲突场景：main 与 feature 改同一行后合并。
    @discardableResult
    public static func makeConflictRepo() throws -> (repo: URL, engine: GitRepository) {
        let repo = try make(prefix: "conflict")
        try write(repo, "conflict.txt", "shared line\nmain only\n")
        try commitAll(repo, "base")
        try GitShell.run(repo, "checkout", "-b", "feature")
        try write(repo, "conflict.txt", "feature changed the shared line\nmain only\n")
        try commitAll(repo, "feature edit")
        try GitShell.run(repo, "checkout", "main")
        try write(repo, "conflict.txt", "main changed the shared line\nmain only\n")
        try commitAll(repo, "main edit")
        return (repo, engine(repo))
    }

    /// pre-commit 钩子失败场景（MRD 10.2-C：不吞错、不产生提交）。
    @discardableResult
    public static func makeHookRepo() throws -> (repo: URL, engine: GitRepository) {
        let repo = try make(prefix: "hook")
        try write(repo, "a.txt", "hello\n")
        try commitAll(repo, "base")
        try write(repo, "a.txt", "hello changed\n")
        let hook = """
        #!/bin/sh
        echo "hook says no"
        exit 1
        """
        let hookURL = repo.appendingPathComponent(".git/hooks/pre-commit")
        try hook.write(to: hookURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hookURL.path)
        return (repo, engine(repo))
    }
}
