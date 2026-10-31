import Foundation

/// 应用数据目录约定（TechStack §6.2）：
/// `~/Library/Application Support/GitSpace/{workspaces,logs}`。
public enum GSPaths {
    public static var appSupportRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("GitSpace", isDirectory: true)
    }

    public static var workspacesDirectory: URL {
        appSupportRoot.appendingPathComponent("workspaces", isDirectory: true)
    }

    public static var logsDirectory: URL {
        appSupportRoot.appendingPathComponent("logs", isDirectory: true)
    }

    /// 应用配置（GUI 与 MCP server 共读共写）：`{"mcpWritesEnabled": Bool}`。
    public static var configFile: URL {
        appSupportRoot.appendingPathComponent("config.json")
    }

    /// skill 安装清单：记录已装 git-spece 的版本与时间（Story-1031-mcp）。
    public static var skillInstallManifest: URL {
        appSupportRoot.appendingPathComponent("skill-install.json")
    }

    @discardableResult
    public static func ensureDirectory(_ url: URL) throws -> URL {
        var isDirectory: ObjCBool = false
        if !FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } else if !isDirectory.boolValue {
            throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: url.path])
        }
        return url
    }
}
