import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import better_music_sheet_ios

struct PagePhotoTests {

    private typealias Quad = PagePhoto.Quad

    /// A grey table with a white page on it, the page turned `degrees` and
    /// ruled with dark lines like staves.
    private func photo(width: Int = 1600, height: Int = 1200, degrees: Double) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(gray: 0.25, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: Double(width) / 2, y: Double(height) / 2)
        context.rotate(by: degrees * .pi / 180)
        let page = CGRect(x: -350, y: -480, width: 700, height: 960)
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(page)
        context.setFillColor(gray: 0, alpha: 1)
        for staff in stride(from: -400.0, to: 400, by: 120) {
            for line in 0..<5 {
                context.fill(CGRect(x: -300, y: staff + Double(line) * 12, width: 600, height: 2))
            }
        }
        return context.makeImage()!
    }

    @Test func homographyTakesEachCornerToItsMatch() {
        let from = Quad.whole(width: 100, height: 50)
        let to = Quad(topLeft: CGPoint(x: 10, y: 5), topRight: CGPoint(x: 90, y: 12),
                      bottomRight: CGPoint(x: 95, y: 70), bottomLeft: CGPoint(x: 3, y: 60))
        let h = PagePhoto.homography(from: from, to: to)
        for (p, q) in zip(from.corners, to.corners) {
            let x = Double(p.x), y = Double(p.y)
            let w: Double = h[6] * x + h[7] * y + h[8]
            let mappedX: Double = (h[0] * x + h[1] * y + h[2]) / w
            let mappedY: Double = (h[3] * x + h[4] * y + h[5]) / w
            #expect(abs(mappedX - Double(q.x)) < 1e-6)
            #expect(abs(mappedY - Double(q.y)) < 1e-6)
        }
    }

    @Test func aSquarePageIsCutOutNotRedrawn() {
        let straight = Quad(topLeft: CGPoint(x: 100, y: 50), topRight: CGPoint(x: 900, y: 52),
                            bottomRight: CGPoint(x: 901, y: 1150), bottomLeft: CGPoint(x: 99, y: 1149))
        #expect(PagePhoto.squareCrop(straight, width: 1000, height: 1200)
                == CGRect(x: 100, y: 51, width: 801, height: 1099))

        let tilted = Quad(topLeft: CGPoint(x: 100, y: 50), topRight: CGPoint(x: 900, y: 120),
                          bottomRight: CGPoint(x: 880, y: 1150), bottomLeft: CGPoint(x: 99, y: 1149))
        #expect(PagePhoto.squareCrop(tilted, width: 1000, height: 1200) == nil)
    }

    @Test func warpingOntoItsOwnFrameKeepsEveryPixel() {
        var data = [UInt8](repeating: 0, count: 7 * 5 * 4)
        for i in data.indices { data[i] = UInt8((i * 37) % 256) }
        let source = PagePhoto.Pixels(data: data, width: 7, height: 5)
        let out = PagePhoto.warp(source, quad: .whole(width: 7, height: 5), width: 7, height: 5)
        for i in stride(from: 0, to: data.count, by: 4) {
            #expect(Array(out.data[i..<(i + 3)]) == Array(data[i..<(i + 3)]))
        }
    }

    @Test func evenLightingWhitensShadedPaperAndKeepsInk() {
        // Paper fading from white to a shadowed grey, with an ink mark in the shade.
        let width = 320, height = 200
        var data = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let paper = UInt8(255 - x * 115 / width)
                let ink = (250..<254).contains(x) && (90..<110).contains(y)
                for c in 0..<3 { data[i + c] = ink ? 20 : paper }
            }
        }
        var page = PagePhoto.Pixels(data: data, width: width, height: height)
        PagePhoto.evenLighting(&page)
        let shaded = (100 * width + 200) * 4, mark = (100 * width + 251) * 4
        #expect(data[shaded] < 190)
        #expect(page.data[shaded] > 240)
        #expect(page.data[mark] < 60)
    }

    @Test func findsATiltedPageAndFlattensIt() throws {
        let image = photo(degrees: 12)
        let quad = try #require(PagePhoto.findPage(in: image))
        let size = PagePhoto.flatSize(quad, longSide: PagePhoto.pageLongSide)
        // Upright and the page's shape: 700 x 960.
        #expect(abs(Double(size.height) / Double(size.width) - 960.0 / 700) < 0.05)
        #expect(PagePhoto.squareCrop(quad, width: image.width, height: image.height) == nil)
    }

    @Test func straightensAPhotoToAJPEGOfThePage() throws {
        let photo = try #require(PagePhoto.jpeg(photo(degrees: -8), quality: 0.95))
        let page = try #require(PagePhoto.straightened(photo))
        let source = try #require(CGImageSourceCreateWithData(page as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.height > image.width)
        #expect(abs(Double(image.height) / Double(image.width) - 960.0 / 700) < 0.06)
    }

    @Test func severalScannedPagesBecomeAPDFAt300DPI() throws {
        let pages = [photo(degrees: 0), photo(degrees: 0)]
        let scan = try #require(PagePhoto.scanned(pages, maxBytes: 50 * 1024 * 1024))
        #expect(scan.filename == "Scan.pdf")
        let pdf = try #require(CGPDFDocument(CGDataProvider(data: scan.data as CFData)!))
        #expect(pdf.numberOfPages == 2)
        let box = try #require(pdf.page(at: 1)).getBoxRect(.mediaBox)
        #expect(abs(box.width - 1600 * 72 / 300) < 0.01)
        #expect(abs(box.height - 1200 * 72 / 300) < 0.01)

        let single = try #require(PagePhoto.scanned([pages[0]], maxBytes: 50 * 1024 * 1024))
        #expect(single.filename == "Scan.jpg")
    }
}
