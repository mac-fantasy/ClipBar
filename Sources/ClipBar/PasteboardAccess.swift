import AppKit

@MainActor
final class PasteboardAccess {
    private let pasteboard: NSPasteboard
    private var observedChange: Int?

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var isReadDenied: Bool {
        if #available(macOS 15.4, *) {
            return pasteboard.accessBehavior == .alwaysDeny
        }
        return false
    }

    func ignoreCurrentContents() {
        observedChange = pasteboard.changeCount
    }

    func retryCurrentContents() {
        observedChange = nil
    }

    func readIfChanged() -> CapturedContent? {
        let change = pasteboard.changeCount
        guard change != observedChange, !isReadDenied else { return nil }
        defer {
            // 有些应用延迟提供内容；读取途中换了所有者时，下个周期重新读取。
            observedChange = pasteboard.changeCount == change ? change : nil
        }
        let types = Set(pasteboard.types ?? [])
        guard !types.contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")),
            !types.contains(NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        else { return nil }

        let captured: CapturedContent?
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            as? [URL], !urls.isEmpty
        {
            captured = .files(urls)
        } else if let png = pasteboard.data(forType: .png) {
            captured = .image(png)
        } else if let tiff = pasteboard.data(forType: .tiff) {
            captured = .image(tiff)
        } else if let text = pasteboard.string(forType: .string), !text.isEmpty {
            captured = .text(text)
        } else {
            captured = nil
        }
        return pasteboard.changeCount == change ? captured : nil
    }

    func write(_ content: PreparedContent) throws {
        let objects: [NSPasteboardWriting]
        switch content {
        case .text(let text): objects = [text as NSString]
        case .files(let urls): objects = urls.map { $0 as NSURL }
        case .image(let data):
            guard let image = NSImage(data: data) else { throw ClipBarError.missingImage }
            objects = [image]
        }
        pasteboard.clearContents()
        let success = pasteboard.writeObjects(objects)
        // 自己写回历史不再作为新记录，否则会改变 FIFO 顺序并挤掉最早记录。
        observedChange = pasteboard.changeCount
        guard success else { throw ClipBarError.pasteboardWriteFailed }
    }
}
