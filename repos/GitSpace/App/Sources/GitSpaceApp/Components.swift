import SwiftUI
import GSFeatures
import GSDesignKit

// MARK: - Toast

struct ToastsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: GSSpacing.xs) {
            ForEach(app.toasts.toasts) { toast in
                ToastRow(toast: toast)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.bottom, 34)
        .animation(.easeOut(duration: 0.2), value: app.toasts.toasts.map(\.id))
    }
}

private struct ToastRow: View {
    @Environment(AppModel.self) private var app
    let toast: ToastCenter.Toast

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: toast.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(toast.isError ? Color.gs(.red) : Color.gs(.green))
            Text(toast.text)
                .font(.callout)
                .lineLimit(3)
            if let label = toast.actionLabel, let action = toast.action {
                Button(label) {
                    action()
                    app.toasts.dismiss(id: toast.id)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(Color.gs(.accent))
            }
        }
        .padding(.horizontal, GSSpacing.m)
        .padding(.vertical, GSSpacing.s)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 10, y: 3)
    }
}

// MARK: - 空态

struct EmptyStateView: View {
    let title: String
    let hint: String
    var showReset = false
    var onReset: (() -> Void)?

    var body: some View {
        VStack(spacing: GSSpacing.s) {
            Image(systemName: "circle.dashed")
                .font(.system(size: 30))
                .foregroundStyle(.quaternary)
            Text(title).font(.callout.weight(.medium)).foregroundStyle(.secondary)
            Text(hint)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            if showReset {
                Button("一键重置筛选", action: { onReset?() })
                    .buttonStyle(.link)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(GSSpacing.xl)
    }
}

// MARK: - 状态栏

struct StatusBarView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: GSSpacing.m) {
            statusDot
            Text("\(app.repoCount) 个仓库已纳管")
            if app.totalUnpushed > 0 {
                Text("\(app.totalUnpushed) 个未推送提交")
            }
            if let refreshed = app.lastRefreshed {
                Text("上次刷新 \(refreshed.formatted(date: .omitted, time: .shortened))")
            }
            if app.isRefreshing {
                ProgressView().controlSize(.mini)
            }
            Spacer()
            Text("● 本地模式 · 数据不上传")
            Text("Git \(app.gitVersionText)").font(.gsMonoSmall)
            Text("v0.1.0-mvp")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, GSSpacing.m)
        .padding(.vertical, 4)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var statusDot: some View {
        Circle()
            .fill(app.attentionCount > 0 ? Color.gs(.amber) : Color.gs(.green))
            .frame(width: 6, height: 6)
    }
}
