import AppKit
import SwiftUI

struct HistoryView: View {
    @ObservedObject var controller: ClipboardController
    @ObservedObject var updater: UpdateController
    @State private var showsSettings = false
    @State private var confirmsClear = false
    @State private var limitDraft = "20"
    @State private var limitError: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            if showsSettings { settings }
            if controller.isReadDenied {
                notice("系统已禁止读取剪贴板。请在系统设置中允许 ClipBar 访问剪贴板。", symbol: "lock.shield", color: .orange)
            }
            if let message = controller.errorMessage {
                HStack(alignment: .top, spacing: 6) {
                    notice(message, symbol: "exclamationmark.triangle", color: .orange)
                    Button {
                        controller.errorMessage = nil
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .help("关闭提示")
                    .padding(.trailing, 16)
                    .padding(.top, 10)
                }
            }
            HStack {
                Text("最近记录").font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("\(controller.history.entries.count) / \(controller.history.limit)")
                    .font(.system(size: 11, design: .monospaced))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)

            if controller.history.entries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(controller.history.entries) { entry in
                            HistoryRow(entry: entry, controller: controller) { controller.copy(entry) }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                }
            }
            Divider()
            footer
        }
        .frame(width: 400, height: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: controller.history.limit) { value in limitDraft = String(value) }
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.blue.gradient, in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 3) {
                Text("ClipBar").font(.system(size: 17, weight: .semibold))
                HStack(spacing: 4) {
                    Circle().fill(statusColor).frame(width: 5, height: 5)
                    Text(statusText).font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                controller.togglePause()
            } label: {
                Image(systemName: controller.isPaused ? "play.fill" : "pause.fill")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .help(controller.isPaused ? "恢复记录" : "暂停记录")
            .accessibilityLabel(controller.isPaused ? "恢复记录" : "暂停记录")
            .disabled(!controller.isLoaded || controller.isBusy)
            Button {
                showsSettings.toggle()
                limitDraft = String(controller.history.limit)
                limitError = nil
            } label: {
                Image(systemName: "gearshape").frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .help("设置")
            .accessibilityLabel("设置")
        }
        .padding(18)
        .padding(.bottom, 2)
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text("保留条数").font(.system(size: 12, weight: .medium))
                Spacer()
                TextField("1–100", text: $limitDraft)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 64)
                    .accessibilityLabel("历史记录保留条数")
                    .onSubmit(saveLimit)
                Button("保存", action: saveLimit)
                    .disabled(controller.isBusy || !controller.isLoaded)
            }
            Text("默认 20 条，最多 100 条；超出后移除最早的记录。调小条数会立即删除超出的历史。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let limitError {
                Text(limitError).font(.system(size: 11)).foregroundStyle(.orange)
            }
            Divider()
            HStack {
                Text("版本 \(updater.version)").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button("检查更新…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }
            if updater.isAvailable {
                Toggle(
                    "自动检查更新",
                    isOn: Binding(
                        get: { updater.automaticallyChecksForUpdates },
                        set: { updater.setAutomaticChecks($0) }
                    )
                )
                Toggle(
                    "自动下载并安装更新",
                    isOn: Binding(
                        get: { updater.automaticallyDownloadsUpdates },
                        set: { updater.setAutomaticDownloads($0) }
                    )
                )
                .disabled(!updater.automaticallyChecksForUpdates)
            } else {
                Text("此构建暂不支持自动更新。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "clipboard").font(.system(size: 40, weight: .ultraLight)).foregroundStyle(.tertiary)
            Text(controller.isLoaded ? "还没有剪贴板记录" : (controller.isBusy ? "正在准备历史记录" : "历史记录暂不可用"))
                .font(.system(size: 14, weight: .medium))
            Text("复制文本、图片或 Finder 中的文件\n记录就会出现在这里")
                .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if !controller.isLoaded && !controller.isBusy {
                Button("重新加载") { controller.start() }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if confirmsClear {
                HStack {
                    Text("删除全部历史和缓存图片？").font(.system(size: 11))
                    Spacer()
                    Button("取消") { confirmsClear = false }
                    Button("清空", role: .destructive) {
                        confirmsClear = false
                        controller.clearHistory()
                    }
                    .disabled(controller.isBusy)
                }
            } else {
                HStack {
                    Text("点击记录即可重新复制").font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        confirmsClear = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("清空历史")
                    .accessibilityLabel("清空历史")
                    .disabled(controller.history.entries.isEmpty || controller.isBusy)
                    Button("退出") { NSApp.terminate(nil) }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11))
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
    }

    private func notice(_ message: String, symbol: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(message).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func saveLimit() {
        guard let value = Int(limitDraft.trimmingCharacters(in: .whitespacesAndNewlines)),
            (1...HistoryState.maximumLimit).contains(value)
        else {
            limitError = ClipBarError.invalidLimit.localizedDescription
            return
        }
        limitError = nil
        controller.setLimit(value)
    }

    private var statusText: String {
        if !controller.isLoaded { return controller.isBusy ? "正在加载" : "历史记录不可用" }
        if controller.isReadDenied { return "等待剪贴板访问权限" }
        return controller.isPaused ? "已暂停记录" : "自动记录剪贴板"
    }

    private var statusColor: Color {
        if !controller.isLoaded || controller.isReadDenied || controller.isPaused { return .orange }
        return .green
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry
    @ObservedObject var controller: ClipboardController
    let action: () -> Void
    @State private var isHovered = false
    @State private var thumbnail: NSImage?

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                preview
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 6) {
                        Text(detail).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 4)
                        Text(entry.createdAt, style: .time).monospacedDigit()
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }
                Image(systemName: "arrow.up.doc")
                    .font(.system(size: 12))
                    .foregroundStyle(isHovered ? Color.accentColor : Color.secondary.opacity(0.45))
            }
            .padding(11)
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(
                isHovered ? Color.accentColor.opacity(0.09) : Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(controller.isBusy)
        .onHover { isHovered = $0 }
        .help(helpText)
        .accessibilityLabel("重新复制：\(title)")
        .task(id: entry.id) {
            if case .image(let image) = entry.content {
                thumbnail = await controller.thumbnail(for: image)
            }
        }
    }

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.07))
            if let thumbnail {
                Image(nsImage: thumbnail).resizable().scaledToFit().padding(3)
            } else {
                Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(Color.accentColor)
            }
        }
        .frame(width: 46, height: 46)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var title: String {
        switch entry.content {
        case .text(let text):
            let preview = String(text.prefix(240)).trimmingCharacters(in: .whitespacesAndNewlines)
            return preview.isEmpty ? "空白文本" : preview
        case .image: return "图片"
        case .files(let urls):
            return urls.map(\.lastPathComponent).joined(separator: "、")
        }
    }

    private var detail: String {
        switch entry.content {
        case .text(let text): return "文本 · \(text.count) 字符"
        case .image(let image):
            return
                "\(image.pixelWidth) × \(image.pixelHeight) · \(ByteCountFormatter.string(fromByteCount: Int64(image.byteCount), countStyle: .file))"
        case .files(let urls): return "\(urls.count) 个项目 · \(urls.first?.deletingLastPathComponent().path ?? "")"
        }
    }

    private var symbol: String {
        switch entry.content {
        case .text: "text.alignleft"
        case .image: "photo"
        case .files: "doc.on.doc"
        }
    }

    private var helpText: String {
        switch entry.content {
        case .text(let text): return String(text.prefix(2_000))
        case .image: return "点击重新复制图片"
        case .files(let urls): return urls.map(\.path).joined(separator: "\n")
        }
    }
}
