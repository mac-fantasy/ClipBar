import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import ClipBar

@Test func roundTripRetainsExactTextSettingsAndFiles() throws {
    let directory = TestDirectory()
    let repository = directory.repository
    #expect(try repository.load() == HistoryState())
    var state = HistoryState(limit: 37)
    state.record(HistoryEntry(content: .text("  中文 👩‍💻\n第二行\t  ")))
    let file = URL(fileURLWithPath: "/tmp/只有路径、不读内容.txt")
    state.record(HistoryEntry(content: .files([file])))
    try repository.save(state)
    #expect(try repository.load() == state)
    #expect(try FileManager.default.contentsOfDirectory(atPath: repository.imageDirectory.path).isEmpty)
    let permissions =
        try FileManager.default.attributesOfItem(atPath: repository.directory.path)[.posixPermissions] as? NSNumber
    #expect(permissions?.intValue == 0o700)
    let historyPermissions =
        try FileManager.default.attributesOfItem(
            atPath: repository.directory.appendingPathComponent("history.json").path)[.posixPermissions] as? NSNumber
    #expect(historyPermissions?.intValue == 0o600)
}

@Test func pngRoundTripThumbnailAndOrphanCleanup() throws {
    let directory = TestDirectory()
    let repository = directory.repository
    let png = try sampleImage()
    let image = try repository.storeImage(png)
    #expect(image.pixelWidth == 4)
    #expect(image.pixelHeight == 3)
    #expect(try repository.readImage(image) == png)
    #expect(try repository.thumbnailData(image) != nil)
    #expect(try repository.storeImage(png) == image)
    #expect(try FileManager.default.contentsOfDirectory(atPath: repository.imageDirectory.path).count == 1)
    var state = HistoryState()
    state.record(HistoryEntry(content: .image(image)))
    try repository.save(state)
    try repository.removeUnusedImages(in: state)
    #expect(try repository.readImage(image) == png)
    state.clear()
    try repository.save(state)
    try repository.removeUnusedImages(in: state)
    #expect(try FileManager.default.contentsOfDirectory(atPath: repository.imageDirectory.path).isEmpty)
}

@Test func tiffIsConvertedToPNG() throws {
    let directory = TestDirectory()
    let repository = directory.repository
    let image = try repository.storeImage(sampleImage(type: .tiff))
    let png = try repository.readImage(image)
    let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
    #expect(CGImageSourceGetType(source) as String? == UTType.png.identifier)
    #expect(image.pixelWidth == 4)
    #expect(image.pixelHeight == 3)
}

@Test func corruptOrFutureHistoryIsNotOverwritten() throws {
    let directory = TestDirectory()
    let repository = directory.repository
    _ = try repository.load()
    let url = repository.directory.appendingPathComponent("history.json")
    let corrupt = Data("{broken".utf8)
    try corrupt.write(to: url)
    #expect(throws: (any Error).self) { try repository.load() }
    #expect(try Data(contentsOf: url) == corrupt)
    let future = Data(#"{"version":999,"limit":20,"entries":[]}"#.utf8)
    try future.write(to: url)
    #expect(throws: ClipBarError.self) { try repository.load() }
    #expect(try Data(contentsOf: url) == future)
    try Data(#"{"version":1,"limit":101,"entries":[]}"#.utf8).write(to: url)
    #expect(throws: ClipBarError.self) { try repository.load() }
}

@Test func unsafeImageReferencesAndInvalidImagesAreRejected() throws {
    let directory = TestDirectory()
    let repository = directory.repository
    let unsafe = ImageAttachment(
        filename: "../outside.png", digest: String(repeating: "a", count: 64), pixelWidth: 1, pixelHeight: 1,
        byteCount: 1)
    #expect(throws: ClipBarError.self) { try repository.readImage(unsafe) }
    var state = HistoryState()
    state.record(HistoryEntry(content: .image(unsafe)))
    try repository.save(state)
    #expect(throws: ClipBarError.self) { try repository.load() }
    #expect(throws: ClipBarError.self) { try repository.storeImage(Data("not an image".utf8)) }
    #expect(throws: ClipBarError.self) {
        try repository.storeImage(Data(repeating: 0, count: HistoryRepository.maximumImageBytes + 1))
    }
}

@Test func tamperedImageIsNotCopied() throws {
    let directory = TestDirectory()
    let repository = directory.repository
    let image = try repository.storeImage(sampleImage())
    try Data("tampered".utf8).write(to: repository.imageDirectory.appendingPathComponent(image.filename))
    #expect(throws: ClipBarError.self) { try repository.readImage(image) }
}

@Test func filesAreReferencesAndMissingSourcesFailBeforeCopy() async throws {
    let directory = TestDirectory()
    let repository = directory.repository
    let store = HistoryStore(repository: repository)
    _ = try await store.load()
    let source = directory.url.appendingPathComponent("原始文件.txt")
    let original = Data("原文件内容不可复制到历史目录".utf8)
    try original.write(to: source)
    let state = try await store.record(.files([source]))
    let entry = try #require(state.entries.first)
    if case .files(let urls) = try await store.prepareCopy(id: entry.id) {
        #expect(urls == [source])
    } else {
        Issue.record("应恢复文件 URL")
    }
    let storedJSON = try Data(contentsOf: repository.directory.appendingPathComponent("history.json"))
    #expect(!String(decoding: storedJSON, as: UTF8.self).contains("原文件内容不可复制到历史目录"))
    #expect(try FileManager.default.contentsOfDirectory(atPath: repository.imageDirectory.path).isEmpty)
    try FileManager.default.removeItem(at: source)
    await #expect(throws: ClipBarError.self) { try await store.prepareCopy(id: entry.id) }
}

@Test func actorStorePersistsCapacityCleansEvictedImagesAndSurvivesRestart() async throws {
    let directory = TestDirectory()
    let repository = directory.repository
    let store = HistoryStore(repository: repository)
    _ = try await store.load()
    _ = try await store.setLimit(1)
    let imageState = try await store.record(.image(sampleImage()))
    #expect(imageState.entries.count == 1)
    let textState = try await store.record(.text("替换图片"))
    #expect(textState.entries.map(\.content) == [.text("替换图片")])
    #expect(try FileManager.default.contentsOfDirectory(atPath: repository.imageDirectory.path).isEmpty)
    let restarted = HistoryStore(repository: repository)
    #expect(try await restarted.load() == textState)
    let cleared = try await restarted.clear()
    #expect(cleared.entries.isEmpty)
    #expect(cleared.limit == 1)
    #expect(try repository.load() == cleared)
}

@Test func failedSaveRetainsPreviousStateAndImages() async throws {
    let directory = TestDirectory()
    let repository = directory.repository
    let store = HistoryStore(repository: repository)
    _ = try await store.load()
    let original = try await store.record(.image(sampleImage()))
    let historyURL = repository.directory.appendingPathComponent("history.json")
    try FileManager.default.removeItem(at: historyURL)
    try FileManager.default.createDirectory(at: historyURL, withIntermediateDirectories: false)
    await #expect(throws: (any Error).self) { try await store.record(.text("不能保存")) }
    let id = try #require(original.entries.first?.id)
    if case .image(let data) = try await store.prepareCopy(id: id) {
        #expect(!data.isEmpty)
    } else {
        Issue.record("保存失败时应保留旧图片记录")
    }
}
