import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import LurkerKit

/// A plain, solid-filled `width` x `height` RGB image -- cheap to make, and
/// being flat colour, compresses to almost nothing as JPEG, which is exactly
/// what the resize-math tests want: the only thing that should change is
/// pixel dimensions.
private func solidImage(width: Int, height: Int) -> CGImage {
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )!
    context.setFillColor(CGColor(red: 0.3, green: 0.5, blue: 0.9, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

private func jpegData(_ image: CGImage) -> Data {
    let output = NSMutableData()
    let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    return output as Data
}

private func pixelSize(of data: Data) -> (width: Int, height: Int)? {
    guard
        let source = CGImageSourceCreateWithData(data as CFData, nil),
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
        let width = properties[kCGImagePropertyPixelWidth] as? Int,
        let height = properties[kCGImagePropertyPixelHeight] as? Int
    else {
        return nil
    }
    return (width, height)
}

@Suite("ImagePrep")
struct ImagePrepTests {
    @Test("caps the long edge at maxDimension, keeping the aspect ratio")
    func capsLongEdge() throws {
        let input = jpegData(solidImage(width: 4000, height: 3000))
        let output = try ImagePrep.prepare(input, maxDimension: 1600)
        let size = try #require(pixelSize(of: output))
        #expect(size.width == 1600)
        #expect(size.height == 1200)
    }

    @Test("never upscales a photo already smaller than maxDimension")
    func doesNotUpscale() throws {
        let input = jpegData(solidImage(width: 400, height: 300))
        let output = try ImagePrep.prepare(input, maxDimension: 1600)
        let size = try #require(pixelSize(of: output))
        #expect(size.width == 400)
        #expect(size.height == 300)
    }

    @Test("a portrait photo caps height, not width")
    func portraitCapsHeight() throws {
        let input = jpegData(solidImage(width: 1200, height: 1600))
        let output = try ImagePrep.prepare(input, maxDimension: 800)
        let size = try #require(pixelSize(of: output))
        #expect(size.height == 800)
        #expect(size.width == 600)
    }

    @Test("a square photo scales both sides down by the same factor")
    func squareScalesEvenly() throws {
        let input = jpegData(solidImage(width: 2000, height: 2000))
        let output = try ImagePrep.prepare(input, maxDimension: 500)
        let size = try #require(pixelSize(of: output))
        #expect(size.width == 500)
        #expect(size.height == 500)
    }

    @Test("re-encodes as JPEG: the output starts with the JPEG magic number")
    func encodesJPEG() throws {
        let input = jpegData(solidImage(width: 800, height: 600))
        let output = try ImagePrep.prepare(input, maxDimension: 1600)
        #expect(output.count >= 2)
        #expect(output[output.startIndex] == 0xFF)
        #expect(output[output.index(after: output.startIndex)] == 0xD8)
    }

    @Test("garbage bytes throw decodeFailed instead of crashing")
    func garbageInputThrows() {
        #expect(throws: ImagePrepError.decodeFailed) {
            _ = try ImagePrep.prepare(Data([0x00, 0x01, 0x02, 0x03]))
        }
    }
}
