import SwiftUI
import GSFeatures
import GSGitEngine
import GSInfra

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @AppStorage("appearance") private var appearance = "system"

    var body: some View {
        @Bindable var app = app
        @Bindable var batch = app.batch
        Form {
            Section("批量同步") {
                Stepper(value: $batch.concurrency, in: 1...8) {
                    LabeledContent("并发度", value: "\(batch.concurrency)")
                }
                Picker("Pull 模式", selection: $batch.pullMode) {
                    Text("ff-only（安全，默认）").tag(PullMode.fastForwardOnly)
                    Text("merge（冲突进入冲突流程）").tag(PullMode.merge)
                }
                Text("MRD 12：批量并发默认 4（1–8 可调），单仓超时 60s，网络错误自动重试 1 次。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("时间线") {
                Stepper(value: $app.timelineWindowDays, in: 7...365, step: 7) {
                    LabeledContent("加载窗口", value: "近 \(app.timelineWindowDays) 天")
                }
                Text("超大仓按时间窗口截断，控制内存与首屏时间（MRD 10.6）。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("外观") {
                Picker("主题", selection: $appearance) {
                    Text("跟随系统").tag("system")
                    Text("浅色").tag("light")
                    Text("深色").tag("dark")
                }
            }

            Section("环境") {
                LabeledContent("git 版本", value: app.gitVersionText)
                Button("打开操作日志目录") {
                    NSWorkspace.shared.open(GSPaths.logsDirectory)
                }
                Text("所有写操作（提交/分支/合并/同步）均写入本地 JSONL 日志，可回溯（MRD 10.2-G）。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
