import AppKit
import Combine
import OSLog

@MainActor
final class ClipboardController: NSObject, ObservableObject {
    @Published private(set) var history = HistoryState()
    @Published private(set) var isLoaded = false
    @Published private(set) var isBusy = false
    @Published private(set) var isPaused = false
    @Published private(set) var isReadDenied = false
    @Published var errorMessage: String?

    var onCopied: (() -> Void)?
    private let store: HistoryStore
    private let pasteboard = PasteboardAccess()
    private let logger = Logger(subsystem: "local.ClipBar", category: "Clipboard")
    private var timer: Timer?

    init(repository: HistoryRepository = .applicationRepository()) {
        store = HistoryStore(repository: repository)
        super.init()
    }

    func start() {
        guard !isBusy, !isLoaded else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                history = try await store.load()
                isLoaded = true
                errorMessage = nil
                let timer = Timer(
                    timeInterval: 0.6, target: self, selector: #selector(poll), userInfo: nil, repeats: true)
                timer.tolerance = 0.15
                RunLoop.main.add(timer, forMode: .common)
                self.timer = timer
            } catch { report(error, action: "加载历史记录") }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func togglePause() {
        isPaused.toggle()
        pasteboard.ignoreCurrentContents()
    }

    func setLimit(_ value: Int) {
        guard !isBusy, isLoaded else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                history = try await store.setLimit(value)
                errorMessage = nil
            } catch { report(error, action: "更新历史条数") }
        }
    }

    func clearHistory() {
        guard !isBusy, isLoaded else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                history = try await store.clear()
                pasteboard.ignoreCurrentContents()
                errorMessage = nil
            } catch { report(error, action: "清空历史记录") }
        }
    }

    func copy(_ entry: HistoryEntry) {
        guard !isBusy, isLoaded else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let prepared = try await store.prepareCopy(id: entry.id)
                try pasteboard.write(prepared)
                errorMessage = nil
                onCopied?()
            } catch { report(error, action: "重新复制") }
        }
    }

    func thumbnail(for image: ImageAttachment) async -> NSImage? {
        do {
            guard let data = try await store.thumbnail(for: image) else { return nil }
            return NSImage(data: data)
        } catch {
            logger.error("加载缩略图失败：\(String(describing: error), privacy: .private)")
            return nil
        }
    }

    @objc private func poll() {
        guard isLoaded, !isBusy, !isPaused else { return }
        let denied = pasteboard.isReadDenied
        if denied != isReadDenied {
            isReadDenied = denied
            if !denied { pasteboard.retryCurrentContents() }
        }
        guard !denied, let captured = pasteboard.readIfChanged() else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do { history = try await store.record(captured) } catch { report(error, action: "记录剪贴板") }
        }
    }

    private func report(_ error: Error, action: String) {
        errorMessage = "\(action)失败：\(error.localizedDescription)"
        logger.error("\(action, privacy: .public)失败：\(String(describing: error), privacy: .private)")
    }
}
