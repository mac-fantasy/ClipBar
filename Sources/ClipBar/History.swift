import Foundation

struct ImageAttachment: Codable, Equatable, Sendable {
    let filename: String
    let digest: String
    let pixelWidth: Int
    let pixelHeight: Int
    let byteCount: Int
}

enum HistoryContent: Codable, Equatable, Sendable {
    case text(String)
    case image(ImageAttachment)
    case files([URL])
}

struct HistoryEntry: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let createdAt: Date
    let content: HistoryContent

    init(content: HistoryContent, id: UUID = UUID(), createdAt: Date = Date()) {
        self.id = id
        self.createdAt = createdAt
        self.content = content
    }
}

struct HistoryState: Codable, Equatable, Sendable {
    static let defaultLimit = 20
    static let maximumLimit = 100

    let version: Int
    private(set) var limit: Int
    private(set) var entries: [HistoryEntry]

    init(limit: Int = defaultLimit, entries: [HistoryEntry] = []) {
        version = 1
        self.limit = min(max(limit, 1), Self.maximumLimit)
        self.entries = Array(entries.prefix(self.limit))
    }

    @discardableResult
    mutating func record(_ entry: HistoryEntry) -> Bool {
        guard entries.first?.content != entry.content else { return false }
        entries.insert(entry, at: 0)
        trim()
        return true
    }

    mutating func setLimit(_ value: Int) throws {
        guard (1...Self.maximumLimit).contains(value) else {
            throw ClipBarError.invalidLimit
        }
        limit = value
        trim()
    }

    mutating func clear() {
        entries.removeAll()
    }

    private mutating func trim() {
        if entries.count > limit {
            entries.removeLast(entries.count - limit)
        }
    }
}

enum CapturedContent: Sendable {
    case text(String)
    case image(Data)
    case files([URL])
}

enum PreparedContent: Sendable {
    case text(String)
    case image(Data)
    case files([URL])
}

enum ClipBarError: LocalizedError {
    case invalidLimit
    case invalidHistory
    case unsupportedVersion
    case invalidImage
    case imageTooLarge
    case missingImage
    case missingFiles(Int)
    case pasteboardWriteFailed
    case entryNotFound

    var errorDescription: String? {
        switch self {
        case .invalidLimit: "历史条数必须是 1–100 之间的整数。"
        case .invalidHistory: "历史数据损坏。请先备份应用数据目录，修复或移走 history.json 后重试。"
        case .unsupportedVersion: "历史数据由更新版本创建，请使用兼容版本打开。"
        case .invalidImage: "无法读取这张图片，已跳过。"
        case .imageTooLarge: "图片超过 32 MB 或 4000 万像素，已跳过，以免占用过多资源。"
        case .missingImage: "这条记录的图片已丢失或损坏，无法复制。"
        case .missingFiles(let count): "有 \(count) 个原始文件或文件夹已移动、删除或无法访问，未改动当前剪贴板。"
        case .pasteboardWriteFailed: "写入系统剪贴板失败，请重试。"
        case .entryNotFound: "这条记录已被移除，请选择其他记录。"
        }
    }
}
