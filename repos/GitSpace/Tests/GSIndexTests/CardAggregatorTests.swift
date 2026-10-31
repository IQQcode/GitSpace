import Testing
import Foundation
import GSIndex
import GSGitEngine

@Suite("CardAggregator")
struct CardAggregatorTests {
    private func mkCommit(_ sha: String, _ subject: String, body: String = "", author: String = "陈默", ts: Int) -> CommitInfo {
        CommitInfo(sha: sha, shortSHA: String(sha.prefix(7)), authorName: author, authorEmail: "a@b.com",
                   authorTimestamp: ts, committerTimestamp: ts, parents: [], decorations: [], subject: subject, body: body)
    }

    @Test func extractsCardInVariousForms() {
        #expect(CardAggregator.extractCard(subject: "tieba02-88421 修复话题卡", body: "") == "tieba02-88421")
        #expect(CardAggregator.extractCard(subject: "[Story] TASK-123456 做功能", body: "") == "TASK-123456")
        #expect(CardAggregator.extractCard(subject: "大小写 task-7788 也命中", body: "") == "task-7788")
        #expect(CardAggregator.extractCard(subject: "无卡号的提交", body: "") == nil)
        #expect(CardAggregator.extractCard(subject: "正文里有", body: "详见 ABC-999 说明") == "ABC-999")
        #expect(CardAggregator.extractCard(subject: "A-111 然后 B-222", body: "") == "A-111")
    }

    @Test func groupsAcrossReposSortedByLatest() {
        let base = 1_700_000_000
        let repoA = [
            mkCommit("a1aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "TASK-100 旧", ts: base + 10),
            mkCommit("a2aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "TASK-200 新", ts: base + 90)
        ]
        let repoB = [
            mkCommit("b1bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "TASK-100 另一仓", author: "林子涵", ts: base + 50),
            mkCommit("b2bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "无卡号提交", ts: base + 20)
        ]
        let commits = TimelineAggregator.build(repos: [
            ("GdHome", "/tmp/home", repoA),
            ("GdThread", "/tmp/thread", repoB)
        ])
        let groups = CardAggregator.group(commits)
        #expect(groups.map(\.card) == ["TASK-200", "TASK-100", ""])
        let task100 = groups.first { $0.card == "TASK-100" }
        #expect(task100?.repoNames == ["GdHome", "GdThread"])
        #expect(task100?.commits.count == 2)
        #expect(task100?.authorCount == 2)
    }
}
