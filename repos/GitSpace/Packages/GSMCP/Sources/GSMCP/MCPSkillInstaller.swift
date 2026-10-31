import Foundation

/// git-spece skill 安装器（Story-1031-mcp）：
/// - 源：App Bundle 内的 Skill 资源（SPM `resources: [.copy("Skill")]`）；
/// - 目标：`~/.agents/skills/git-spece/`（skill-unify SSOT 路径，本机各 Agent 平台可发现）；
/// - 更新判断：SKILL.md frontmatter 的 version 与 skill-install.json 清单比对；
/// - 只覆盖源里存在的文件，目标目录内用户自加的文件一律不动。
public enum MCPSkillInstaller {
    public struct Manifest: Codable, Sendable, Equatable {
        public var version: String
        public var installedAt: Date

        public init(version: String, installedAt: Date) {
            self.version = version
            self.installedAt = installedAt
        }
    }

    public enum InstallError: Error, CustomStringConvertible {
        case sourceMissing(String)
        case targetNotWritable(String)

        public var description: String {
            switch self {
            case .sourceMissing(let path): return "skill 源不存在：\(path)"
            case .targetNotWritable(let path): return "skill 目标目录不可写：\(path)"
            }
        }
    }

    /// 装入 SSOT。返回是否发生了安装/更新。
    @discardableResult
    public static func installIfNeeded(
        sourceDirectory: URL,
        targetDirectory: URL,
        manifestFile: URL,
        force: Bool = false,
        now: Date = Date()
    ) throws -> Bool {
        guard FileManager.default.fileExists(atPath: sourceDirectory.appendingPathComponent("SKILL.md").path) else {
            throw InstallError.sourceMissing(sourceDirectory.path)
        }
        let version = skillVersion(at: sourceDirectory.appendingPathComponent("SKILL.md")) ?? "0"

        if !force {
            let manifest = installedManifest(at: manifestFile)
            let alreadyInstalled = manifest?.version == version
                && FileManager.default.fileExists(atPath: targetDirectory.appendingPathComponent("SKILL.md").path)
            if alreadyInstalled { return false }
        }

        let fs = FileManager.default
        try fs.createDirectory(at: targetDirectory, withIntermediateDirectories: true)

        // 递归拷贝源目录内全部文件（保持相对路径）；目标里多出来的用户文件不删。
        guard let enumerator = fs.enumerator(at: sourceDirectory, includingPropertiesForKeys: [.isRegularFileKey]) else {
            throw InstallError.sourceMissing(sourceDirectory.path)
        }
        for case let fileURL as URL in enumerator {
            guard let isRegular = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile, isRegular else { continue }
            let relative = fileURL.path.replacingOccurrences(of: sourceDirectory.path + "/", with: "")
            let destination = targetDirectory.appendingPathComponent(relative)
            try fs.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fs.removeItem(at: destination)
            try fs.copyItem(at: fileURL, to: destination)
        }

        let manifest = Manifest(version: version, installedAt: now)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: manifestFile, options: .atomic)
        return true
    }

    /// 已装版本（无清单时 nil）。
    public static func installedManifest(at manifestFile: URL) -> Manifest? {
        guard let data = try? Data(contentsOf: manifestFile) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Manifest.self, from: data)
    }

    /// 解析 SKILL.md frontmatter 里的 `version: x.y.z`（宽松匹配首个 version 键）。
    public static func skillVersion(at skillMarkdown: URL) -> String? {
        guard let text = try? String(contentsOf: skillMarkdown, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("version:") {
                return trimmed.dropFirst("version:".count)
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    /// 默认目标目录：`~/.agents/skills/git-spece`（skill-unify SSOT）。
    public static var defaultTargetDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".agents/skills/git-spece", isDirectory: true)
    }

    /// Bundle 内 skill 源目录（SPM .copy 资源位于 bundle 根的 Skill/ 下）。
    public static func bundleSkillDirectory(bundle: Bundle? = nil) -> URL? {
        let resolved = bundle ?? .module
        let candidate = resolved.resourceURL?.appendingPathComponent("Skill", isDirectory: true)
        guard let candidate, FileManager.default.fileExists(atPath: candidate.path) else { return nil }
        return candidate
    }
}
