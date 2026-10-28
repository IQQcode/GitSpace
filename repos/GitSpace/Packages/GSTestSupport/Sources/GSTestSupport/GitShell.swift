import Foundation

/// 同步 shell 封装：fixture 仓生成与命令行基准执行（等价性测试用）。
public enum GitShell {
    @discardableResult
    public static func run(_ workDir: URL, _ arguments: String...) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = workDir

        var environment = ProcessInfo.processInfo.environment
        environment["GIT_AUTHOR_NAME"] = "Tester"
        environment["GIT_AUTHOR_EMAIL"] = "tester@example.com"
        environment["GIT_COMMITTER_NAME"] = "Tester"
        environment["GIT_COMMITTER_EMAIL"] = "tester@example.com"
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["LC_ALL"] = "C"
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw ShellError(command: arguments.joined(separator: " "), output: output)
        }
        return output
    }

    public struct ShellError: Error, CustomStringConvertible {
        public let command: String
        public let output: String
        public var description: String { "git \(command) 失败：\n\(output)" }
    }
}
