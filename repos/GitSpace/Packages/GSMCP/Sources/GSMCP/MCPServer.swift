import Foundation
import GSInfra
import GSGitEngine
import GSIndex

/// MCP stdio server（Story-1031-mcp）：
/// - 传输：换行分隔 JSON-RPC 2.0（MCP stdio 规范），串行处理；
/// - 方法面：initialize / notifications/initialized / ping / tools/list / tools/call；
/// - stdout 是协议通道：除响应外不输出任何内容。
public actor MCPServer {
    public static let supportedProtocolVersions = ["2025-06-18", "2024-11-05"]
    /// 单工具响应文本上限：超过即截断，防止 Agent 上下文爆量。
    static let maxToolTextLength = 512_000

    private let configFile: URL
    private let workspaceStore: WorkspaceStore
    private let operationLog: OperationLog
    private let serverName: String
    private let serverVersion: String
    private var repoCache: [String: GitRepository] = [:]

    public init(configFile: URL = GSPaths.configFile,
                workspaceStore: WorkspaceStore = .shared,
                operationLog: OperationLog = .shared,
                serverName: String = "gitspace-mcp",
                serverVersion: String = "0.1.0") {
        self.configFile = configFile
        self.workspaceStore = workspaceStore
        self.operationLog = operationLog
        self.serverName = serverName
        self.serverVersion = serverVersion
    }

    /// 阻塞运行直到 stdin EOF（由 `GitSpaceApp mcp-serve` 子命令调用）。
    public func run() async throws {
        for await line in StdinLineStream() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if let response = await handle(line: trimmed) {
                writeResponse(response)
            }
        }
    }

    /// 单行请求处理（`run` 循环体；公开以便协议测试直连）。
    public func handleLine(_ line: String) async -> JSONValue? {
        await handle(line: line)
    }

    // MARK: - 请求处理

    private func handle(line: String) async -> JSONValue? {
        guard let data = line.data(using: .utf8) else {
            return JSONRPC.errorResponse(id: .null, code: JSONRPC.parseError, message: "Parse error")
        }
        let request: JSONValue
        do {
            request = try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            return JSONRPC.errorResponse(id: .null, code: JSONRPC.parseError, message: "Parse error: \(error.localizedDescription)")
        }
        guard let object = request.objectValue, let method = object["method"]?.stringValue else {
            return JSONRPC.errorResponse(id: .null, code: JSONRPC.invalidRequest, message: "Invalid Request")
        }
        let id = object["id"] ?? .null
        let isNotification = object["id"] == nil

        switch method {
        case "initialize":
            let requested = object["params"]?["protocolVersion"]?.stringValue
            let version = requested.flatMap { requestedVersion in
                Self.supportedProtocolVersions.first { $0 == requestedVersion }
            } ?? Self.supportedProtocolVersions[0]
            return JSONRPC.result(id: id, result: .object([
                "protocolVersion": .string(version),
                "capabilities": .object(["tools": .object(["listChanged": .bool(false)])]),
                "serverInfo": .object(["name": .string(serverName), "version": .string(serverVersion)])
            ]))

        case "notifications/initialized":
            return nil

        case "ping":
            return JSONRPC.result(id: id, result: .object([:]))

        case "tools/list":
            return JSONRPC.result(id: id, result: .object([
                "tools": .array(ToolRegistry.definitions.map(\.asListEntry))
            ]))

        case "tools/call":
            let response = await handleToolCall(params: object["params"])
            return isNotification ? nil : JSONRPC.result(id: id, result: response)

        default:
            // 未知 notification 静默忽略（JSON-RPC 约定）；未知请求报 method not found。
            return isNotification ? nil : JSONRPC.errorResponse(id: id, code: JSONRPC.methodNotFound, message: "Method not found: \(method)")
        }
    }

    private func handleToolCall(params: JSONValue?) async -> JSONValue {
        let name = params?["name"]?.stringValue
        guard let name, let tool = ToolRegistry.tool(named: name) else {
            return toolResult("未知工具：\(name ?? "(空)")。可用工具请调 tools/list 查看。", isError: true)
        }
        let arguments = params?["arguments"] ?? .object([:])

        if tool.isWrite {
            let writesEnabled = Self.writesEnabled(configFile: configFile)
            if !writesEnabled {
                return toolResult("「允许 MCP 写操作」已在 GitSpace 设置中关闭；请到 GitSpace 设置开启后重试，或改用只读工具查询。", isError: true)
            }
            if tool.requiresConfirm, arguments["confirm"]?.boolValue != true {
                return toolResult("""
                此操作是破坏性操作，需要显式传入 "confirm": true 才会执行。
                影响范围：\(tool.description)
                请先向使用者说明影响并获得同意，再携带 confirm 重试。
                """, isError: true)
            }
        }

        do {
            // list_repos 不需要仓库；其余工具解析仓库后执行。
            if name == "list_repos" {
                return toolResult(MCPTextLimiter.truncate(formatManagedRepos(workspaceStore.loadAll())))
            }
            let repo = try repository(for: arguments)
            do {
                let text = try await GitToolExecutor.execute(name: name, arguments: arguments, repo: repo)
                if tool.isWrite {
                    await operationLog.recordSuccess(
                        repoName: repo.name,
                        action: "mcp.\(name)",
                        durationMs: 0,
                        detail: "经 MCP 触发的写操作（引擎侧另有留痕）"
                    )
                }
                return toolResult(MCPTextLimiter.truncate(text))
            } catch {
                if tool.isWrite {
                    await operationLog.recordFailure(
                        repoName: repo.name,
                        action: "mcp.\(name)",
                        durationMs: 0,
                        detail: String(describing: error)
                    )
                }
                throw error
            }
        } catch let error as GitError {
            return toolResult(MCPTextLimiter.truncate(error.errorDescription ?? String(describing: error)), isError: true)
        } catch {
            return toolResult(MCPTextLimiter.truncate(String(describing: error)), isError: true)
        }
    }

    private func repository(for arguments: JSONValue) throws -> GitRepository {
        guard let path = arguments["repo"]?.stringValue, !path.isEmpty else {
            throw MCPServerError.missingParameter("repo（仓库绝对路径）")
        }
        // 归一化键：/var 与 /private/var、尾斜杠等差异会拆出多实例，破坏「同仓串行」语义。
        let normalizedPath = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
        if let cached = repoCache[normalizedPath] { return cached }
        guard let repo = GitRepository(path: URL(fileURLWithPath: path)) else {
            throw MCPServerError.invalidRepo(path)
        }
        repoCache[normalizedPath] = repo
        return repo
    }

    // MARK: - 配置与输出

    /// 写开关读取：文件缺失 = 默认允许；文件损坏 = 拒绝写（fail-closed，不让坏配置放大权限）。
    public static func writesEnabled(configFile: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: configFile.path) else { return true }
        return (try? MCPAppConfig.read(from: configFile))?.mcpWritesEnabled ?? false
    }

    private func writeResponse(_ value: JSONValue) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(value) else { return }
        var line = data
        line.append(0x0A)
        FileHandle.standardOutput.write(line)
    }

    private func toolResult(_ text: String, isError: Bool = false) -> JSONValue {
        var payload: [String: JSONValue] = [
            "content": .array([.object(["type": .string("text"), "text": .string(text)])])
        ]
        if isError { payload["isError"] = .bool(true) }
        return .object(payload)
    }

    private func formatManagedRepos(_ configs: [WorkspaceConfig]) -> String {
        var lines = ["GitSpace 已纳管仓库："]
        var count = 0
        for workspace in configs {
            for entry in workspace.repos {
                count += 1
                lines.append("\(entry.name)\t\(entry.path)")
            }
        }
        if count == 0 { lines.append("（暂无纳管仓库，可在 GitSpace 中添加，或直接操作任意本地仓库路径）") }
        lines.append("说明：其他工具的 repo 参数接受任意本地 git 仓库绝对路径，不限于以上清单。")
        return lines.joined(separator: "\n")
    }
}

/// server 层错误（工具执行前校验）。
enum MCPServerError: Error, CustomStringConvertible {
    case missingParameter(String)
    case invalidRepo(String)

    var description: String {
        switch self {
        case .missingParameter(let name):
            return "缺少必需参数：\(name)"
        case .invalidRepo(let path):
            return "不是 Git 仓库（或路径不存在）：\(path)。请传入含 .git 的仓库根目录绝对路径。"
        }
    }
}

/// 工具响应文本限长。
enum MCPTextLimiter {
    static func truncate(_ text: String, limit: Int = MCPServer.maxToolTextLength) -> String {
        guard text.count > limit else { return text }
        let head = String(text.prefix(limit))
        return head + "\n\n…[输出过长已截断，原始长度 \(text.count) 字符；请用更精确的查询缩小范围]"
    }
}

/// stdin 行读取：独立线程阻塞读，避免占用 Swift 协作线程池。
/// 单次使用约束：每个实例只应被迭代一次（二次迭代会再开线程重复读 stdin）。
struct StdinLineStream: AsyncSequence {
    typealias Element = String

    func makeAsyncIterator() -> AsyncStream<String>.Iterator {
        AsyncStream<String>(bufferingPolicy: .unbounded) { continuation in
            Thread.detachNewThread {
                let handle = FileHandle.standardInput
                var buffer: [UInt8] = []
                while true {
                    let chunk = handle.availableData
                    if chunk.isEmpty { break } // EOF
                    buffer.append(contentsOf: chunk)
                    while let newlineIndex = buffer.firstIndex(of: 0x0A) {
                        let line = String(decoding: buffer[0..<newlineIndex], as: UTF8.self)
                        buffer.removeSubrange(0...newlineIndex)
                        continuation.yield(line)
                    }
                }
                if !buffer.isEmpty {
                    continuation.yield(String(decoding: buffer, as: UTF8.self))
                }
                continuation.finish()
            }
        }.makeAsyncIterator()
    }
}
