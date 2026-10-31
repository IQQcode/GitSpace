import Foundation
import GSGitEngine

/// 外部合并工具预设与启动（EP07-F02）。
/// 模板按空白拆参（尊重引号）后逐参替换变量，路径以独立参数传入，不拼接 shell 字符串。
enum ExternalMergeTool: String, CaseIterable, Identifiable {
    case filemerge
    case kaleidoscope
    case vscode
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .filemerge: return "FileMerge（opendiff）"
        case .kaleidoscope: return "Kaleidoscope（ksdiff）"
        case .vscode: return "VS Code（code --wait）"
        case .custom: return "自定义命令"
        }
    }

    /// 命令模板变量：$LOCAL（ours）/ $REMOTE（theirs）/ $BASE / $MERGED。
    var template: String? {
        switch self {
        case .filemerge: return "opendiff $LOCAL $REMOTE -ancestor $BASE -merge $MERGED"
        case .kaleidoscope: return "ksdiff --merge --output $MERGED --base $BASE -- $LOCAL $REMOTE"
        case .vscode: return "code --wait --merge $REMOTE $LOCAL $BASE $MERGED"
        case .custom: return nil
        }
    }

    /// opendiff 立即返回（交给 FileMerge），需轮询 MERGED 文件直到标记清除。
    var returnsImmediately: Bool { self == .filemerge }
}

enum ExternalMergeToolLauncher {
    enum RunResult: Equatable {
        case cleared
        case stillConflicted(markers: Int)
        case timedOut
    }

    /// 模板 → 参数数组；解析失败返回 nil。
    static func resolveArguments(template: String, context: [String: String]) -> [String]? {
        let tokens = tokenize(template)
        guard !tokens.isEmpty else { return nil }
        return tokens.map { token -> String in
            token
                .replacingOccurrences(of: "$LOCAL", with: context["LOCAL"] ?? "")
                .replacingOccurrences(of: "$REMOTE", with: context["REMOTE"] ?? "")
                .replacingOccurrences(of: "$BASE", with: context["BASE"] ?? "")
                .replacingOccurrences(of: "$MERGED", with: context["MERGED"] ?? "")
        }
    }

    /// 尊重双引号的空白分词。
    static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuotes = false
        for character in text {
            switch character {
            case "\"":
                inQuotes.toggle()
            case " ", "\t" where !inQuotes:
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            default:
                current.append(character)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    /// 写三路临时文件并启动工具，等待结果。
    /// - Returns: 工具退出（或轮询结束）后 MERGED 的冲突标记状态。
    static func run(
        template: String,
        mergedPath: URL,
        stages: (base: String?, ours: String?, theirs: String?)
    ) async throws -> RunResult {
        let filename = mergedPath.lastPathComponent
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitSpace-merge-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

        let localURL = workDir.appendingPathComponent("local-\(filename)")
        let remoteURL = workDir.appendingPathComponent("remote-\(filename)")
        try (stages.ours ?? "").write(to: localURL, atomically: true, encoding: .utf8)
        try (stages.theirs ?? "").write(to: remoteURL, atomically: true, encoding: .utf8)
        var baseURL: URL?
        if let base = stages.base {
            let url = workDir.appendingPathComponent("base-\(filename)")
            try base.write(to: url, atomically: true, encoding: .utf8)
            baseURL = url
        }

        let arguments = resolveArguments(template: template, context: [
            "LOCAL": localURL.path,
            "REMOTE": remoteURL.path,
            "BASE": baseURL?.path ?? "",
            "MERGED": mergedPath.path
        ])
        guard let arguments, let executable = arguments.first else {
            throw GitError.failed(exitCode: -1, stderr: "合并工具命令模板无法解析")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env") // PATH 上解析 code/ksdiff 等
        process.arguments = ["-S"] + arguments

        // 立即返回型（opendiff）：轮询 MERGED 文件标记
        if template.trimmingCharacters(in: .whitespaces).hasPrefix("opendiff") {
            try process.run()
            return await pollMarkers(of: mergedPath, timeoutSeconds: 300)
        }

        // 等待退出型
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { _ in
                continuation.resume()
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: GitError.failed(exitCode: -1, stderr: "无法启动合并工具：\(error.localizedDescription)"))
            }
        }
        return markerCount(of: mergedPath) == 0 ? .cleared : .stillConflicted(markers: markerCount(of: mergedPath))
    }

    private static func pollMarkers(of url: URL, timeoutSeconds: Int) async -> RunResult {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        while Date() < deadline {
            if Task.isCancelled { return .timedOut }
            let count = markerCount(of: url)
            if count == 0 { return .cleared }
            try? await Task.sleep(for: .seconds(2))
        }
        return .timedOut
    }

    /// 统计冲突标记（<<<<<<< 行）数量。
    static func markerCount(of url: URL) -> Int {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return 0 }
        return content
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.hasPrefix("<<<<<<<") }
            .count
    }
}
