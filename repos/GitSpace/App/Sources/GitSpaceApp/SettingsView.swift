import SwiftUI
import GSFeatures
import GSGitEngine
import GSInfra

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("mergeTool") private var mergeTool = "filemerge"
    @AppStorage("mergeToolCustomTemplate") private var mergeToolCustomTemplate = ""
    @AppStorage("externalTerminal") private var externalTerminal = "terminal"
    @AppStorage("externalTerminalCustom") private var externalTerminalCustom = ""
    @AppStorage("externalEditor") private var externalEditor = "xcode"
    @AppStorage("externalEditorCustom") private var externalEditorCustom = ""

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

            Section("合并工具（EP07-F02）") {
                Picker("工具", selection: $mergeTool) {
                    ForEach(ExternalMergeTool.allCases) { tool in
                        Text(tool.displayName).tag(tool.rawValue)
                    }
                }
                if mergeTool == ExternalMergeTool.custom.rawValue {
                    TextField("命令模板（$LOCAL $REMOTE $BASE $MERGED）", text: $mergeToolCustomTemplate)
                        .textFieldStyle(.roundedBorder)
                    Text("示例：meld $LOCAL $REMOTE $BASE --output $MERGED。路径以独立参数传入，不经过 shell。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    let template = ExternalMergeTool(rawValue: mergeTool)?.template ?? ""
                    Text("命令：\(template)")
                        .font(.gsMonoSmall)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Text("工具退出后 GitSpace 会检查冲突标记；只有你确认后才执行 git add。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("终端与编辑器（EP09-F01）") {
                Picker("终端", selection: $externalTerminal) {
                    ForEach(ExternalTerminal.allCases) { terminal in
                        Text(terminal.displayName).tag(terminal.rawValue)
                    }
                }
                if externalTerminal == ExternalTerminal.custom.rawValue {
                    TextField("终端命令模板（$REPO $FILE $LINE）", text: $externalTerminalCustom)
                        .textFieldStyle(.roundedBorder)
                }
                Picker("编辑器", selection: $externalEditor) {
                    ForEach(ExternalEditor.allCases) { editor in
                        Text(editor.displayName).tag(editor.rawValue)
                    }
                }
                if externalEditor == ExternalEditor.custom.rawValue {
                    TextField("编辑器命令模板（$REPO $FILE $LINE）", text: $externalEditorCustom)
                        .textFieldStyle(.roundedBorder)
                }
                Text("文件行右键「在编辑器打开」可定位到行（xed --line / code --goto file:line）。路径以独立参数传入。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
