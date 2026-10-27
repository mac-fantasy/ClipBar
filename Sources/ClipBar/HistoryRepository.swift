import CryptoKit
import Foundation
import ImageIO
import OSLog
import UniformTypeIdentifiers

struct HistoryRepository: Sendable {
    static let maximumImageBytes = 32 * 1024 * 1024
    static let maximumImagePixels = 40_000_000

    let directory: URL
    private var historyURL: URL { directory.appendingPathComponent("history.json") }
    var imageDirectory: URL { directory.appendingPathComponent("Images", isDirectory: true) }

    static func applicationRepository() -> HistoryRepository {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return HistoryRepository(directory: base.appendingPathComponent("ClipBar", isDirectory: true))
    }

    func load() throws -> HistoryState {
        try prepareDirectories()
        guard FileManager.default.fileExists(atPath: historyURL.path) else { return HistoryState() }
        let data = try Data(contentsOf: historyURL)
        let state: HistoryState
        do {
            state = try JSONDecoder().decode(HistoryState.self, from: data)
        } catch {
            throw NSError(
                domain: "ClipBar.History", code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: ClipBarError.invalidHistory.localizedDescription,
                    NSUnderlyingErrorKey: error,
                ]
            )
        }
        guard state.version == 1 else { throw ClipBarError.unsupportedVersion }
        guard (1...HistoryState.maximumLimit).contains(state.limit),
            state.entries.count <= state.limit,
            Set(state.entries.map(\.id)).count == state.entries.count
        else {
            throw ClipBarError.invalidHistory
        }
        for entry in state.entries {
            switch entry.content {
            case .text(let text):
                guard !text.isEmpty else { throw ClipBarError.invalidHistory }
            case .files(let urls):
                guard !urls.isEmpty, urls.allSatisfy({ $0.isFileURL }) else {
                    throw ClipBarError.invalidHistory
                }
            case .image(let image):
                guard isValidImageReference(image), image.pixelWidth > 0, image.pixelHeight > 0,
                    image.byteCount > 0
                else { throw ClipBarError.invalidHistory }
            }
        }
        return state
    }

    func save(_ state: HistoryState) throws {
        try prepareDirectories()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(state).write(to: historyURL, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: historyURL.path)
    }

    func storeImage(_ data: Data) throws -> ImageAttachment {
        guard data.count <= Self.maximumImageBytes else { throw ClipBarError.imageTooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int,
            width > 0, height > 0
        else { throw ClipBarError.invalidImage }
        guard width <= Self.maximumImagePixels / height else { throw ClipBarError.imageTooLarge }

        let png: Data
        if CGImageSourceGetType(source) as String? == UTType.png.identifier {
            png = data
        } else {
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)
            else {
                throw ClipBarError.invalidImage
            }
            CGImageDestinationAddImageFromSource(destination, source, 0, nil)
            guard CGImageDestinationFinalize(destination) else { throw ClipBarError.invalidImage }
            png = output as Data
        }
        guard png.count <= Self.maximumImageBytes else { throw ClipBarError.imageTooLarge }
        let digest = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
        let filename = digest + ".png"
        try prepareDirectories()
        let url = imageDirectory.appendingPathComponent(filename)
        if !FileManager.default.fileExists(atPath: url.path) {
            try png.write(to: url, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        return ImageAttachment(
            filename: filename, digest: digest, pixelWidth: width, pixelHeight: height, byteCount: png.count)
    }

    func readImage(_ image: ImageAttachment) throws -> Data {
        guard isValidImageReference(image) else { throw ClipBarError.missingImage }
        let url = imageDirectory.appendingPathComponent(image.filename)
        guard FileManager.default.fileExists(atPath: url.path) else { throw ClipBarError.missingImage }
        let data = try Data(contentsOf: url)
        guard data.count == image.byteCount,
            SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == image.digest
        else {
            throw ClipBarError.missingImage
        }
        return data
    }

    func thumbnailData(_ image: ImageAttachment) throws -> Data? {
        guard isValidImageReference(image) else { return nil }
        let url = imageDirectory.appendingPathComponent(image.filename)
        guard FileManager.default.fileExists(atPath: url.path),
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let thumbnail = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 160,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                ] as CFDictionary)
        else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, thumbnail, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    func removeUnusedImages(in state: HistoryState) throws {
        let referenced = Set(
            state.entries.compactMap { entry -> String? in
                if case .image(let image) = entry.content { return image.filename }
                return nil
            })
        let files = try FileManager.default.contentsOfDirectory(at: imageDirectory, includingPropertiesForKeys: nil)
        for file in files where file.pathExtension == "png" && !referenced.contains(file.lastPathComponent) {
            try FileManager.default.removeItem(at: file)
        }
    }

    private func prepareDirectories() throws {
        for url in [directory, imageDirectory] {
            try FileManager.default.createDirectory(
                at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        }
    }

    private func isValidImageReference(_ image: ImageAttachment) -> Bool {
        image.digest.count == 64 && image.digest.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
            && image.filename == image.digest + ".png"
    }
}

actor HistoryStore {
    private let repository: HistoryRepository
    private var state = HistoryState()
    private var loaded = false
    private let logger = Logger(subsystem: "local.ClipBar", category: "History")

    init(repository: HistoryRepository) {
        self.repository = repository
    }

    func load() throws -> HistoryState {
        let restored = try repository.load()
        state = restored
        loaded = true
        cleanImages()
        return state
    }

    func record(_ captured: CapturedContent) throws -> HistoryState {
        guard loaded else { throw ClipBarError.invalidHistory }
        let content: HistoryContent
        switch captured {
        case .text(let text):
            guard !text.isEmpty else { return state }
            content = .text(text)
        case .files(let urls):
            guard !urls.isEmpty, urls.allSatisfy({ $0.isFileURL }) else { return state }
            content = .files(urls)
        case .image(let data):
            content = .image(try repository.storeImage(data))
        }
        var next = state
        if next.record(HistoryEntry(content: content)) { try commit(next) }
        return state
    }

    func setLimit(_ value: Int) throws -> HistoryState {
        guard loaded else { throw ClipBarError.invalidHistory }
        var next = state
        try next.setLimit(value)
        try commit(next)
        return state
    }

    func clear() throws -> HistoryState {
        guard loaded else { throw ClipBarError.invalidHistory }
        var next = state
        next.clear()
        try commit(next)
        return state
    }

    func prepareCopy(id: UUID) throws -> PreparedContent {
        guard let entry = state.entries.first(where: { $0.id == id }) else { throw ClipBarError.entryNotFound }
        switch entry.content {
        case .text(let text): return .text(text)
        case .image(let image): return .image(try repository.readImage(image))
        case .files(let urls):
            let missing = urls.filter { !FileManager.default.fileExists(atPath: $0.path) }.count
            guard missing == 0 else { throw ClipBarError.missingFiles(missing) }
            return .files(urls)
        }
    }

    func thumbnail(for image: ImageAttachment) throws -> Data? {
        try repository.thumbnailData(image)
    }

    private func commit(_ next: HistoryState) throws {
        // 先原子落盘，再删除淘汰图片，避免保存失败时破坏仍被旧历史引用的文件。
        try repository.save(next)
        state = next
        cleanImages()
    }

    private func cleanImages() {
        do {
            try repository.removeUnusedImages(in: state)
        } catch {
            logger.error("清理未引用的图片失败，将在下次保存时重试：\(String(describing: error), privacy: .private)")
        }
    }
}
