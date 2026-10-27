import Combine
import Foundation
import OSLog
import Sparkle

struct UpdateConfiguration {
    let feedURL: URL

    init?(info: [String: Any]) {
        guard let feed = info["SUFeedURL"] as? String,
            let url = URL(string: feed), url.scheme == "https", url.host == "github.com",
            url.user == nil, url.password == nil, url.port == nil,
            url.query == nil, url.fragment == nil,
            url.pathComponents.count == 7,
            Array(url.pathComponents.suffix(4)) == ["releases", "latest", "download", "appcast.xml"],
            let key = info["SUPublicEDKey"] as? String,
            Data(base64Encoded: key)?.count == 32
        else { return nil }
        feedURL = url
    }
}

@MainActor
final class UpdateController: ObservableObject {
    @Published private(set) var isAvailable = false
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var automaticallyDownloadsUpdates = false

    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
    var onCheckForUpdates: (() -> Void)?

    private var controller: SPUStandardUpdaterController?
    private let logger = Logger(subsystem: "local.ClipBar", category: "Updates")

    func start() {
        guard controller == nil else { return }
        guard UpdateConfiguration(info: Bundle.main.infoDictionary ?? [:]) != nil else {
            logger.info("当前构建未配置有效的 GitHub 更新源和 EdDSA 公钥，跳过自动更新。")
            return
        }

        let controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        do {
            try controller.updater.start()
            self.controller = controller
            controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
            controller.updater.publisher(for: \.automaticallyChecksForUpdates).assign(
                to: &$automaticallyChecksForUpdates)
            controller.updater.publisher(for: \.automaticallyDownloadsUpdates).assign(
                to: &$automaticallyDownloadsUpdates)
            isAvailable = true
        } catch {
            logger.error("启动自动更新失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        onCheckForUpdates?()
        controller?.checkForUpdates(nil)
    }

    func setAutomaticChecks(_ enabled: Bool) {
        controller?.updater.automaticallyChecksForUpdates = enabled
    }

    func setAutomaticDownloads(_ enabled: Bool) {
        controller?.updater.automaticallyDownloadsUpdates = enabled
    }
}
