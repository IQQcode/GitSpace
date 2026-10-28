import Foundation
import GSGitEngine

/// 跨仓统一时间线的一行：提交元数据 + 所属仓库信息。
public struct TimelineCommit: Sendable, Identifiable, Equatable {
    public var id: String { commit.sha + "@" + repoName }
    public let commit: CommitInfo
    public let repoName: String
    public let repoPath: String
    public let colorSlot: Int
    /// MVP 布局：每仓一条 lane（真实跨仓 DAG lane 布局在 P1 预计算）。
    public let lane: Int
}

/// 把多个仓库的提交合并为一条按时间排序的时间线（MRD §9 产品内核）。
public enum TimelineAggregator {
    public static func build(repos: [(name: String, path: String, commits: [CommitInfo])]) -> [TimelineCommit] {
        let laneByRepo = Dictionary(uniqueKeysWithValues: repos.enumerated().map { ($0.element.name, $0.offset) })
        var merged: [TimelineCommit] = []
        merged.reserveCapacity(repos.reduce(0) { $0 + $1.commits.count })
        for repo in repos {
            let slot = laneByRepo[repo.name] ?? 0
            for commit in repo.commits {
                merged.append(TimelineCommit(
                    commit: commit,
                    repoName: repo.name,
                    repoPath: repo.path,
                    colorSlot: slot,
                    lane: slot
                ))
            }
        }
        return merged.sorted { lhs, rhs in
            if lhs.commit.committerTimestamp != rhs.commit.committerTimestamp {
                return lhs.commit.committerTimestamp > rhs.commit.committerTimestamp
            }
            return lhs.commit.sha < rhs.commit.sha
        }
    }
}
