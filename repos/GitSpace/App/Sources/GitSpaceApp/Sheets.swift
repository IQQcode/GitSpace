import SwiftUI
import UniformTypeIdentifiers
import GSFeatures
import GSIndex
import GSGitEngine
import GSDesignKit

// MARK: - 添加仓库

struct AddRepoSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var path = ""
    @State private var name = ""
    @State private var isPicking = false
    @State private var errorText: String?
    @State private var isSubmitting = false

    var body: some View {
        VStack(alignment: .leading, spacing: GSSpacing.m) {
            Text("添加仓库").font(.headline)
            Text("把任意本地 Git 仓库加入当前工作区，支持私有仓库与自建 Gerrit。")
                .font(.caption)
                .foregroundStyle(.secondary)

            LabeledContent("本地路径") {
                HStack {
                    TextField("~/dev/components/GdThread", text: $path)
                        .textFieldStyle(.roundedBorder)
                    Button("浏览…") { isPicking = true }
                }
            }
            LabeledContent("显示名称") {
                TextField("默认取目录名", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(Color.gs(.red))
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    submit()
                } label: {
                    if isSubmitting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("添加")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Color.gs(.accent))
                .disabled(path.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
            }
        }
        .padding(GSSpacing.l)
        .frame(width: 480)
        .fileImporter(isPresented: $isPicking, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                path = url.path(percentEncoded: false)
            }
        }
    }

    private func submit() {
        isSubmitting = true
        Task {
            let error = await app.addRepo(path: path, name: name.isEmpty ? nil : name)
            isSubmitting = false
            if let error {
                errorText = error
            } else {
                dismiss()
            }
        }
    }
}

// MARK: - 扫描父目录

struct ScanSheetView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var parentPath = ""
    @State private var discovered: [DiscoveredRepo] = []
    @State private var selected = Set<String>()
    @State private var isScanning = false
    @State private var scanError: String?
    @State private var hasScanned = false
    @State private var isPicking = false
    @State private var isImporting = false

    private var importable: [DiscoveredRepo] {
        discovered.filter { repo in
            !(repo.alreadyManaged && !selected.contains(repo.id)) && !app.repos.contains { $0.config.path == repo.id } && selected.contains(repo.id)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: GSSpacing.m) {
            Text("扫描父目录").font(.headline)
            Text("自动发现目录下所有 Git 仓库（深度 3 层，跳过构建产物目录），一键纳管 50+ 仓。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                TextField("父目录，如 ~/dev/components", text: $parentPath)
                    .textFieldStyle(.roundedBorder)
                Button("浏览…") { isPicking = true }
                Button("开始扫描") { scan() }
                    .disabled(parentPath.trimmingCharacters(in: .whitespaces).isEmpty || isScanning)
            }

            if isScanning {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("正在扫描 \(parentPath) …").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let scanError {
                Text(scanError).font(.caption).foregroundStyle(Color.gs(.red))
            }

            if hasScanned {
                Text("发现 \(discovered.count) 个 Git 仓库")
                    .font(.callout.weight(.medium))
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(discovered) { item in
                            HStack {
                                Toggle(isOn: Binding(
                                    get: { selected.contains(item.id) },
                                    set: { on in
                                        if on { selected.insert(item.id) } else { selected.remove(item.id) }
                                    }
                                )) {
                                    HStack {
                                        Text(item.name).font(.callout.weight(.medium))
                                        Text(item.path.path)
                                            .font(.gsMonoSmall)
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                }
                                .disabled(item.alreadyManaged || app.repos.contains { $0.config.path == item.id })
                                Spacer()
                                if item.alreadyManaged || app.repos.contains(where: { $0.config.path == item.id }) {
                                    Text("已纳管")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
                .frame(minHeight: 180)
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("导入选中") { importSelected() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.gs(.accent))
                    .disabled(selected.isEmpty || isImporting)
            }
        }
        .padding(GSSpacing.l)
        .frame(width: 620, height: 480)
        .fileImporter(isPresented: $isPicking, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                parentPath = url.path(percentEncoded: false)
                scan()
            }
        }
    }

    private func scan() {
        isScanning = true
        scanError = nil
        Task {
            let expanded = (parentPath as NSString).expandingTildeInPath
            let known = Set(app.repos.map(\.config.path))
            let url = URL(fileURLWithPath: expanded)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory), isDirectory.boolValue else {
                isScanning = false
                hasScanned = false
                scanError = "目录不存在：\(expanded)"
                return
            }
            let result = (try? WorkspaceScanner.scan(parent: url, knownPaths: known)) ?? []
            discovered = result
            selected = Set(result.filter { !$0.alreadyManaged }.map(\.id))
            isScanning = false
            hasScanned = true
        }
    }

    private func importSelected() {
        isImporting = true
        let picked = discovered.filter { repo in
            selected.contains(repo.id) && !app.repos.contains { $0.config.path == repo.id }
        }
        Task {
            await app.importDiscovered(picked)
            isImporting = false
            dismiss()
        }
    }
}

// MARK: - 批量执行面板

struct BatchSheetView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var wasRunning = false

    var body: some View {
        @Bindable var batch = app.batch
        VStack(alignment: .leading, spacing: GSSpacing.m) {
            HStack {
                Text("批量 \(batch.action.rawValue)")
                    .font(.headline)
                Text("\(batch.items.count) 个仓库")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if batch.isRunning {
                    ProgressView().controlSize(.small)
                }
            }

            if batch.pullMode == .fastForwardOnly && batch.action == .pull {
                Label("Pull 模式：ff-only（分叉仓跳过，不自动合并）", systemImage: "shield.lefthalf.filled")
                    .font(.caption)
                    .foregroundStyle(Color.gs(.amber))
            }

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(batch.items) { item in
                        HStack(spacing: GSSpacing.s) {
                            Circle().fill(GSPalette.color(forSlot: item.repo.colorSlot)).frame(width: 7, height: 7)
                            Text(item.repo.displayName).font(.callout.weight(.medium))
                            Spacer()
                            stateView(item.state)
                        }
                        .padding(.vertical, 4)
                        Divider()
                    }
                }
            }
            .frame(minHeight: 200)

            HStack {
                if !batch.isRunning {
                    Text(batch.summaryText).font(.caption).foregroundStyle(.secondary)
                    if !batch.failedItems.isEmpty {
                        Button("重跑失败项") { batch.retryFailed() }
                            .buttonStyle(.link)
                    }
                }
                Spacer()
                if batch.isRunning {
                    Button("取消") { batch.cancel() }
                }
                Button(batch.isRunning ? "后台运行" : "完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.gs(.accent))
            }
        }
        .padding(GSSpacing.l)
        .frame(width: 520, height: 460)
        .onAppear { wasRunning = app.batch.isRunning }
        .onChange(of: app.batch.isRunning) { _, running in
            if wasRunning && !running {
                wasRunning = false
                app.toasts.show("批量 \(app.batch.action.rawValue) 完成：\(app.batch.summaryText)")
            }
        }
    }

    @ViewBuilder
    private func stateView(_ state: BatchItemState) -> some View {
        switch state {
        case .queued:
            Label("等待中", systemImage: "clock")
                .font(.caption).foregroundStyle(.tertiary)
        case .running:
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text("执行中").font(.caption)
            }
        case .succeeded:
            Label("完成", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(Color.gs(.green))
        case .skipped(let reason):
            Label("跳过 · \(reason)", systemImage: "forward.end")
                .font(.caption).foregroundStyle(Color.gs(.amber))
        case .failed(let reason):
            Label("失败 · \(reason)", systemImage: "xmark.octagon.fill")
                .font(.caption).foregroundStyle(Color.gs(.red))
                .lineLimit(2)
        case .cancelled:
            Label("已取消", systemImage: "minus.circle")
                .font(.caption).foregroundStyle(.tertiary)
        }
    }
}
