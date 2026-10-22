import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

/// A photo of a page, made into what recognition reads best before upload:
/// the page found (Vision), cut out of the photo and flattened to a rectangle,
/// and its paper evened out to white. The web app does the same in
/// lib/page-edges.ts and lib/page-photo.ts, and the measurements behind each
/// choice are in its commit "Photograph a page and straighten it before
/// upload". On synthetic phone photos, a tilted page read a quarter fewer
/// labels than the clean page; flattened, the same.
///
/// Also the camera's scanned pages put together into one upload, as the web
/// app's lib/photo-pages.ts puts several photos together.
nonisolated enum PagePhoto {

    /// The page's corners in an image's pixels, y running down.
    struct Quad: Equatable, Sendable {
        var topLeft: CGPoint
        var topRight: CGPoint
        var bottomRight: CGPoint
        var bottomLeft: CGPoint

        static func whole(width: Int, height: Int) -> Quad {
            Quad(topLeft: .zero, topRight: CGPoint(x: width, y: 0),
                 bottomRight: CGPoint(x: width, y: height), bottomLeft: CGPoint(x: 0, y: height))
        }

        var corners: [CGPoint] { [topLeft, topRight, bottomRight, bottomLeft] }

        var area: Double {
            let points = corners
            var sum = 0.0
            for i in 0..<4 {
                let a = points[i], b = points[(i + 1) % 4]
                sum += a.x * b.y - b.x * a.y
            }
            return abs(sum) / 2
        }
    }

    /// RGBA, 8 bits a channel, rows top to bottom. Alpha is ignored.
    struct Pixels: Sendable {
        var data: [UInt8]
        let width: Int
        let height: Int
    }

    /// The most pixels read from a photo: a 12-megapixel phone photo whole,
    /// and a 48-megapixel one at a quarter - still more than recognition reads.
    static let sourceLongSide = 4032
    /// The flattened page's long side at most: A4 at the 300 DPI recognition
    /// reads at.
    static let pageLongSide = 3508
    /// Recognition reads a PDF at 300 DPI. Sizing each page so its picture
    /// comes out at exactly that gives it the picture's own pixels.
    static let recognitionDPI = 300.0
    /// Matches the backend's page limit (MAX_PAGES in config.py).
    static let maxPages = 50

    /// Vision's own doubt about a page, past which the whole photo is used.
    private static let leastConfidence: Float = 0.5
    /// A smaller rectangle than this share of the photo is something on the
    /// page - a picture, a box of text - or a sign behind it, not the page.
    private static let leastShare = 0.2

    // MARK: - A photo

    /// The photo (JPEG, PNG or HEIC) as a JPEG of the page in it: found,
    /// flattened and evened out. Where no page stands out, the whole photo,
    /// evened out. Nil only if it isn't a picture at all.
    static func straightened(_ photo: Data) -> Data? {
        guard let image = upright(photo) else { return nil }
        let quad = findPage(in: image) ?? .whole(width: image.width, height: image.height)
        guard var page = flatten(image, quad: quad) else { return nil }
        evenLighting(&page)
        return page.cgImage.flatMap { jpeg($0, quality: 0.92) }
    }

    /// The photo turned the way its orientation tag says, on white (a
    /// transparent PNG would otherwise turn black as a JPEG), and at most
    /// `longSide` across.
    static func upright(_ photo: Data, longSide: Int = sourceLongSide) -> CGImage? {
        guard let image = CIImage(data: photo, options: [.applyOrientationProperty: true]) else { return nil }
        return render(image, longSide: longSide)
    }

    /// Where the page's corners are in `image`, or nil if no page stands out.
    static func findPage(in image: CGImage) -> Quad? {
        let request = VNDetectDocumentSegmentationRequest()
        try? VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
        guard let found = request.results?.first, found.confidence >= leastConfidence else { return nil }
        // Vision's points are fractions of the image, y running up.
        let width = Double(image.width), height = Double(image.height)
        func pixel(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * width, y: (1 - p.y) * height) }
        let quad = Quad(topLeft: pixel(found.topLeft), topRight: pixel(found.topRight),
                        bottomRight: pixel(found.bottomRight), bottomLeft: pixel(found.bottomLeft))
        return quad.area >= leastShare * width * height ? quad : nil
    }

    /// The part of `image` inside `quad` as a rectangle: cut out as it is if
    /// it's already square in the frame, otherwise redrawn.
    static func flatten(_ image: CGImage, quad: Quad) -> Pixels? {
        if let crop = squareCrop(quad, width: image.width, height: image.height) {
            return image.cropping(to: crop).flatMap(Pixels.init)
        }
        guard let source = Pixels(image) else { return nil }
        let size = flatSize(quad, longSide: pageLongSide)
        return warp(source, quad: quad, width: size.width, height: size.height)
    }

    // Straighter than this, a page is only cut out, not redrawn. Redrawing
    // moves every pixel by some fraction of one, which softens a staff line
    // one or two pixels thick - measured on a prod photo already taken
    // straight on, it cost recognition a fifth of its notes - while
    // recognition straightens a slight tilt by itself.
    private static let squareDegrees = 1.5
    private static let squareSides = 0.02

    /// The box to cut the page out with, when `quad` is that box near enough -
    /// its sides level and upright, its opposite sides the same length - or
    /// nil when it needs flattening. Whole pixels, inside `width` x `height`.
    static func squareCrop(_ quad: Quad, width: Int, height: Int) -> CGRect? {
        func tilt(_ a: CGPoint, _ b: CGPoint, vertical: Bool) -> Double {
            let degrees = Double(atan2(b.y - a.y, b.x - a.x)) * 180 / .pi
            if vertical { return abs(abs(degrees) - 90) }
            return abs(degrees > 90 ? 180 - degrees : degrees < -90 ? -180 - degrees : degrees)
        }
        let sides = [tilt(quad.topLeft, quad.topRight, vertical: false),
                     tilt(quad.bottomLeft, quad.bottomRight, vertical: false),
                     tilt(quad.topLeft, quad.bottomLeft, vertical: true),
                     tilt(quad.topRight, quad.bottomRight, vertical: true)]
        guard sides.allSatisfy({ $0 <= squareDegrees }) else { return nil }
        let across = distance(quad.topLeft, quad.topRight) / distance(quad.bottomLeft, quad.bottomRight)
        let down = distance(quad.topLeft, quad.bottomLeft) / distance(quad.topRight, quad.bottomRight)
        guard abs(1 - across) <= squareSides, abs(1 - down) <= squareSides else { return nil }
        let left = max(0, Int(((quad.topLeft.x + quad.bottomLeft.x) / 2).rounded()))
        let right = min(width, Int(((quad.topRight.x + quad.bottomRight.x) / 2).rounded()))
        let top = max(0, Int(((quad.topLeft.y + quad.topRight.y) / 2).rounded()))
        let bottom = min(height, Int(((quad.bottomLeft.y + quad.bottomRight.y) / 2).rounded()))
        guard right > left, bottom > top else { return nil }
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    /// The flattened page's size: as long as its longer opposite sides, so no
    /// part of it is shrunk, scaled down to `longSide` at most.
    static func flatSize(_ quad: Quad, longSide: Int) -> (width: Int, height: Int) {
        let width = max(distance(quad.topLeft, quad.topRight), distance(quad.bottomLeft, quad.bottomRight))
        let height = max(distance(quad.topLeft, quad.bottomLeft), distance(quad.topRight, quad.bottomRight))
        let scale = min(1, Double(longSide) / max(width, height))
        return (max(1, Int((width * scale).rounded())), max(1, Int((height * scale).rounded())))
    }

    /// The part of `source` inside `quad`, redrawn as a `width` x `height`
    /// rectangle: each pixel read from where it lies on the photographed page,
    /// from the 4 x 4 pixels around that spot (Catmull-Rom). Bicubic rather
    /// than bilinear - Core Image's perspective correction - because a pixel
    /// landing between two others otherwise averages them, and a staff line
    /// one pixel thick comes out two pixels at half its darkness: on a prod
    /// photo, bilinear read 159 labels where bicubic read 207.
    static func warp(_ source: Pixels, quad: Quad, width: Int, height: Int) -> Pixels {
        let h = homography(from: .whole(width: width, height: height), to: quad)
        var out = [UInt8](repeating: 255, count: width * height * 4)
        let sw = source.width, maxX = source.width - 1, maxY = source.height - 1
        source.data.withUnsafeBufferPointer { data in
            out.withUnsafeMutableBufferPointer { out in
                var wx = (0.0, 0.0, 0.0, 0.0), wy = (0.0, 0.0, 0.0, 0.0)
                var o = 0
                for v in 0..<height {
                    let cy = Double(v) + 0.5
                    // Along a row every term is linear in u, so step it.
                    var nx = h[0] * 0.5 + h[1] * cy + h[2]
                    var ny = h[3] * 0.5 + h[4] * cy + h[5]
                    var nw = h[6] * 0.5 + h[7] * cy + h[8]
                    for _ in 0..<width {
                        let x = min(Double(maxX), max(0, nx / nw - 0.5))
                        let y = min(Double(maxY), max(0, ny / nw - 0.5))
                        let x0 = Int(x), y0 = Int(y)
                        wx = catmullRom(x - Double(x0))
                        wy = catmullRom(y - Double(y0))
                        let xs = (min(maxX, max(0, x0 - 1)) * 4, x0 * 4,
                                  min(maxX, x0 + 1) * 4, min(maxX, x0 + 2) * 4)
                        let ys = (min(maxY, max(0, y0 - 1)) * sw * 4, y0 * sw * 4,
                                  min(maxY, y0 + 1) * sw * 4, min(maxY, y0 + 2) * sw * 4)
                        var r = 0.0, g = 0.0, b = 0.0
                        func add(_ row: Int, _ wj: Double) {
                            func tap(_ column: Int, _ wi: Double) {
                                let p = row + column, w = wj * wi
                                r += Double(data[p]) * w
                                g += Double(data[p + 1]) * w
                                b += Double(data[p + 2]) * w
                            }
                            tap(xs.0, wx.0); tap(xs.1, wx.1); tap(xs.2, wx.2); tap(xs.3, wx.3)
                        }
                        add(ys.0, wy.0); add(ys.1, wy.1); add(ys.2, wy.2); add(ys.3, wy.3)
                        out[o] = clamp(r)
                        out[o + 1] = clamp(g)
                        out[o + 2] = clamp(b)
                        o += 4
                        nx += h[0]
                        ny += h[3]
                        nw += h[6]
                    }
                }
            }
        }
        return Pixels(data: out, width: width, height: height)
    }

    /// The weights of the four pixels around a point `t` of the way from the
    /// second to the third.
    private static func catmullRom(_ t: Double) -> (Double, Double, Double, Double) {
        let t2 = t * t, t3 = t2 * t
        return ((-t3 + 2 * t2 - t) / 2, (3 * t3 - 5 * t2 + 2) / 2,
                (-3 * t3 + 4 * t2 + t) / 2, (t3 - t2) / 2)
    }

    private static func clamp(_ value: Double) -> UInt8 {
        UInt8(min(255, max(0, value.rounded())))
    }

    /// Paper made evenly white, in place: each pixel brightened by how much
    /// darker than white the paper around it is. A lamp to one side or a page
    /// curving into shadow otherwise leaves part of it grey enough to read as
    /// ink, or its ink too faint to read at all.
    static func evenLighting(_ page: inout Pixels) {
        let width = page.width, height = page.height
        // The paper's own brightness, on a coarse grid: the brightest pixel of
        // each cell is paper even where the cell is mostly ink, and the grid
        // is then spread and smoothed so a note cluster or a thick beam
        // doesn't dip it.
        let cell = max(1, Int((Double(max(width, height)) / 160).rounded()))
        let gw = (width + cell - 1) / cell, gh = (height + cell - 1) / cell
        var grid = [Float](repeating: 0, count: gw * gh)
        page.data.withUnsafeBufferPointer { data in
            for y in 0..<height {
                let row = (y / cell) * gw
                for x in 0..<width {
                    let i = (y * width + x) * 4
                    let l = 0.299 * Float(data[i]) + 0.587 * Float(data[i + 1]) + 0.114 * Float(data[i + 2])
                    let g = row + x / cell
                    if l > grid[g] { grid[g] = l }
                }
            }
        }
        grid = maxFilter(grid, width: gw, height: gh, radius: 2)
        grid = boxBlur(boxBlur(grid, width: gw, height: gh, radius: 3), width: gw, height: gh, radius: 3)
        page.data.withUnsafeMutableBufferPointer { data in
            for y in 0..<height {
                let gy = min(Float(gh - 1), max(0, (Float(y) + 0.5) / Float(cell) - 0.5))
                let y0 = Int(gy), y1 = min(gh - 1, y0 + 1), fy = gy - Float(y0)
                for x in 0..<width {
                    let gx = min(Float(gw - 1), max(0, (Float(x) + 0.5) / Float(cell) - 0.5))
                    let x0 = Int(gx), x1 = min(gw - 1, x0 + 1), fx = gx - Float(x0)
                    let top = grid[y0 * gw + x0] + (grid[y0 * gw + x1] - grid[y0 * gw + x0]) * fx
                    let bottom = grid[y1 * gw + x0] + (grid[y1 * gw + x1] - grid[y1 * gw + x0]) * fx
                    // Floored, so a nearly black patch isn't stretched into noise.
                    let gain = 255 / max(48, top + (bottom - top) * fy)
                    let i = (y * width + x) * 4
                    for c in i..<(i + 3) {
                        data[c] = UInt8(min(255, Float(data[c]) * gain))
                    }
                }
            }
        }
    }

    private static func boxBlur(_ source: [Float], width: Int, height: Int, radius: Int) -> [Float] {
        var across = [Float](repeating: 0, count: source.count)
        var out = [Float](repeating: 0, count: source.count)
        for y in 0..<height {
            for x in 0..<width {
                let range = max(0, x - radius)...min(width - 1, x + radius)
                across[y * width + x] = range.reduce(0) { $0 + source[y * width + $1] } / Float(range.count)
            }
        }
        for x in 0..<width {
            for y in 0..<height {
                let range = max(0, y - radius)...min(height - 1, y + radius)
                out[y * width + x] = range.reduce(0) { $0 + across[$1 * width + x] } / Float(range.count)
            }
        }
        return out
    }

    private static func maxFilter(_ source: [Float], width: Int, height: Int, radius: Int) -> [Float] {
        var out = [Float](repeating: 0, count: source.count)
        for y in 0..<height {
            for x in 0..<width {
                var best: Float = 0
                for j in max(0, y - radius)...min(height - 1, y + radius) {
                    for k in max(0, x - radius)...min(width - 1, x + radius) where source[j * width + k] > best {
                        best = source[j * width + k]
                    }
                }
                out[y * width + x] = best
            }
        }
        return out
    }

    /// The 3x3 projective map (row by row, last entry 1) taking each corner
    /// of `from` to the same corner of `to`.
    static func homography(from: Quad, to: Quad) -> [Double] {
        // Eight equations, two a corner, in the eight unknowns h0..h7:
        //   X = (h0 x + h1 y + h2) / (h6 x + h7 y + 1), likewise Y with h3..h5.
        var rows: [[Double]] = []
        for (p, q) in zip(from.corners, to.corners) {
            rows.append([p.x, p.y, 1, 0, 0, 0, -q.x * p.x, -q.x * p.y, q.x])
            rows.append([0, 0, 0, p.x, p.y, 1, -q.y * p.x, -q.y * p.y, q.y])
        }
        return solve(rows) + [1]
    }

    /// Gaussian elimination with partial pivoting on an augmented n x (n+1)
    /// system.
    private static func solve(_ rows: [[Double]]) -> [Double] {
        var m = rows
        let n = m.count
        for col in 0..<n {
            var pivot = col
            for r in (col + 1)..<n where abs(m[r][col]) > abs(m[pivot][col]) { pivot = r }
            m.swapAt(col, pivot)
            let p = m[col][col] == 0 ? 1e-12 : m[col][col]
            for r in 0..<n where r != col {
                let f = m[r][col] / p
                if f == 0 { continue }
                for c in col...n { m[r][c] -= f * m[col][c] }
            }
        }
        return (0..<n).map { m[$0][n] / (m[$0][$0] == 0 ? 1e-12 : m[$0][$0]) }
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        hypot(a.x - b.x, a.y - b.y)
    }

    // MARK: - Scanned pages

    // Long side of an A4 page at 300 DPI: plenty for recognition, and it
    // keeps a dozen pages well inside the upload limit. A second, smaller
    // pass is tried if they still don't fit.
    private static let attempts: [(longSide: Int, quality: Double)] = [(3508, 0.85), (2800, 0.72)]

    /// The camera's scanned pages as one upload: a page alone as a JPEG, as a
    /// photo is uploaded, and several as a PDF a page each, in order - to
    /// everything after the upload an ordinary multi-page PDF. Under
    /// `maxBytes` if it can be done without making the pages too small to
    /// read; past that, the smallest try, for the uploader to refuse.
    static func scanned(_ pages: [CGImage], maxBytes: Int) -> (filename: String, data: Data)? {
        if pages.count == 1 {
            guard let page = render(CIImage(cgImage: pages[0]), longSide: sourceLongSide) else { return nil }
            return jpeg(page, quality: 0.92).map { ("Scan.jpg", $0) }
        }
        var smallest: Data?
        for attempt in attempts {
            guard let pdf = pdf(pages, longSide: attempt.longSide, quality: attempt.quality) else { return nil }
            if pdf.count <= maxBytes { return ("Scan.pdf", pdf) }
            smallest = pdf
        }
        return smallest.map { ("Scan.pdf", $0) }
    }

    private static func pdf(_ pages: [CGImage], longSide: Int, quality: Double) -> Data? {
        let out = NSMutableData()
        guard let consumer = CGDataConsumer(data: out as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil) else { return nil }
        for page in pages {
            // Drawn from the JPEG itself, which the PDF then holds as it is.
            guard let scaled = render(CIImage(cgImage: page), longSide: longSide),
                  let encoded = jpeg(scaled, quality: quality),
                  let provider = CGDataProvider(data: encoded as CFData),
                  let image = CGImage(jpegDataProviderSource: provider, decode: nil,
                                      shouldInterpolate: true, intent: .defaultIntent) else { return nil }
            var box = CGRect(x: 0, y: 0, width: Double(image.width) * 72 / recognitionDPI,
                             height: Double(image.height) * 72 / recognitionDPI)
            let info = [kCGPDFContextMediaBox: Data(bytes: &box, count: MemoryLayout<CGRect>.size)] as CFDictionary
            context.beginPDFPage(info)
            context.draw(image, in: box)
            context.endPDFPage()
        }
        context.closePDF()
        return out as Data
    }

    // MARK: - Pictures

    /// `image` on white, at most `longSide` across (shrunk with Lanczos), as
    /// sRGB pixels.
    private static func render(_ image: CIImage, longSide: Int) -> CGImage? {
        let extent = image.extent
        guard !extent.isInfinite, extent.width >= 1, extent.height >= 1 else { return nil }
        var image = image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
        var size = extent.size
        let scale = Double(longSide) / max(size.width, size.height)
        if scale < 1 {
            image = image.applyingFilter("CILanczosScaleTransform",
                                         parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1])
            size = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        }
        let rect = CGRect(origin: .zero, size: size)
        image = image.composited(over: CIImage(color: .white).cropped(to: rect))
        guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CIContext().createCGImage(image, from: rect, format: .RGBA8, colorSpace: sRGB)
    }

    static func jpeg(_ image: CGImage, quality: Double) -> Data? {
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out as CFMutableData,
                                                                 UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image,
                                   [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? out as Data : nil
    }
}

nonisolated extension PagePhoto.Pixels {
    /// `image`'s pixels as sRGB RGBA.
    init?(_ image: CGImage) {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 255, count: width * height * 4)
        let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4, space: sRGB,
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.init(data: data, width: width, height: height)
    }

    var cgImage: CGImage? {
        guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(data) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: sRGB,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
