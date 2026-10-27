import AppKit
import Foundation
import Testing

@testable import ClipBar

@MainActor
@Test func pasteboardChangeDetectionAndSelfCopies() throws {
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    let access = PasteboardAccess(pasteboard: pasteboard)
    pasteboard.clearContents()
    #expect(pasteboard.setString("  文本\n\t", forType: .string))
    if case .text(let text) = access.readIfChanged() {
        #expect(text == "  文本\n\t")
    } else {
        Issue.record("应该读取原样文本")
    }
    #expect(access.readIfChanged() == nil)
    try access.write(.text("来自历史的内容"))
    #expect(pasteboard.string(forType: .string) == "来自历史的内容")
    #expect(access.readIfChanged() == nil)
    pasteboard.clearContents()
    #expect(pasteboard.setString("新内容", forType: .string))
    #expect(access.readIfChanged() != nil)
}

@MainActor
@Test func concealedAndTransientContentsAreIgnored() {
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    let access = PasteboardAccess(pasteboard: pasteboard)
    for marker in ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType"] {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString("敏感内容", forType: .string)
        item.setData(Data(), forType: NSPasteboard.PasteboardType(marker))
        #expect(pasteboard.writeObjects([item]))
        #expect(access.readIfChanged() == nil)
    }
}

@MainActor
@Test func multipleFileURLsHavePriorityOverTextAndImages() throws {
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    let access = PasteboardAccess(pasteboard: pasteboard)
    let urls = [URL(fileURLWithPath: "/tmp/文件 A.txt"), URL(fileURLWithPath: "/tmp/文件夹 B", isDirectory: true)]
    pasteboard.clearContents()
    let items = try urls.map { url in
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .fileURL)
        item.setString(url.lastPathComponent, forType: .string)
        item.setData(try sampleImage(), forType: .png)
        return item
    }
    #expect(pasteboard.writeObjects(items))
    if case .files(let captured) = access.readIfChanged() {
        #expect(captured == urls)
    } else {
        Issue.record("文件 URL 应优先于预览图和文件名文本")
    }
    try access.write(.files(urls))
    let copied = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
    #expect(copied == urls)
    #expect(access.readIfChanged() == nil)
}

@MainActor
@Test func imageRoundTripAndInvalidCopyDoesNotClearClipboard() throws {
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    let access = PasteboardAccess(pasteboard: pasteboard)
    let png = try sampleImage()
    pasteboard.clearContents()
    #expect(pasteboard.setData(png, forType: .png))
    if case .image(let data) = access.readIfChanged() {
        #expect(data == png)
    } else {
        Issue.record("应该捕获图片")
    }
    try access.write(.image(png))
    #expect(NSImage(pasteboard: pasteboard) != nil)
    #expect(access.readIfChanged() == nil)
    try access.write(.text("保留当前剪贴板"))
    #expect(throws: ClipBarError.self) { try access.write(.image(Data("invalid".utf8))) }
    #expect(pasteboard.string(forType: .string) == "保留当前剪贴板")
}

@MainActor
@Test func pausedContentsAreSkippedAndEmptyClipboardIsIgnored() {
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    let access = PasteboardAccess(pasteboard: pasteboard)
    pasteboard.clearContents()
    #expect(pasteboard.setString("暂停期间内容", forType: .string))
    access.ignoreCurrentContents()
    #expect(access.readIfChanged() == nil)
    pasteboard.clearContents()
    #expect(access.readIfChanged() == nil)
    pasteboard.clearContents()
    #expect(pasteboard.setString("恢复后的新内容", forType: .string))
    #expect(access.readIfChanged() != nil)
}
