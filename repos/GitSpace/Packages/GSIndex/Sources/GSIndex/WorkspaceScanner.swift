import Foundation

/// 父目录扫描发现的仓库（MRD 10.6 流程一）。
public struct DiscoveredRepo: Sendable, Identifiable, Equatable {
    public var id: String { path.path }
    public let path: URL
    public let name: String
    public let alreadyManaged: Bool
}

/// 父目录递归发现 Git 仓库（.git 目录或文件——含 worktree / submodule）。
/// 构建产物目录不下钻，控制 50+ 仓冷扫描预算（TechStack §10-1）。
public enum WorkspaceScanner {
    public static let defaultSkipDirectories: Set<String> = [
        "node_modules", "build", "Build", "Pods", "DerivedData", ".build",
        "dist", "target", "Carthage", "vendor", ".cache", "tmp", "Release", "Debug"
    ]

    public static func scan(parent: URL, knownPaths: Set<String>, maxDepth: Int = 3) throws -> [DiscoveredRepo] {
        let fileManager = FileManager.default
        var discovered: [DiscoveredRepo] = []

        func walk(directory: URL, depth: Int) {
            let contents = (try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            )) ?? []
            for item in contents {
                let name = item.lastPathComponent
                if name.hasPrefix(".") { continue }
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: item.path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
                if fileManager.fileExists(atPath: item.appendingPathComponent(".git").path) {
                    if !discovered.contains(where: { $0.id == item.path }) {
                        discovered.append(DiscoveredRepo(
                            path: item,
                            name: name,
                            alreadyManaged: knownPaths.contains(item.path)
                        ))
                    }
                    // 仓库内部不再下钻：submodule 由纳管清单管理
                    continue
                }
                if depth < maxDepth && !defaultSkipDirectories.contains(name) {
                    walk(directory: item, depth: depth + 1)
                }
            }
        }

        walk(directory: parent, depth: 1)
        return discovered.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }
}
