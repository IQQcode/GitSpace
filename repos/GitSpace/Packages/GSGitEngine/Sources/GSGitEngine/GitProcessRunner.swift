import Foundation
import GSInfra

public struct GitOutput: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public var succeeded: Bool { exitCode == 0 }

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public struct GitExecutionOptions: Sendable {
    public var timeoutSeconds: Int
    public var stdin: Data?
    public var retriesOnNetworkError: Int

    public init(timeoutSeconds: Int = 60, stdin: Data? = nil, retriesOnNetworkError: Int = 0) {
        self.timeoutSeconds = timeoutSeconds
        self.stdin = stdin
        self.retriesOnNetworkError = retriesOnNetworkError
    }

    /// 本地快速只读命令。
    public static let quick = GitExecutionOptions(timeoutSeconds: 20)
    /// 网络命令：60s 单仓超时 + 网络类错误自动重试 1 次（MRD 12）。
    public static let network = GitExecutionOptions(timeoutSeconds: 60, retriesOnNetworkError: 1)
}

/// git 进程执行器（actor）：统一超时、取消、重试与安全闸（TechStack §5.2）。
public actor GitProcessRunner {
    public static let shared = GitProcessRunner()

    public let gitExecutable: URL

    public init(gitExecutable: URL? = nil) {
        self.gitExecutable = gitExecutable ?? GitProcessRunner.locateGit()
    }

    private static func locateGit() -> URL {
        let candidates = [
            "/usr/bin/git", "/opt/homebrew/bin/git", "/usr/local/bin/git"
        ]
        if let hit = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return URL(fileURLWithPath: hit)
        }
        return URL(fileURLWithPath: "/usr/bin/git")
    }

    public func gitVersion() async throws -> String {
        let output = try await runRaw(
            directory: URL(fileURLWithPath: "/"),
            arguments: ["--version"],
            options: GitExecutionOptions(timeoutSeconds: 10)
        )
        let text = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.hasPrefix("git version ") ? String(text.dropFirst("git version ".count)) : text
    }

    /// 执行并归类非零退出为 GitError。合法非零退出的命令请用 runRaw。
    public func run(directory: URL, arguments: [String], options: GitExecutionOptions = .quick) async throws -> GitOutput {
        let output = try await runRaw(directory: directory, arguments: arguments, options: options)
        guard output.succeeded else {
            throw GitError.classify(output: output, arguments: arguments)
        }
        return output
    }

    /// 执行并原样返回退出码（不抛业务错误）；仅在取消 / 超时 / 启动失败时抛错。
    public func runRaw(directory: URL, arguments: [String], options: GitExecutionOptions = .quick) async throws -> GitOutput {
        try Self.validate(arguments)

        var attempt = 0
        while true {
            attempt += 1
            do {
                return try await runOnce(directory: directory, arguments: arguments, options: options)
            } catch {
                guard let gitError = error as? GitError,
                      gitError.isNetworkError,
                      attempt <= options.retriesOnNetworkError,
                      !Task.isCancelled
                else { throw error }
                continue
            }
        }
    }

    private func runOnce(directory: URL, arguments: [String], options: GitExecutionOptions) async throws -> GitOutput {
        let process = Process()
        process.executableURL = gitExecutable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        var environment = ProcessInfo.processInfo.environment
        // 环境透传（MRD 12）：PATH/SSH_AUTH_SOCK/代理配置原样继承；仅关掉交互提示。
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_PAGER"] = "cat"
        environment["LC_ALL"] = "C"
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            if let input = options.stdin {
                let inputPipe = Pipe()
                process.standardInput = inputPipe
                try process.run()
                let writer = inputPipe.fileHandleForWriting
                Task.detached(priority: .utility) {
                    do { try writer.write(contentsOf: input) } catch {}
                    try? writer.close()
                }
            } else {
                process.standardInput = FileHandle.nullDevice
                try process.run()
            }
        } catch {
            throw GitError.failed(exitCode: -1, stderr: "无法启动 git 进程：\(error.localizedDescription)")
        }

        // 管道必须与进程运行并行读，避免输出超 64KB 死锁。
        async let outData: Data? = stdoutPipe.fileHandleForReading.readToEnd()
        async let errData: Data? = stderrPipe.fileHandleForReading.readToEnd()

        let startedAt = Date()
        let exitCode: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
                let box = OnceBox(continuation)
                process.terminationHandler = { terminated in
                    box.resume(returning: terminated.terminationStatus)
                }
                let timeoutSeconds = options.timeoutSeconds
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds) * 1_000_000_000)
                    if process.isRunning { process.terminate() }
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }

        let out = (try? await outData) ?? Data()
        let err = (try? await errData) ?? Data()

        if Task.isCancelled { throw GitError.cancelled }
        let elapsed = Date().timeIntervalSince(startedAt)
        if exitCode == Int32(SIGTERM), elapsed >= Double(options.timeoutSeconds) - 0.5 {
            throw GitError.timeout(seconds: options.timeoutSeconds)
        }

        let output = GitOutput(
            exitCode: exitCode,
            stdout: String(decoding: out, as: UTF8.self),
            stderr: String(decoding: err, as: UTF8.self)
        )
        return output
    }

    // MARK: 安全闸（MRD 10.2-G：引擎层硬闸）

    /// 白名单外不放行：引擎内永远不存在 force push / reset --hard / clean 的调用路径。
    public static func validate(_ arguments: [String]) throws {
        if let pushIndex = arguments.firstIndex(of: "push") {
            for arg in arguments.dropFirst(pushIndex + 1) where arg.hasPrefix("--force") {
                throw GitError.unsafeCommand(reason: "永不提供 force push（MRD 10.2-G）")
            }
        }
        if arguments.contains("reset"), arguments.contains("--hard") {
            throw GitError.unsafeCommand(reason: "reset --hard 未开放：丢弃改动走 git restore 逐文件路径")
        }
        if arguments.contains("clean") {
            throw GitError.unsafeCommand(reason: "clean 未开放：未跟踪文件逐个删除并二次确认")
        }
        if arguments.contains("-f") {
            throw GitError.unsafeCommand(reason: "引擎调用路径不接受 -f（force）参数")
        }
    }
}

/// continuation 恰好恢复一次的守卫（terminationHandler / 超时 / 取消可能竞争）。
final class OnceBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Int32, Error>?
    private var consumed = false

    init(_ continuation: CheckedContinuation<Int32, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: Int32) {
        lock.lock()
        let taken = consumed
        consumed = true
        let continuation = self.continuation
        lock.unlock()
        if !taken { continuation?.resume(returning: value) }
    }

    func resume(throwing error: Error) {
        lock.lock()
        let taken = consumed
        consumed = true
        let continuation = self.continuation
        lock.unlock()
        if !taken { continuation?.resume(throwing: error) }
    }
}
