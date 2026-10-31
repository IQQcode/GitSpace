import Testing
import Foundation
import GSGitEngine
import GSInfra
import GSMCP
import GSTestSupport

/// MCP 协议层（Story-1031-mcp W2）：handshake / tools/list / 错误码。
@Suite("MCP Protocol")
struct MCPProtocolTests {
    private func makeServer(config: [String: JSONValue] = [:]) throws -> MCPServer {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitspace-mcp-proto-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let configFile = dir.appendingPathComponent("config.json")
        if !config.isEmpty {
            let object = JSONValue.object(config)
            try JSONEncoder().encode(object).write(to: configFile)
        }
        return MCPServer(configFile: configFile, operationLog: OperationLog(directory: dir.appendingPathComponent("logs")))
    }

    private func text(_ response: JSONValue?) -> String? {
        guard case .array(let content) = response?["result"]?["content"] else { return nil }
        return content.first?["text"]?.stringValue
    }

    @Test func initializeNegotiatesKnownVersion() async throws {
        let server = try makeServer()
        let response = await server.handleLine(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}"#)
        #expect(response?["result"]?["protocolVersion"]?.stringValue == "2024-11-05")
        #expect(response?["result"]?["serverInfo"]?["name"]?.stringValue == "gitspace-mcp")
    }

    @Test func initializeFallsBackOnUnknownVersion() async throws {
        let server = try makeServer()
        let response = await server.handleLine(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2099-01-01"}}"#)
        #expect(response?["result"]?["protocolVersion"]?.stringValue == MCPServer.supportedProtocolVersions[0])
    }

    @Test func pingReturnsEmptyResult() async throws {
        let server = try makeServer()
        let response = await server.handleLine(#"{"jsonrpc":"2.0","id":2,"method":"ping"}"#)
        #expect(response?["result"] == .object([:]))
    }

    @Test func toolsListMatchesRegistry() async throws {
        let server = try makeServer()
        let response = await server.handleLine(#"{"jsonrpc":"2.0","id":3,"method":"tools/list"}"#)
        guard case .array(let tools) = response?["result"]?["tools"] else {
            Issue.record("tools/list 应返回数组")
            return
        }
        #expect(tools.count >= 50)
        #expect(tools.allSatisfy { $0["name"]?.stringValue != nil })
        #expect(tools.allSatisfy { $0["inputSchema"]?["type"]?.stringValue == "object" })
        let names = Set(tools.compactMap { $0["name"]?.stringValue })
        #expect(names.contains("git_status"))
        #expect(names.contains("git_bisect_start"))
        #expect(names.contains("git_revert"))
        #expect(names.contains("list_repos"))
        // 防漂移：与 Registry 全量一致（防未来新增工具漏进 tools/list）
        #expect(names == Set(ToolRegistry.names))
    }

    /// 硬闸结构断言（doc §5-3）：MCP 面不存在任意命令透传，也没有触发 force 的入口。
    @Test func noArbitraryCommandOrForcePassthrough() async throws {
        for name in ToolRegistry.names {
            guard let tool = ToolRegistry.tool(named: name) else {
                Issue.record("工具缺失：\(name)")
                continue
            }
            guard case .object(let properties) = tool.inputSchema["properties"] else {
                Issue.record("\(name) schema 无 properties")
                continue
            }
            // 不存在接受任意 git 命令/参数数组的工具（引擎硬闸的前提：命令面封闭）
            for forbidden in ["command", "arguments", "args", "force_push"] {
                #expect(properties[forbidden] == nil, "\(name) 不得暴露 \(forbidden) 参数")
            }
        }
        // push 类工具不提供 force 入参（引擎对 force push 参数级拦截，MCP 面也不给入口）
        let pushSchema = ToolRegistry.tool(named: "git_push")?.inputSchema
        #expect(pushSchema?["properties"]?["force"] == nil)
    }

    @Test func unknownMethodReturns32601() async throws {
        let server = try makeServer()
        let response = await server.handleLine(#"{"jsonrpc":"2.0","id":4,"method":"no/such/method"}"#)
        #expect(response?["error"]?["code"]?.intValue == -32601)
    }

    @Test func malformedJSONReturns32700() async throws {
        let server = try makeServer()
        let response = await server.handleLine("this is not json")
        #expect(response?["error"]?["code"]?.intValue == -32700)
    }

    @Test func notificationProducesNoResponse() async throws {
        let server = try makeServer()
        let initialized = await server.handleLine(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        #expect(initialized == nil)
    }
}

/// 工具行为（fixture 仓 + server 直连，等价性与安全口径）。
@Suite("MCP Tools")
struct MCPToolTests {
    private func makeServer(config: [String: JSONValue] = [:]) throws -> (MCPServer, URL, OperationLog) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitspace-mcp-tool-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let configFile = dir.appendingPathComponent("config.json")
        if !config.isEmpty {
            try JSONEncoder().encode(JSONValue.object(config)).write(to: configFile)
        }
        let log = OperationLog(directory: dir.appendingPathComponent("logs"))
        return (MCPServer(configFile: configFile, operationLog: log), dir, log)
    }

    private func call(_ server: MCPServer, _ name: String, _ arguments: [String: JSONValue], id: Int = 10) async throws -> JSONValue? {
        let argumentsJSON = JSONValue.object(arguments)
        let data = try JSONEncoder().encode(JSONValue.object([
            "jsonrpc": .string("2.0"),
            "id": .int(id),
            "method": .string("tools/call"),
            "params": .object(["name": .string(name), "arguments": argumentsJSON])
        ]))
        let line = String(decoding: data, as: UTF8.self)
        return await server.handleLine(line)
    }

    private func isError(_ response: JSONValue?) -> Bool {
        response?["result"]?["isError"]?.boolValue == true
    }

    private func text(_ response: JSONValue?) -> String? {
        guard case .array(let content) = response?["result"]?["content"] else { return nil }
        return content.first?["text"]?.stringValue
    }

    /// 10 提交线性链，第 7 个提交注入 bug（同 VCSTests 口径）。
    private func makeLinearRepo() throws -> (URL, [String]) {
        let repo = try FixtureRepo.make(prefix: "mcp")
        try FixtureRepo.write(repo, "stable.txt", "stable\n")
        try FixtureRepo.commitAll(repo, "c1")
        var shas = [try GitShell.run(repo, "rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)]
        for i in 2...10 {
            try FixtureRepo.write(repo, "noise\(i).txt", "noise \(i)\n")
            if i == 7 { try FixtureRepo.write(repo, "feature.txt", "buggy line\n") }
            try FixtureRepo.commitAll(repo, "c\(i)")
            shas.append(try GitShell.run(repo, "rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return (repo, shas)
    }

    @Test func statusToolReflectsEngineState() async throws {
        let (server, _, _) = try makeServer()
        let repoURL = try makeLinearRepo().0

        let response = try await call(server, "git_status", ["repo": .string(repoURL.path)])
        let output = text(response) ?? ""
        #expect(!isError(response))
        #expect(output.contains("分支：main"))
        #expect(output.contains("工作区干净"))
    }

    @Test func stageAndCommitViaMCPProducesCommitAndLog() async throws {
        let (server, dir, log) = try makeServer()
        let repoURL = try makeLinearRepo().0

        try FixtureRepo.write(repoURL, "newfile.txt", "new content\n")
        _ = try await call(server, "git_stage", ["repo": .string(repoURL.path), "paths": .array([.string("newfile.txt")])])
        let commitResponse = try await call(server, "git_commit", ["repo": .string(repoURL.path), "message": .string("feat: via mcp")])

        #expect(!isError(commitResponse))
        #expect(text(commitResponse)?.hasPrefix("提交完成：") == true)

        let subject = try GitShell.run(repoURL, "log", "--format=%s", "-1").trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(subject == "feat: via mcp")
        let status = try await call(server, "git_status", ["repo": .string(repoURL.path)])
        #expect(text(status)?.contains("工作区干净") == true)

        let entries = await log.recentEntries()
        #expect(entries.contains { $0.action == "mcp.git_commit" && $0.result == "success" })
        #expect(entries.contains { $0.action == "mcp.git_stage" && $0.result == "success" })
    }

    @Test func discardRequiresExplicitConfirm() async throws {
        let (server, _, _) = try makeServer()
        let repoURL = try makeLinearRepo().0
        try FixtureRepo.write(repoURL, "stable.txt", "modified\n")

        let refused = try await call(server, "git_discard", [
            "repo": .string(repoURL.path), "scope": .string("worktree"), "path": .string("stable.txt")
        ])
        #expect(isError(refused))
        #expect(text(refused)?.contains("confirm") == true)
        #expect(try FixtureRepo.read(repoURL, "stable.txt") == "modified\n") // 未执行

        let allowed = try await call(server, "git_discard", [
            "repo": .string(repoURL.path), "scope": .string("worktree"), "path": .string("stable.txt"), "confirm": .bool(true)
        ])
        #expect(!isError(allowed))
        #expect(try FixtureRepo.read(repoURL, "stable.txt") == "stable\n")
    }

    @Test func writesDisabledByConfigAreRejected() async throws {
        let (server, dir, _) = try makeServer(config: ["mcpWritesEnabled": .bool(false)])
        let repoURL = try makeLinearRepo().0
        try FixtureRepo.write(repoURL, "x.txt", "x\n")

        let response = try await call(server, "git_stage", ["repo": .string(repoURL.path), "paths": .array([.string("x.txt")])])
        #expect(isError(response))
        #expect(text(response)?.contains("MCP 写操作") == true)
        // 读工具不受影响
        let read = try await call(server, "git_status", ["repo": .string(repoURL.path)])
        #expect(!isError(read))
    }

    /// config.json 损坏时 fail-closed（写被拒），缺失时默认允许。
    @Test func corruptConfigFailsClosed() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitspace-mcp-corrupt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let configFile = dir.appendingPathComponent("config.json")
        try Data("{{{ not json".utf8).write(to: configFile)

        #expect(MCPServer.writesEnabled(configFile: configFile) == false)
        #expect(MCPServer.writesEnabled(configFile: dir.appendingPathComponent("missing.json")) == true)
    }

    @Test func unknownToolAndInvalidRepoReturnReadableErrors() async throws {
        let (server, dir, _) = try makeServer()
        let bad = try await call(server, "no_such_tool", ["repo": .string(dir.path)])
        #expect(isError(bad))

        let notRepo = try await call(server, "git_status", ["repo": .string(dir.path)])
        #expect(isError(notRepo))
        #expect(text(notRepo)?.contains("不是 Git 仓库") == true)
    }

    @Test func bisectWorkflowViaMCP() async throws {
        let (server, dir, _) = try makeServer()
        let (repoURL, shas) = try makeLinearRepo()
        // 用副本仓跑二分，避免 repoCache 与其他用例互相干扰
        let workURL = dir.appendingPathComponent("bisect-repo")
        try FileManager.default.copyItem(at: repoURL, to: workURL)

        let start = try await call(server, "git_bisect_start", [
            "repo": .string(workURL.path), "bad": .string(shas[9]), "good": .string(shas[0]), "confirm": .bool(true)
        ], id: 20)
        if isError(start) { Issue.record("bisect_start 失败：\(text(start) ?? "")") }
        #expect(!isError(start))

        var log = text(try await call(server, "git_bisect_log", ["repo": .string(workURL.path)], id: 21)) ?? ""
        var rounds = 0
        while !log.contains("first bad commit") {
            rounds += 1
            #expect(rounds <= 10)
            if rounds > 10 { break }
            let isBad = (try? FixtureRepo.read(workURL, "feature.txt"))?.contains("buggy") == true
            log = text(try await call(server, isBad ? "git_bisect_bad" : "git_bisect_good", ["repo": .string(workURL.path)], id: 22 + rounds)) ?? ""
        }
        #expect(log.contains("first bad commit"))

        let reset = try await call(server, "git_bisect_reset", ["repo": .string(workURL.path)], id: 40)
        #expect(!isError(reset))
        let sha = text(try await call(server, "git_current_sha", ["repo": .string(workURL.path)], id: 41))
        #expect(sha == shaOfHEAD(workURL))
    }

    private func shaOfHEAD(_ repo: URL) -> String {
        (try? GitShell.run(repo, "rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
    }
}