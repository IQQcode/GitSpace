import Foundation
import GSInfra

/// 应用配置（GUI 设置页与 MCP 模块共读共写）：`GSPaths.configFile`（config.json）。
/// MCP server 每次写工具调用前重读文件，保证设置页改动即时生效。
public struct MCPAppConfig: Codable, Sendable {
    /// 是否允许经 MCP 执行写操作（总开关；引擎硬闸与 confirm 机制独立于此）。
    public var mcpWritesEnabled: Bool

    public init(mcpWritesEnabled: Bool = true) {
        self.mcpWritesEnabled = mcpWritesEnabled
    }

    /// 读取配置；文件缺失/损坏时回退默认值（GUI 侧便捷入口）。
    public static func load() -> MCPAppConfig {
        (try? read(from: GSPaths.configFile)) ?? MCPAppConfig()
    }

    /// 指定路径读取（server 侧；每次写工具调用前重读）。
    public static func read(from url: URL) throws -> MCPAppConfig {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(MCPAppConfig.self, from: data)
    }

    /// 原子写入（自动建目录）。
    public func save() throws {
        try GSPaths.ensureDirectory(GSPaths.appSupportRoot)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: GSPaths.configFile, options: .atomic)
    }
}
