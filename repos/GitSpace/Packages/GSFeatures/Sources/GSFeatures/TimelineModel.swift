import Foundation
import Observation
import GSGitEngine
import GSIndex

/// 跨仓统一时间线（MRD 10.6 流程二：过滤 → 详情）。
@MainActor
@Observable
public final class TimelineModel {
    public enum DateRange: String, CaseIterable {
        case all = "全部时间"
        case today = "今天"
        case week = "近 7 天"
        case month = "近 30 天"

        var cutoffInterval: TimeInterval? {
            let days: Int
            switch self {
            case .all: return nil
            case .today: days = 1
            case .week: days = 7
            case .month: days = 30
            }
            return TimeInterval(days * 24 * 3600)
        }
    }

    public struct Filters: Equatable {
        public var repoPath: String?
        public var author: String?
        public var branch: String?
        public var text: String = ""
        public var dateRange: DateRange = .all

        public init() {}

        public var isDefault: Bool {
            repoPath == nil && author == nil && branch == nil && text.isEmpty && dateRange == .all
        }

        public func matches(_ commit: TimelineCommit, now: Date = Date()) -> Bool {
            if let repoPath, commit.repoPath != repoPath { return false }
            if let author, commit.commit.authorName != author { return false }
            if let branch, !branch.isEmpty {
                let hit = commit.commit.decorations.contains { $0.localizedCaseInsensitiveContains(branch) }
                if !hit { return false }
            }
            if let cutoff = dateRange.cutoffInterval {
                if Double(commit.commit.committerTimestamp) < now.timeIntervalSince1970 - cutoff { return false }
            }
            let query = text.trimmingCharacters(in: .whitespaces)
            if !query.isEmpty {
                let haystack = [
                    commit.commit.subject,
                    commit.commit.sha,
                    commit.commit.shortSHA,
                    commit.commit.authorName,
                    commit.repoName,
                    commit.commit.body
                ].joined(separator: " ")
                if !haystack.localizedCaseInsensitiveContains(query) { return false }
            }
            return true
        }
    }

    public private(set) var commits: [TimelineCommit] = []
    public var filters = Filters()
    public var isLoading = false
    public private(set) var authors: [String] = []
    public private(set) var branchOptions: [String] = []
    public private(set) var truncatedRepos: [String] = []
    public var selectedCommit: TimelineCommit?
    public private(set) var selectedFiles: [FileDiff] = []
    public private(set) var isLoadingDetail = false
    public var perRepoLimit: Int = 800

    public init() {}

    public var filtered: [TimelineCommit] {
        commits.filter { filters.matches($0) }
    }

    public func resetFilters() {
        filters = Filters()
    }

    /// 时间窗口来自 AppModel 设置（默认近 3 个月，MRD 10.6 超大仓截断策略）。
    public func reload(app: AppModel) async {
        isLoading = true
        defer { isLoading = false }
        let since = Calendar.current.date(byAdding: .day, value: -app.timelineWindowDays, to: Date())
        let limit = perRepoLimit
        let repos = app.repos

        var perRepo: [(name: String, path: String, commits: [CommitInfo])] = []
        var truncated: [String] = []
        await withTaskGroup(of: (ManagedRepo, [CommitInfo]).self) { group in
            for repo in repos {
                group.addTask {
                    guard let engine = repo.engine else { return (repo, []) }
                    let commits = (try? await engine.commits(limit: limit, since: since)) ?? []
                    return (repo, commits)
                }
            }
            for await (repo, commits) in group {
                perRepo.append((repo.displayName, repo.config.path, commits))
                if commits.count >= limit { truncated.append(repo.displayName) }
            }
        }
        commits = TimelineAggregator.build(repos: perRepo)
        truncatedRepos = truncated
        authors = Array(Set(commits.map { $0.commit.authorName })).sorted { $0.localizedCompare($1) == .orderedAscending }
        branchOptions = Array(Set(
            commits.flatMap { $0.commit.decorations }
                .filter { !$0.hasPrefix("HEAD") && !$0.hasPrefix("tag:") }
        )).sorted { $0.localizedCompare($1) == .orderedAscending }
        if let selected = selectedCommit, !commits.contains(where: { $0.id == selected.id }) {
            selectedCommit = nil
            selectedFiles = []
        }
    }

    public func select(_ commit: TimelineCommit?, app: AppModel) async {
        selectedCommit = commit
        selectedFiles = []
        guard let commit,
              let repo = app.repos.first(where: { $0.config.path == commit.repoPath }),
              let engine = repo.engine
        else { return }
        isLoadingDetail = true
        defer { isLoadingDetail = false }
        selectedFiles = (try? await engine.commitDetail(sha: commit.commit.sha)) ?? []
    }
}
