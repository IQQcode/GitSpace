import Foundation

/// Git 操作错误，按 MRD 10.6 状态表分类（网络 / 鉴权 / 冲突 / 数据 / 取消）。
public enum GitError: Error, Sendable, Equatable {
    case cancelled
    case timeout(seconds: Int)
    case notARepository(path: String)
    case auth(message: String)
    case network(message: String)
    case conflict(message: String)
    case nonFastForward(message: String)
    case uncommittedChanges(message: String)
    case hookFailed(message: String)
    case nothingToCommit
    case noUpstream(branch: String)
    case missingBranch(name: String)
    case unsafeCommand(reason: String)
    case failed(exitCode: Int32, stderr: String)
}

extension GitError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .cancelled: return "操作已取消"
        case .timeout(let seconds): return "操作超时（\(seconds)s）"
        case .notARepository(let path): return "不是 Git 仓库：\(path)"
        case .auth(let message): return "鉴权失败\n\(message)"
        case .network(let message): return "网络错误\n\(message)"
        case .conflict(let message): return "合并冲突\n\(message)"
        case .nonFastForward(let message): return "远端有新提交（非快进）\n\(message)"
        case .uncommittedChanges(let message): return "工作区有未提交改动\n\(message)"
        case .hookFailed(let message): return "钩子执行失败（提交未产生）\n\(message)"
        case .nothingToCommit: return "没有可提交的内容"
        case .noUpstream(let branch): return "分支 \(branch) 未配置上游"
        case .missingBranch(let name): return "分支或引用不存在：\(name)"
        case .unsafeCommand(let reason): return "命令被安全闸拦截：\(reason)"
        case .failed(let code, let stderr): return "git 退出码 \(code)\n\(stderr)"
        }
    }
}

public extension GitError {
    /// 仅网络类错误允许自动重试 1 次（MRD 12）；鉴权/非快进等语义错误绝不重试。
    var isNetworkError: Bool {
        switch self {
        case .network, .timeout: return true
        default: return false
        }
    }

    /// 从 git 的 stderr/stdout 归类失败原因（只做关键词匹配，不吞错）。
    static func classify(output: GitOutput, arguments: [String]) -> GitError {
        let text = output.stderr + "\n" + output.stdout
        let lowered = text.lowercased()
        if lowered.contains("not a git repository") {
            return .notARepository(path: "")
        }
        if arguments.first == "commit" {
            if lowered.contains("nothing to commit") { return .nothingToCommit }
            // 提交失败优先怀疑钩子：原始输出原样带出（MRD 10.2-C 不吞错）
            return .hookFailed(message: text)
        }
        if lowered.contains("conflict") || lowered.contains("automatic merge failed") {
            return .conflict(message: text)
        }
        if lowered.contains("[rejected]") || lowered.contains("non-fast-forward") {
            return .nonFastForward(message: text)
        }
        if lowered.contains("your local changes") || lowered.contains("would be overwritten")
            || lowered.contains("please commit your changes or stash them")
            || lowered.contains("cannot pull with rebase") {
            return .uncommittedChanges(message: text)
        }
        if lowered.contains("no upstream configured") || lowered.contains("has no upstream branch")
            || lowered.contains("no tracking information") {
            return .noUpstream(branch: arguments.last ?? "")
        }
        if lowered.contains("permission denied (publickey") || lowered.contains("authentication failed")
            || lowered.contains("could not read username") || lowered.contains("terminal prompts disabled") {
            return .auth(message: text)
        }
        if lowered.contains("could not resolve host") || lowered.contains("failed to connect")
            || lowered.contains("connection refused") || lowered.contains("connection reset")
            || lowered.contains("operation timed out") || lowered.contains("the remote end hung up") {
            return .network(message: text)
        }
        if lowered.contains("did not match any file(s) known to git") || lowered.contains("unknown revision")
            || lowered.contains("bad revision") {
            return .missingBranch(name: arguments.last ?? "")
        }
        return .failed(exitCode: output.exitCode, stderr: output.stderr.isEmpty ? output.stdout : output.stderr)
    }
}
