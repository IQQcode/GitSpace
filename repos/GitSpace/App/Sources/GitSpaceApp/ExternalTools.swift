import Foundation
import GSGitEngine

// 在终端 / 编辑器打开（EP09-F01）：预设应用探测 + 自定义命令模板（$REPO/$FILE/$LINE）。

// MARK: - 终端

enum ExternalTerminal: String, CaseIterable, Identifiable {
    case terminal
    case iterm2
    case ghostty
    case warp
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .terminal: return "Terminal（系统终端）"
        case .iterm2: return "iTerm2"
        case .ghostty: return "Ghostty"
        case .warp: return "Warp"
        case .custom: return "自定义命令"
        }
    }

    /// `open -a` 使用的应用名（custom 为 nil）。
    var appName: String? {
        switch self {
        case .terminal: return "Terminal"
        case .iterm2: return "iTerm"
        case .ghostty: return "Ghostty"
        case .warp: return "Warp"
        case .custom: return nil
        }
    }
}

// MARK: - 编辑器

enum ExternalEditor: String, CaseIterable, Identifiable {
    case xcode
    case vscode
    case cursor
    case zed
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .xcode: return "Xcode（xed）"
        case .vscode: return "VS Code"
        case .cursor: return "Cursor"
        case .zed: return "Zed"
        case .custom: return "自定义命令"
        }
    }

    /// CLI 可执行文件候选路径（存在性探测）。
    var cliCandidates: [String] {
        switch self {
        case .xcode: return ["/usr/bin/xed"]
        case .vscode: return ["/opt/homebrew/bin/code", "/usr/local/bin/code", "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"]
        case .cursor: return ["/opt/homebrew/bin/cursor", "/usr/local/bin/cursor"]
        case .zed: return ["/opt/homebrew/bin/zed", "/usr/local/bin/zed", "/Applications/Zed.app/Contents/MacOS/cli"]
        case .custom: return []
        }
    }

    /// `open -a` 的兜底应用名。
    var appName: String? {
        switch self {
        case .xcode: return "Xcode"
        case .vscode: return "Visual Studio Code"
        case .cursor: return "Cursor"
        case .zed: return "Zed"
        case .custom: return nil
        }
    }
}

// MARK: - 启动器

enum ExternalToolsLauncher {
    /// 应用是否已安装（/Applications 或 CLI 候选存在）。
    static func isAvailable(editor: ExternalEditor) -> Bool {
        editor.cliCandidates.contains { FileManager.default.isExecutableFile(atPath: $0) }
            || (editor.appName.map { isAppInstalled($0) } ?? false)
    }

    static func isAvailable(terminal: ExternalTerminal) -> Bool {
        guard let name = terminal.appName else { return true }
        return isAppInstalled(name)
    }

    private static func isAppInstalled(_ name: String) -> Bool {
        let system = "/System/Applications/\(name).app"
        let systemUtilities = "/System/Applications/Utilities/\(name).app"
        let user = "/Applications/\(name).app"
        return [system, systemUtilities, user].contains { FileManager.default.fileExists(atPath: $0) }
            || name == "Terminal" // 系统终端恒可用
    }

    /// 在终端打开仓库目录（验收：终端工作目录 = 仓库路径，EP09-F01）。
    static func openInTerminal(_ terminal: ExternalTerminal, repoPath: URL, customTemplate: String) throws {
        if terminal == .custom {
            try runCustom(
                template: customTemplate,
                context: ["REPO": repoPath.path, "FILE": "", "LINE": ""],
                fallbackError: "请先在设置中配置终端命令模板"
            )
            return
        }
        guard let appName = terminal.appName else { return }
        try runProcess("/usr/bin/open", ["-a", appName, repoPath.path])
    }

    /// 在编辑器打开仓库或文件（文件可定位行）。
    static func openInEditor(
        _ editor: ExternalEditor,
        repoPath: URL,
        file: URL? = nil,
        line: Int? = nil,
        customTemplate: String
    ) throws {
        if editor == .custom {
            try runCustom(
                template: customTemplate,
                context: [
                    "REPO": repoPath.path,
                    "FILE": file?.path ?? "",
                    "LINE": line.map(String.init) ?? ""
                ],
                fallbackError: "请先在设置中配置编辑器命令模板"
            )
            return
        }
        // 文件 + 行：优先 CLI 定位（xed --line / code --goto file:line / zed file:line）
        if let file {
            if let cli = editor.cliCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
                switch editor {
                case .xcode:
                    var args = ["--line", String(line ?? 1)]
                    args.append(file.path)
                    try runProcess(cli, args)
                    return
                case .vscode, .cursor:
                    let goto = line.map { "\(file.path):\($0)" } ?? file.path
                    try runProcess(cli, ["--goto", goto])
                    return
                case .zed:
                    let target = line.map { "\(file.path):\($0)" } ?? file.path
                    try runProcess(cli, [target])
                    return
                case .custom:
                    break
                }
            }
            if let appName = editor.appName, isAppInstalled(appName) {
                try runProcess("/usr/bin/open", ["-a", appName, file.path])
                return
            }
            throw GitError.failed(exitCode: -1, stderr: "未找到 \(editor.displayName)，请安装或在设置中配置自定义命令")
        }
        // 目录：CLI 或 open -a
        if let cli = editor.cliCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            try runProcess(cli, [repoPath.path])
        } else if let appName = editor.appName {
            try runProcess("/usr/bin/open", ["-a", appName, repoPath.path])
        } else {
            throw GitError.failed(exitCode: -1, stderr: "未找到 \(editor.displayName)")
        }
    }

    /// 自定义模板：按空白拆参（尊重引号）+ 变量替换，经 env -S 执行。
    private static func runCustom(template: String, context: [String: String], fallbackError: String) throws {
        let tokens = ExternalMergeToolLauncher.resolveArguments(template: template, context: context) ?? []
        guard !tokens.isEmpty else {
            throw GitError.failed(exitCode: -1, stderr: fallbackError)
        }
        // 首个 token 是可执行名，交给 env 在 PATH 上解析
        let command = tokens.joined(separator: " ")
        try runProcess("/usr/bin/env", ["-S", command])
    }

    private static func runProcess(_ launchPath: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        // fire and forget：工具自身管理窗口与生命周期
    }
}
