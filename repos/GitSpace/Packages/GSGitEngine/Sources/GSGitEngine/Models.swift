import Foundation

// MARK: - 状态

public enum FileChangeKind: String, Sendable, Equatable {
    case modified = "M"
    case added = "A"
    case deleted = "D"
    case renamed = "R"
    case copied = "C"
    case typechange = "T"
    case unmerged = "U"
}

/// 一条文件级改动（`git status --porcelain=v2` 的 1/2/u/? 记录）。
public struct ChangeEntry: Sendable, Equatable, Identifiable {
    public var id: String { path }
    public let path: String
    public let originalPath: String?
    public let indexKind: FileChangeKind?
    public let worktreeKind: FileChangeKind?
    public let isUntracked: Bool

    public init(path: String, originalPath: String? = nil, indexKind: FileChangeKind? = nil, worktreeKind: FileChangeKind? = nil, isUntracked: Bool = false) {
        self.path = path
        self.originalPath = originalPath
        self.indexKind = indexKind
        self.worktreeKind = worktreeKind
        self.isUntracked = isUntracked
    }
}

public struct UnmergedEntry: Sendable, Equatable, Identifiable {
    public var id: String { path }
    public let path: String
    /// UU / AA / DD / AU / UA / DU / UD（与 git status 完全一致）
    public let code: String

    public init(path: String, code: String) {
        self.path = path
        self.code = code
    }
}

/// 单仓状态快照：数据只来自 CLI 输出，不自算（TechStack §10-3）。
public struct RepoStatus: Sendable, Equatable {
    public var headSHA: String?
    public var branch: String?
    public var detached: Bool
    public var upstream: String?
    public var ahead: Int
    public var behind: Int
    public var staged: [ChangeEntry]
    public var unstaged: [ChangeEntry]
    public var untracked: [ChangeEntry]
    public var unmerged: [UnmergedEntry]
    public var isMergeInProgress: Bool

    public init(headSHA: String? = nil, branch: String? = nil, detached: Bool = false, upstream: String? = nil,
                ahead: Int = 0, behind: Int = 0, staged: [ChangeEntry] = [], unstaged: [ChangeEntry] = [],
                untracked: [ChangeEntry] = [], unmerged: [UnmergedEntry] = [], isMergeInProgress: Bool = false) {
        self.headSHA = headSHA
        self.branch = branch
        self.detached = detached
        self.upstream = upstream
        self.ahead = ahead
        self.behind = behind
        self.staged = staged
        self.unstaged = unstaged
        self.untracked = untracked
        self.unmerged = unmerged
        self.isMergeInProgress = isMergeInProgress
    }

    public var dirtyCount: Int { staged.count + unstaged.count + untracked.count }
    public var isClean: Bool { dirtyCount == 0 && unmerged.isEmpty }
    public var hasConflicts: Bool { !unmerged.isEmpty }
    public static let empty = RepoStatus()
}

// MARK: - 提交

public struct CommitInfo: Sendable, Equatable, Identifiable {
    public var id: String { sha }
    public let sha: String
    public let shortSHA: String
    public let authorName: String
    public let authorEmail: String
    public let committerName: String
    public let committerEmail: String
    public let authorTimestamp: Int
    public let committerTimestamp: Int
    public let parents: [String]
    public let decorations: [String]
    public let subject: String
    public let body: String
    public var isMerge: Bool { parents.count > 1 }

    public init(sha: String, shortSHA: String, authorName: String, authorEmail: String,
                committerName: String = "", committerEmail: String = "",
                authorTimestamp: Int, committerTimestamp: Int, parents: [String],
                decorations: [String], subject: String, body: String) {
        self.sha = sha
        self.shortSHA = shortSHA
        self.authorName = authorName
        self.authorEmail = authorEmail
        self.committerName = committerName.isEmpty ? authorName : committerName
        self.committerEmail = committerEmail.isEmpty ? authorEmail : committerEmail
        self.authorTimestamp = authorTimestamp
        self.committerTimestamp = committerTimestamp
        self.parents = parents
        self.decorations = decorations
        self.subject = subject
        self.body = body
    }

    /// author 与 committer 是否为同一人（EP02-F04：不同才显示 committer 行）。
    public var hasDistinctCommitter: Bool {
        committerName != authorName || committerEmail != authorEmail
    }

    /// 从装饰里取展示用分支/标签（HEAD -> x 优先）。
    public var primaryRef: String? {
        if let head = decorations.first(where: { $0.hasPrefix("HEAD -> ") }) {
            return String(head.dropFirst("HEAD -> ".count))
        }
        if let tag = decorations.first(where: { $0.hasPrefix("tag: ") }) {
            return String(tag.dropFirst("tag: ".count))
        }
        return decorations.first
    }
}

// MARK: - 分支 / 标签 / stash

public struct BranchInfo: Sendable, Equatable, Identifiable {
    public var id: String { fullName }
    public let name: String
    public let fullName: String
    public let isCurrent: Bool
    public let upstream: String?
    public let ahead: Int
    public let behind: Int
    public let upstreamGone: Bool
    public let headSHA: String
    public let subject: String
}

public struct RemoteBranchInfo: Sendable, Equatable, Identifiable {
    public var id: String { fullName }
    public let name: String       // origin/feature/x
    public let fullName: String   // refs/remotes/origin/feature/x
    public let remoteName: String
    public let branchName: String // feature/x
    public let headSHA: String
    public let subject: String
}

public struct TagInfo: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public let name: String
    public let shortSHA: String
    public let dateText: String
    public let subject: String
    public let isAnnotated: Bool
}

public struct StashInfo: Sendable, Equatable, Identifiable {
    public var id: String { ref }
    public let ref: String
    public let index: Int
    public let message: String
    public let timestamp: Date
}

// MARK: - diff

public struct DiffLine: Sendable, Equatable {
    public enum Origin: Character, Sendable {
        case add = "+"
        case del = "-"
        case context = " "
        case meta = "\\"
    }

    /// 含前缀的原始行，重组 patch 时逐字还原。
    public let raw: String
    public let origin: Origin
    public var text: String { raw.isEmpty ? "" : String(raw.dropFirst()) }
    /// 旧行号（context / del 行有值，EP03-F02）。
    public var oldNumber: Int?
    /// 新行号（context / add 行有值）。
    public var newNumber: Int?

    public init(raw: String) {
        self.raw = raw
        self.origin = Origin(rawValue: raw.first ?? " ") ?? .context
    }
}

public struct DiffHunk: Sendable, Equatable, Identifiable {
    public var id: Int
    public let header: String
    public let lines: [DiffLine]
    public let additions: Int
    public let deletions: Int

    init(id: Int, header: String, lines: [DiffLine]) {
        self.id = id
        self.header = header
        self.lines = lines
        self.additions = lines.filter { $0.origin == .add }.count
        self.deletions = lines.filter { $0.origin == .del }.count
    }

    public func patchText() -> String {
        header + "\n" + lines.map(\.raw).joined(separator: "\n") + "\n"
    }
}

public struct FileDiff: Sendable, Equatable, Identifiable {
    public var id: String { path }
    public let path: String
    public let originalPath: String?
    public let kind: FileChangeKind
    public let headerLines: [String]
    public let hunks: [DiffHunk]
    public let isBinary: Bool
    public let additions: Int
    public let deletions: Int

    init(path: String, originalPath: String? = nil, kind: FileChangeKind, headerLines: [String], hunks: [DiffHunk], isBinary: Bool = false) {
        self.path = path
        self.originalPath = originalPath
        self.kind = kind
        self.headerLines = headerLines
        self.hunks = hunks
        self.isBinary = isBinary
        self.additions = hunks.reduce(0) { $0 + $1.additions }
        self.deletions = hunks.reduce(0) { $0 + $1.deletions }
    }

    /// 选中 hunk 重组为可 `git apply --cached` 的 patch（TechStack §5.3）。
    public func patch(selectingHunkIDs ids: Set<Int>) -> Data? {
        let selected = hunks.filter { ids.contains($0.id) }
        guard !selected.isEmpty, !isBinary else { return nil }
        var text = headerLines.joined(separator: "\n")
        if !text.isEmpty { text += "\n" }
        for hunk in selected { text += hunk.patchText() }
        return Data(text.utf8)
    }

    public func fullPatch() -> Data? {
        patch(selectingHunkIDs: Set(hunks.map(\.id)))
    }
}

// MARK: - 合并

public enum PullMode: String, Sendable, CaseIterable {
    case fastForwardOnly
    case merge
}

public enum MergeStyle: String, Sendable, CaseIterable {
    case auto
    case fastForwardOnly
    case noFastForward
}

public enum MergeOutcome: Sendable, Equatable {
    case fastForward
    case merged(newSHA: String)
    case upToDate
    case conflicts([UnmergedEntry])
}

public enum ConflictResolution: String, Sendable, CaseIterable {
    case ours       // 取当前
    case theirs     // 取对方
    case mergeMarkers // 生成合并标记，人工编辑后标记解决
}

// MARK: - Blame（EP03-F03）

/// `git blame --porcelain` 输出里的单个提交元数据。
public struct BlameCommitInfo: Sendable, Equatable {
    public let sha: String
    public let shortSHA: String
    public let authorName: String
    public let authorTimestamp: Int
    public let summary: String
    /// boundary 提交（历史窗口之外，git blame --boundary 或初始提交）。
    public let isBoundary: Bool
}

/// 一行 blame 结果。
public struct BlameLine: Sendable, Equatable {
    public let lineNumber: Int
    public let content: String
    /// 归属提交 SHA。
    public let sha: String
    /// 该行是否是同一提交连续区段的首行。
    public let isGroupStart: Bool
}

/// blame 结果：行列表 + 提交元数据表（按 SHA 索引）。
public struct BlameResult: Sendable, Equatable {
    public let lines: [BlameLine]
    public let commits: [String: BlameCommitInfo]

    public init(lines: [BlameLine], commits: [String: BlameCommitInfo]) {
        self.lines = lines
        self.commits = commits
    }
}

// MARK: - 包含于（EP02-F04）

/// 某提交被哪些分支 / tag 包含（`git for-each-ref --contains`）。
public struct ContainsRefs: Sendable, Equatable {
    public let localBranches: [String]
    public let remoteBranches: [String]
    public let tags: [String]

    public init(localBranches: [String] = [], remoteBranches: [String] = [], tags: [String] = []) {
        self.localBranches = localBranches
        self.remoteBranches = remoteBranches
        self.tags = tags
    }

    public var isEmpty: Bool {
        localBranches.isEmpty && remoteBranches.isEmpty && tags.isEmpty
    }
}
