import SwiftUI
import GSFeatures
import GSGitEngine
import GSDesignKit

/// 推送前确认（EP05-F02）：列出将推送的仓库、分支与提交数；永不提供 force（MRD 10.2-G）。
/// 目标分支编辑与 push -u 首推属 EP05-F05（批次 B）。
struct PushConfirmSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    private var preview: [PushPreviewItem] { app.pushPreview }
    private var pushable: [PushPreviewItem] { preview.filter(\.isPushable) }
    private var totalCommits: Int { pushable.reduce(0) { $0 + $1.ahead } }

    var body: some View {
        VStack(alignment: .leading, spacing: GSSpacing.m) {
            Text(pushable.count > 1 ? "推送 \(pushable.count) 个仓库" : "推送")
                .font(.headline)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(preview) { item in
                        row(item)
                        Divider()
                    }
                }
            }
            .frame(minHeight: 120, maxHeight: 320)

            Text("推送仅对已配置上游的分支执行；非快进被拒时不会自动合并，也永不 force（MRD 10.2-G）。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("推送 \(pushable.count) 仓 ⌘↩") { app.confirmPush() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.gs(.accent))
                    .disabled(pushable.isEmpty)
            }
        }
        .padding(GSSpacing.l)
        .frame(width: 560)
    }

    @ViewBuilder
    private func row(_ item: PushPreviewItem) -> some View {
        HStack(spacing: GSSpacing.s) {
            if item.isPushable {
                Image(systemName: "arrow.up.circle")
                    .foregroundStyle(Color.gs(.accent))
            } else {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.tertiary)
            }
            Text(item.repoName)
                .font(.callout.weight(.medium))
            if let branch = item.branch {
                Text(branch).font(.gsMonoSmall).foregroundStyle(Color.gs(.accent))
            }
            if let upstream = item.upstream {
                Text("→ \(upstream)").font(.gsMonoSmall).foregroundStyle(.secondary)
            }
            Spacer()
            if let reason = item.skipReason {
                Text("跳过：\(reason)")
                    .font(.caption)
                    .foregroundStyle(Color.gs(.amber))
            } else {
                Text("\(item.ahead) 个提交")
                    .font(.gsMonoSmall.weight(.semibold))
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, GSSpacing.xs)
    }
}
