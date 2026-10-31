import Foundation
import GSGitEngine

/// 按卡片号聚合跨仓提交（变更集与聚合检索共用）。纯逻辑，不 import SwiftUI。
/// 卡片号口径：字母开头、前缀可内嵌数字，连字符，至少 3 位数字；大小写不敏感，多卡号取首个。
public struct CardGroup: Identifiable, Sendable {
    public var id: String { card }
    public let card: String              // 卡片号；空串表示未关联卡片
    public let commits: [TimelineCommit]
    public let repoNames: [String]       // 去重并排序后涉及的仓库
    public let authorCount: Int
    public let latestTimestamp: Int
}

public enum CardAggregator {
    private static let pattern = #"[A-Za-z][A-Za-z0-9]*-[0-9]{3,}"#

    /// 从 subject 与 body 中提取首个卡片号，无则返回 nil。
    public static func extractCard(subject: String, body: String) -> String? {
        let text = subject + " " + body
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let matched = Range(match.range, in: text) else { return nil }
        return String(text[matched])
    }

    /// 按卡片号分组跨仓提交，无卡号归入空串分组，结果按最新提交时间倒序。
    public static func group(_ commits: [TimelineCommit]) -> [CardGroup] {
        var buckets: [String: [TimelineCommit]] = [:]
        var order: [String] = []
        for item in commits {
            let card = extractCard(subject: item.commit.subject, body: item.commit.body) ?? ""
            if buckets[card] == nil { order.append(card) }
            buckets[card, default: []].append(item)
        }
        let groups = order.map { key -> CardGroup in
            let items = buckets[key] ?? []
            let repoNames = Array(Set(items.map(\.repoName))).sorted()
            let authorCount = Set(items.map(\.commit.authorName)).count
            let latest = items.map(\.commit.committerTimestamp).max() ?? 0
            return CardGroup(card: key, commits: items, repoNames: repoNames, authorCount: authorCount, latestTimestamp: latest)
        }
        return groups.sorted { $0.latestTimestamp > $1.latestTimestamp }
    }
}
