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
