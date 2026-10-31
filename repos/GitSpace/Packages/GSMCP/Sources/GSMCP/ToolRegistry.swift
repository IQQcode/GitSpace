import Foundation

/// MCP 工具元数据（tools/list 输出与执行前检查共用）。
public struct MCPToolDef: Sendable {
    public let name: String
    public let description: String
    public let inputSchema: JSONValue
    /// 是否写操作（受 mcpWritesEnabled 总开关约束）。
    public let isWrite: Bool
    /// 是否破坏性操作（要求调用方显式传 confirm: true）。
    public let requiresConfirm: Bool

    init(name: String, description: String, isWrite: Bool = false, requiresConfirm: Bool = false, _ properties: [String: JSONValue], required: [String]) {
        self.name = name
        self.description = description
        self.isWrite = isWrite
        self.requiresConfirm = requiresConfirm
        self.inputSchema = MCPToolSchema.object(properties, required: required)
    }

    var asListEntry: JSONValue {
        .object([
            "name": .string(name),
            "description": .string(description),
            "inputSchema": inputSchema
        ])
    }
}

/// JSON Schema 便捷构造（MCP inputSchema 全部为 object）。
enum MCPToolSchema {
    static func object(_ properties: [String: JSONValue], required: [String]) -> JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object(properties),
            "required": .array(required.map { .string($0) })
        ])
    }

    static func str(_ description: String) -> JSONValue {
        .object(["type": .string("string"), "description": .string(description)])
    }

    static func int(_ description: String) -> JSONValue {
        .object(["type": .string("integer"), "description": .string(description)])
    }

    static func bool(_ description: String) -> JSONValue {
        .object(["type": .string("boolean"), "description": .string(description)])
    }

    static func stringArray(_ description: String) -> JSONValue {
        .object([
            "type": .string("array"),
            "items": .object(["type": .string("string")]),
            "description": .string(description)
        ])
    }

    /// 枚举字符串字段。
    static func choice(_ description: String, _ values: [String]) -> JSONValue {
        .object([
            "type": .string("string"),
            "enum": .array(values.map { .string($0) }),
            "description": .string(description)
        ])
    }
}

/// GitSpace MCP 工具清单（Story-1031-mcp doc §3.3）。
/// ⚠ 标记 = requiresConfirm（破坏性操作，对齐 MRD 10.2-G 二次确认口径）。
enum ToolRegistry {
    static let definitions: [MCPToolDef] = [
        // MARK: 清单与状态
        MCPToolDef(name: "list_repos", description: "列出 GitSpace 已纳管的仓库（名称与绝对路径）。非纳管仓库也可直接把绝对路径传给其他工具的 repo 参数。", ["repo": MCPToolSchema.str("（不使用，占位保证 schema 为 object）")], required: []),
        MCPToolDef(name: "git_status", description: "查看仓库状态：分支、相对上游、暂存/未暂存/未跟踪/冲突文件清单。", ["repo": repoParam], required: ["repo"]),
        MCPToolDef(name: "git_current_sha", description: "当前 HEAD 的完整 SHA。", ["repo": repoParam], required: ["repo"]),
        MCPToolDef(name: "git_has_remote", description: "仓库是否配置了远端。", ["repo": repoParam], required: ["repo"]),

        // MARK: 历史
        MCPToolDef(name: "git_commits", description: "提交历史（默认覆盖全部分支，近窗口截断）。", [
            "repo": repoParam,
            "limit": MCPToolSchema.int("返回条数，默认 50"),
            "since_days": MCPToolSchema.int("只看最近 N 天，可选"),
            "all_branches": MCPToolSchema.bool("是否包含所有分支，默认 true")
        ], required: ["repo"]),
        MCPToolDef(name: "git_commit_detail", description: "单个提交的改动文件与 unified diff。", ["repo": repoParam, "sha": MCPToolSchema.str("提交 SHA")], required: ["repo", "sha"]),
        MCPToolDef(name: "git_file_history", description: "文件历史（--follow，重命名前历史也包含）。", ["repo": repoParam, "path": pathParam, "limit": MCPToolSchema.int("返回条数，默认 200")], required: ["repo", "path"]),
        MCPToolDef(name: "git_file_change_at", description: "某提交对指定文件的改动 diff。", ["repo": repoParam, "sha": MCPToolSchema.str("提交 SHA"), "path": pathParam], required: ["repo", "sha", "path"]),
        MCPToolDef(name: "git_show_file", description: "读取某版本文件内容（git show rev:path）。", ["repo": repoParam, "rev": revParam, "path": pathParam], required: ["repo", "rev", "path"]),
        MCPToolDef(name: "git_refs_containing", description: "某提交被哪些本地分支 / 远程分支 / tag 包含。", ["repo": repoParam, "sha": MCPToolSchema.str("提交 SHA")], required: ["repo", "sha"]),
        MCPToolDef(name: "git_commit_template", description: "读取 commit.template 配置内容（存在时）。", ["repo": repoParam], required: ["repo"]),

        // MARK: diff
        MCPToolDef(name: "git_worktree_diff", description: "工作区未暂存改动的 unified diff。", ["repo": repoParam], required: ["repo"]),
        MCPToolDef(name: "git_staged_diff", description: "暂存区改动的 unified diff。", ["repo": repoParam], required: ["repo"]),
        MCPToolDef(name: "git_untracked_file_diff", description: "未跟踪文件的内容预览。", ["repo": repoParam, "path": pathParam], required: ["repo", "path"]),
        MCPToolDef(name: "git_diff_against_revision", description: "工作区与某版本在指定文件上的 diff。", ["repo": repoParam, "rev": revParam, "path": pathParam], required: ["repo", "rev", "path"]),

        // MARK: 分支 / tag / stash
        MCPToolDef(name: "git_local_branches", description: "本地分支列表（含当前分支、上游与 ahead/behind）。", ["repo": repoParam], required: ["repo"]),
        MCPToolDef(name: "git_remote_branches", description: "远程分支列表。", ["repo": repoParam], required: ["repo"]),
        MCPToolDef(name: "git_tags", description: "tag 列表（含类型、日期、标题）。", ["repo": repoParam], required: ["repo"]),
        MCPToolDef(name: "git_stashes", description: "stash 列表。", ["repo": repoParam], required: ["repo"]),
        MCPToolDef(name: "git_stash_diff", description: "某个 stash 的内容 diff。", ["repo": repoParam, "index": MCPToolSchema.int("stash 序号，如 0 表示 stash@{0}")], required: ["repo", "index"]),
        MCPToolDef(name: "git_blame", description: "文件逐行 blame（每行归属提交与内容）。", ["repo": repoParam, "path": pathParam, "rev": revParam], required: ["repo", "path"]),

        // MARK: 冲突读取
        MCPToolDef(name: "git_conflict_stage_contents", description: "冲突文件的三路 stage 内容（base/ours/theirs），供外部合并或人工比对。", ["repo": repoParam, "path": pathParam], required: ["repo", "path"]),

        // MARK: 写：暂存与提交
        MCPToolDef(name: "git_stage", description: "暂存文件（git add）。", isWrite: true, ["repo": repoParam, "paths": MCPToolSchema.stringArray("要暂存的相对路径列表")], required: ["repo", "paths"]),
        MCPToolDef(name: "git_unstage", description: "取消暂存（git restore --staged）。", isWrite: true, ["repo": repoParam, "paths": MCPToolSchema.stringArray("要取消暂存的相对路径列表")], required: ["repo", "paths"]),
        MCPToolDef(name: "git_commit", description: "提交暂存区内容，返回新提交 SHA。空信息或暂存区为空会被拒绝。", isWrite: true, ["repo": repoParam, "message": MCPToolSchema.str("提交信息"), "amend": MCPToolSchema.bool("是否修正上一次提交，默认 false")], required: ["repo", "message"]),
        MCPToolDef(name: "git_commit_merge", description: "合并进行中时收尾提交（git commit --no-edit）。", isWrite: true, ["repo": repoParam], required: ["repo"]),

        // MARK: 写：丢弃与恢复
        MCPToolDef(name: "git_discard", description: "⚠ 丢弃改动：scope=worktree 只还原工作区；stagedAndWorktree 连暂存一起回到 HEAD；untracked 把未跟踪文件移入废纸篓（可找回）。不可恢复部分请先评估。", isWrite: true, requiresConfirm: true, ["repo": repoParam, "scope": MCPToolSchema.choice("丢弃范围", ["worktree", "stagedAndWorktree", "untracked"]), "path": pathParam], required: ["repo", "scope", "path"]),
        MCPToolDef(name: "git_stash_snapshot", description: "创建丢弃前快照（git stash create，只建对象不动工作区），返回 SHA。", isWrite: true, ["repo": repoParam, "message": MCPToolSchema.str("快照说明，可选")], required: ["repo"]),
        MCPToolDef(name: "git_restore_from_snapshot", description: "从丢弃快照恢复指定文件到工作区。", isWrite: true, ["repo": repoParam, "sha": MCPToolSchema.str("快照 SHA"), "paths": MCPToolSchema.stringArray("要恢复的相对路径")], required: ["repo", "sha", "paths"]),
        MCPToolDef(name: "git_restore_file", description: "⚠ 把某版本文件内容取回工作区（覆盖当前工作区文件）。", isWrite: true, requiresConfirm: true, ["repo": repoParam, "rev": revParam, "path": pathParam], required: ["repo", "rev", "path"]),

        // MARK: 写：stash
        MCPToolDef(name: "git_stash_push", description: "暂存当前改动到 stash。", isWrite: true, ["repo": repoParam, "message": MCPToolSchema.str("stash 说明，可选")], required: ["repo"]),
        MCPToolDef(name: "git_stash_restore", description: "恢复某个 stash（mode=pop 恢复并删除 / apply 恢复保留）。", isWrite: true, ["repo": repoParam, "index": MCPToolSchema.int("stash 序号"), "mode": MCPToolSchema.choice("恢复方式", ["pop", "apply"])], required: ["repo", "index"]),
        MCPToolDef(name: "git_stash_drop", description: "⚠ 删除某个 stash 记录（内容提交仍在对象库短期可找回，但引用即失效）。", isWrite: true, requiresConfirm: true, ["repo": repoParam, "index": MCPToolSchema.int("stash 序号")], required: ["repo", "index"]),

        // MARK: 写：分支
        MCPToolDef(name: "git_create_branch", description: "新建分支（git switch -c）。", isWrite: true, ["repo": repoParam, "name": MCPToolSchema.str("分支名"), "from": MCPToolSchema.str("起点（分支名/SHA），默认当前 HEAD")], required: ["repo", "name"]),
        MCPToolDef(name: "git_switch_branch", description: "切换分支（脏工作区会被拒绝，请先 stash 或提交）。", isWrite: true, ["repo": repoParam, "name": MCPToolSchema.str("分支名")], required: ["repo", "name"]),
        MCPToolDef(name: "git_delete_branch", description: "⚠ 删除分支；force=true 可删未合并分支（强确认）。", isWrite: true, requiresConfirm: true, ["repo": repoParam, "name": MCPToolSchema.str("分支名"), "force": MCPToolSchema.bool("删除未合并分支，默认 false")], required: ["repo", "name"]),
        MCPToolDef(name: "git_rename_branch", description: "重命名分支。", isWrite: true, ["repo": repoParam, "old": MCPToolSchema.str("旧分支名"), "new": MCPToolSchema.str("新分支名")], required: ["repo", "old", "new"]),
        MCPToolDef(name: "git_checkout_remote_branch", description: "检出远程分支为本地分支（远程分支名如 origin/feature）。", isWrite: true, requiresConfirm: true, ["repo": repoParam, "name": MCPToolSchema.str("远程分支短名，如 origin/feature/x")], required: ["repo", "name"]),
        MCPToolDef(name: "git_checkout_commit", description: "⚠ 检出到某提交（detached HEAD）。", isWrite: true, requiresConfirm: true, ["repo": repoParam, "sha": MCPToolSchema.str("提交 SHA")], required: ["repo", "sha"]),

        // MARK: 写：合并与冲突
        MCPToolDef(name: "git_merge", description: "合并分支（style=auto/ff-only/no-ff，冲突时返回冲突文件清单）。", isWrite: true, ["repo": repoParam, "ref": MCPToolSchema.str("要合并进来的分支或引用"), "style": MCPToolSchema.choice("合并方式", ["auto", "ff-only", "no-ff"]), "message": MCPToolSchema.str("合并信息（no-ff 或产生合并提交时使用），可选")], required: ["repo", "ref"]),
        MCPToolDef(name: "git_resolve_conflict", description: "冲突文件选边：resolution=ours/theirs/mergeMarkers（生成标记人工编辑）。", isWrite: true, ["repo": repoParam, "path": pathParam, "resolution": MCPToolSchema.choice("解决方式", ["ours", "theirs", "mergeMarkers"])], required: ["repo", "path", "resolution"]),
        MCPToolDef(name: "git_mark_conflict_resolved", description: "标记冲突文件已解决（git add）。", isWrite: true, ["repo": repoParam, "path": pathParam], required: ["repo", "path"]),
        MCPToolDef(name: "git_abort_merge", description: "⚠ 中止合并，工作区回到合并前。", isWrite: true, requiresConfirm: true, ["repo": repoParam], required: ["repo"]),
        MCPToolDef(name: "git_abort_pick", description: "⚠ 中止进行中的 cherry-pick / revert，工作区回到操作前。", isWrite: true, requiresConfirm: true, ["repo": repoParam], required: ["repo"]),

        // MARK: 写：同步
        MCPToolDef(name: "git_fetch", description: "fetch 全部远端并清理失效引用。", isWrite: true, ["repo": repoParam], required: ["repo"]),
        MCPToolDef(name: "git_pull", description: "拉取并合并（mode=ff-only 安全默认 / merge 冲突进入冲突流程）。", isWrite: true, ["repo": repoParam, "mode": MCPToolSchema.choice("pull 方式", ["ff-only", "merge"])], required: ["repo"]),
        MCPToolDef(name: "git_push", description: "⚠ 推送当前分支到上游（仅已配上游分支；永不 force，被拒不自动合并）。", isWrite: true, requiresConfirm: true, ["repo": repoParam], required: ["repo"]),
        MCPToolDef(name: "git_push_tag", description: "⚠ 推送 tag 到远端。", isWrite: true, requiresConfirm: true, ["repo": repoParam, "name": MCPToolSchema.str("tag 名"), "remote": MCPToolSchema.str("远端名，默认 origin")], required: ["repo", "name"]),
        MCPToolDef(name: "git_delete_remote_tag", description: "⚠ 删除远端 tag。", isWrite: true, requiresConfirm: true, ["repo": repoParam, "name": MCPToolSchema.str("tag 名"), "remote": MCPToolSchema.str("远端名，默认 origin")], required: ["repo", "name"]),

        // MARK: 写：tag
        MCPToolDef(name: "git_create_tag", description: "创建 tag（带 message 时为 annotated）。", isWrite: true, ["repo": repoParam, "name": MCPToolSchema.str("tag 名"), "message": MCPToolSchema.str("tag 说明，可选"), "at": MCPToolSchema.str("指定提交 SHA，默认当前 HEAD")], required: ["repo", "name"]),
        MCPToolDef(name: "git_delete_tag", description: "⚠ 删除本地 tag。", isWrite: true, requiresConfirm: true, ["repo": repoParam, "name": MCPToolSchema.str("tag 名")], required: ["repo", "name"]),

        // MARK: 写：bisect（二分查找）
        MCPToolDef(name: "git_bisect_start", description: "⚠ 开始二分查找定位坏提交（会来回检出历史提交；要求工作区干净）。bad/good 传起始的坏/好提交 SHA。", isWrite: true, requiresConfirm: true, ["repo": repoParam, "bad": MCPToolSchema.str("已知坏提交 SHA，默认当前 HEAD"), "good": MCPToolSchema.str("已知好提交 SHA")], required: ["repo"]),
        MCPToolDef(name: "git_bisect_good", description: "标记当前（或指定）提交为好，返回 bisect log（定位完成时含 first bad commit 结论）。", isWrite: true, ["repo": repoParam, "rev": MCPToolSchema.str("提交 SHA，默认当前检出")], required: ["repo"]),
        MCPToolDef(name: "git_bisect_bad", description: "标记当前（或指定）提交为坏，返回 bisect log。", isWrite: true, ["repo": repoParam, "rev": MCPToolSchema.str("提交 SHA，默认当前检出")], required: ["repo"]),
        MCPToolDef(name: "git_bisect_skip", description: "跳过当前提交（无法构建/无法判断时），返回 bisect log。", isWrite: true, ["repo": repoParam, "rev": MCPToolSchema.str("提交 SHA，默认当前检出")], required: ["repo"]),
        MCPToolDef(name: "git_bisect_reset", description: "结束二分，回到开始前的 HEAD。", isWrite: true, ["repo": repoParam], required: ["repo"]),

        // MARK: 写：cherry-pick / revert
        MCPToolDef(name: "git_cherry_pick", description: "摘取一个提交到当前分支（冲突时返回冲突清单，可用 git_abort_pick 中止）。", isWrite: true, ["repo": repoParam, "sha": MCPToolSchema.str("要摘取的提交 SHA"), "no_commit": MCPToolSchema.bool("只应用不提交，默认 false")], required: ["repo", "sha"]),
        MCPToolDef(name: "git_revert", description: "生成反向提交撤销一个提交（不重写历史；冲突时返回冲突清单）。", isWrite: true, ["repo": repoParam, "sha": MCPToolSchema.str("要撤销的提交 SHA"), "no_commit": MCPToolSchema.bool("只应用不提交，默认 false")], required: ["repo", "sha"]),

        // MARK: 读：bisect 状态
        MCPToolDef(name: "git_bisect_log", description: "读取 bisect 过程日志（未在二分中时报错属正常）。", ["repo": repoParam], required: ["repo"]),
    ]

    static let repoParam = MCPToolSchema.str("仓库绝对路径（GitSpace 纳管仓库或任意本地 git 仓库）")
    static let pathParam = MCPToolSchema.str("仓库内相对路径")
    static let revParam = MCPToolSchema.str("任意 git 版本表达式（SHA / 分支名 / HEAD~1 等），可选")

    static func tool(named name: String) -> MCPToolDef? {
        definitions.first { $0.name == name }
    }
}
