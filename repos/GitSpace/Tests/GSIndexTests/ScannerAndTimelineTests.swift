import Testing
import Foundation
import GSIndex
import GSGitEngine
import GSTestSupport
import GSInfra

@Suite("Scanner & Workspace")
struct ScannerTests {
    @Test func discoversReposSkippingBuildDirs() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("scan-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        for name in ["GdThread", "GdHome"] {
            let repo = parent.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
            try GitShell.run(repo, "init", "-b", "main")
        }
        // 嵌套两层
        let nested = parent.appendingPathComponent("components/GdNested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try GitShell.run(nested, "init", "-b", "main")
        // 普通目录（非仓库）
        try FileManager.default.createDirectory(at: parent.appendingPathComponent("PlainDir"), withIntermediateDirectories: true)
        // 构建产物内的仓库不下钻
        let insideBuild = parent.appendingPathComponent("GdThread/node_modules/HiddenRepo")
        try FileManager.default.createDirectory(at: insideBuild, withIntermediateDirectories: true)
        try GitShell.run(insideBuild, "init", "-b", "main")

        let discovered = try WorkspaceScanner.scan(parent: parent, knownPaths: [], maxDepth: 3)
        let names = discovered.map(\.name)
        #expect(names == ["GdHome", "GdNested", "GdThread"])
        #expect(discovered.allSatisfy { !$0.alreadyManaged })

        let known = Set(discovered.filter { $0.name == "GdThread" }.map { $0.path.path })
        #expect(!known.isEmpty)
        let second = try WorkspaceScanner.scan(parent: parent, knownPaths: known, maxDepth: 3)
        #expect(second.first { $0.name == "GdThread" }?.alreadyManaged == true)
    }
}

@Suite("WorkspaceStore")
struct WorkspaceStoreTests {
    @Test func roundtripConfig() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ws-store-\(UUID().uuidString)", isDirectory: true)
        let store = WorkspaceStore(directory: dir)
        #expect(store.loadAll().isEmpty)

        let config = WorkspaceConfig(
            name: "抖音 iOS · 主工程",
            repos: [
                ManagedRepoConfig(path: "/tmp/app", name: "app"),
                ManagedRepoConfig(path: "/tmp/GdThread")
            ]
        )
        store.saveAll([config])

        let loaded = WorkspaceStore(directory: dir).loadAll()
        #expect(loaded.count == 1)
        #expect(loaded[0].name == "抖音 iOS · 主工程")
        #expect(loaded[0].repos.map(\.name) == ["app", "GdThread"])
        #expect(loaded[0].repos[1].name == "GdThread") // 默认取目录名
    }
}

@Suite("Timeline Aggregator")
struct TimelineAggregatorTests {
    @Test func mergesAndSortsAcrossRepos() throws {
        let now = Int(Date().timeIntervalSince1970)
        func commit(_ sha: String, _ subject: String, _ ts: Int) -> CommitInfo {
            CommitInfo(
                sha: sha, shortSHA: String(sha.prefix(7)), authorName: "陈默", authorEmail: "c@m.com",
                authorTimestamp: ts, committerTimestamp: ts, parents: [], decorations: [], subject: subject, body: ""
            )
        }
        let repoA = [
            commit("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "A-older", now - 100),
            commit("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "A-newer", now - 10)
        ]
        let repoB = [
            commit("cccccccccccccccccccccccccccccccccccccccc", "B-middle", now - 50)
        ]
        let merged = TimelineAggregator.build(repos: [
            ("GdHome", "/tmp/home", repoA),
            ("GdThread", "/tmp/thread", repoB)
        ])
        #expect(merged.map { $0.commit.subject } == ["A-newer", "B-middle", "A-older"])
        #expect(merged.map(\.repoName) == ["GdHome", "GdThread", "GdHome"])
        #expect(merged[1].lane == 1) // 每仓一条 lane
        #expect(merged[0].id == "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb@GdHome")
    }
}
