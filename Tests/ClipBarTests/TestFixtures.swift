import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

@testable import ClipBar

final class TestDirectory: Sendable {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("ClipBarTests-\(UUID())", isDirectory: true)
    var repository: HistoryRepository { HistoryRepository(directory: url.appendingPathComponent("History")) }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

func sampleImage(type: UTType = .png) throws -> Data {
    guard
        let context = CGContext(
            data: nil, width: 4, height: 3, bitsPerComponent: 8, bytesPerRow: 16,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    else { throw ClipBarError.invalidImage }
    context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 4, height: 3))
    guard let image = context.makeImage() else { throw ClipBarError.invalidImage }
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
        throw ClipBarError.invalidImage
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw ClipBarError.invalidImage }
    return data as Data
}
