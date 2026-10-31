import Foundation

/// git-space skill 安装器（Story-1031-mcp）：
/// - 源：App Bundle 内的 Skill 资源（SPM `resources: [.copy("Skill")]`）；
/// - 目标：`~/.agents/skills/git-space/`（skill-unify SSOT 路径，本机各 Agent 平台可发现）；
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

        public var description: String {
            switch self {
            case .sourceMissing(let path): return "skill 源不存在：\(path)"
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
        // /var 与 /private/var 等符号链接会让 path 前缀不一致，先统一解析。
        let sourcePath = sourceDirectory.resolvingSymlinksInPath().path
        for case let fileURL as URL in enumerator {
            guard let isRegular = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile, isRegular else { continue }
            let resolved = fileURL.resolvingSymlinksInPath().path
            guard resolved.hasPrefix(sourcePath + "/") else { continue }
            let relative = String(resolved.dropFirst(sourcePath.count + 1))
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

    /// 解析 SKILL.md frontmatter 里的 `version: x.y.z`（限定 `---` 围栏内，避免误读正文）。
    public static func skillVersion(at skillMarkdown: URL) -> String? {
        guard let text = try? String(contentsOf: skillMarkdown, encoding: .utf8) else { return nil }
        var inFrontmatter = false
        var fenceCount = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" {
                fenceCount += 1
                inFrontmatter = fenceCount == 1
                if fenceCount >= 2 { break }
                continue
            }
            guard inFrontmatter else { continue }
            if trimmed.hasPrefix("version:") {
                return trimmed.dropFirst("version:".count)
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    /// 默认目标目录：`~/.agents/skills/git-space`（skill-unify SSOT）。
    public static var defaultTargetDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".agents/skills/git-space", isDirectory: true)
    }

    /// Bundle 内 skill 源目录。
    /// SPM 资源会产出独立 bundle（GitSpace_GSMCP.bundle）：swift run/测试时 Bundle.module 可直接定位；
    /// 打包 .app 时该 bundle 位于 Contents/Resources 下——手动查找而非用 Bundle.module，
    /// 避免资源 bundle 缺失时资源访问器 fatalError（P0-1 的保险丝）。
    public static func bundleSkillDirectory(bundle: Bundle? = nil) -> URL? {
        let fs = FileManager.default
        var searchRoots: [URL] = []
        if let bundle {
            if let resourceURL = bundle.resourceURL { searchRoots.append(resourceURL) }
        } else {
            // Bundle.module 仅在资源 bundle 存在时可访问，不能直接触碰；从可推路径找。
            if let main = Bundle.main.resourceURL { searchRoots.append(main) }
            if let executableURL = Bundle.main.executableURL {
                searchRoots.append(executableURL.deletingLastPathComponent())        // swift run: .build/<config>/
                searchRoots.append(executableURL.deletingLastPathComponent().appendingPathComponent("GitSpace_GSMCP.bundle"))
            }
        }
        for root in searchRoots {
            let direct = root.appendingPathComponent("Skill", isDirectory: true)
            if fs.fileExists(atPath: direct.path) { return direct }
            let nested = root.appendingPathComponent("Contents/Resources/Skill", isDirectory: true)
            if fs.fileExists(atPath: nested.path) { return nested }
            let nestedBundle = root.appendingPathComponent("GitSpace_GSMCP.bundle", isDirectory: true)
            if fs.fileExists(atPath: nestedBundle.path),
               let inner = Bundle(url: nestedBundle)?.resourceURL {
                let skill = inner.appendingPathComponent("Skill", isDirectory: true)
                if fs.fileExists(atPath: skill.path) { return skill }
            }
        }
        return nil
    }
}
