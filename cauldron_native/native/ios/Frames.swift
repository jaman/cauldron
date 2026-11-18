import CoreText
import Foundation
import QuartzCore

struct OverlayShape {
    let x: CGFloat
    let y: CGFloat
    let radius: CGFloat
    let held: Bool
    let alpha: Float
    let label: String
}

final class PendingFrame {
    private let lock = NSLock()
    private var image: CGImage?

    func offer(_ next: CGImage) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let wasEmpty = image == nil
        image = next
        return wasEmpty
    }

    func take() -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        let taken = image
        image = nil
        return taken
    }
}

@_cdecl("cn_platform_present")
func cnPlatformPresent(_ rgba: UnsafePointer<UInt8>, _ width: Int32, _ height: Int32) {
    let bytes = Int(width) * Int(height) * 4
    guard let data = CFDataCreate(nil, rgba, bytes), let provider = CGDataProvider(data: data),
          let image = CGImage(width: Int(width), height: Int(height), bitsPerComponent: 8, bitsPerPixel: 32,
                              bytesPerRow: Int(width) * 4, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                              provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    else { return }

    if Screen.shared.offerFrame(image) {
        DispatchQueue.main.async {
            if let latest = Screen.shared.takeFrame() { Screen.shared.show(latest) }
        }
    }
}

@_cdecl("cn_platform_overlay")
func cnPlatformOverlay(_ packed: UnsafePointer<UInt8>, _ size: Int) {
    let shapes = OverlayDecoder.decode(UnsafeBufferPointer(start: packed, count: size))
    DispatchQueue.main.async { Screen.shared.draw(shapes) }
}

enum OverlayDecoder {
    static func decode(_ bytes: UnsafeBufferPointer<UInt8>) -> [OverlayShape] {
        var shapes: [OverlayShape] = []
        var at = 0
        while at + 16 <= bytes.count {
            let x = float(bytes, at), y = float(bytes, at + 4), radius = float(bytes, at + 8)
            let held = bytes[at + 12] != 0
            let alpha = Float(bytes[at + 13]) / 255
            let length = Int(bytes[at + 14]) | Int(bytes[at + 15]) << 8
            let start = at + 16
            guard start + length <= bytes.count else { break }
            let label = String(decoding: UnsafeBufferPointer(rebasing: bytes[start..<start + length]), as: UTF8.self)
            shapes.append(OverlayShape(x: CGFloat(x), y: CGFloat(y), radius: CGFloat(radius), held: held, alpha: alpha, label: label))
            at = start + length
        }
        return shapes
    }

    private static func float(_ bytes: UnsafeBufferPointer<UInt8>, _ at: Int) -> Float {
        let bits = UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24
        return Float(bitPattern: bits)
    }
}

@_cdecl("cn_platform_gpu_surface")
func cnPlatformMetalLayer() -> UnsafeMutableRawPointer? {
    let layer = Screen.shared.metalLayer
    DispatchQueue.main.async { Screen.shared.showMetal() }
    return Unmanaged.passUnretained(layer).toOpaque()
}

@_cdecl("cn_platform_hide_gpu_surface")
func cnPlatformHideMetalLayer() {
    DispatchQueue.main.async { Screen.shared.hideMetal() }
}

enum OverlayLayers {
    static func circle(_ shape: OverlayShape, scale: CGFloat) -> CAShapeLayer {
        let layer = CAShapeLayer()
        let radius = shape.radius / scale
        let rect = CGRect(x: shape.x / scale - radius, y: shape.y / scale - radius, width: radius * 2, height: radius * 2)
        layer.path = CGPath(ellipseIn: rect, transform: nil)
        layer.lineWidth = 2.5
        layer.strokeColor = CGColor(gray: 1, alpha: 0.85)
        layer.fillColor = shape.held ? CGColor(gray: 1, alpha: 0.4) : CGColor(gray: 0, alpha: 0.32)
        layer.shadowColor = CGColor(gray: 0, alpha: 1)
        layer.shadowOpacity = 0.7
        layer.shadowRadius = 2.5
        layer.shadowOffset = .zero
        return layer
    }

    static func label(_ shape: OverlayShape, scale: CGFloat) -> CATextLayer {
        let layer = CATextLayer()
        let radius = shape.radius / scale
        let lines = shape.label.split(separator: " ", maxSplits: 1).map(String.init)
        let base = radius * 0.42
        let widest = lines.map { width($0, size: base) }.max() ?? 1
        let size = min(base, base * radius * 1.6 / max(widest, 1))
        layer.string = lines.joined(separator: "\n")
        layer.font = bold(size)
        layer.fontSize = size
        layer.alignmentMode = .center
        layer.foregroundColor = CGColor(gray: 1, alpha: 0.95)
        layer.shadowColor = CGColor(gray: 0, alpha: 1)
        layer.shadowOpacity = 0.9
        layer.shadowRadius = 1.5
        layer.shadowOffset = .zero
        layer.contentsScale = scale
        let width = shape.radius / scale * 2
        let height = size * 1.2 * CGFloat(lines.count)
        layer.frame = CGRect(x: shape.x / scale - width / 2, y: shape.y / scale - height / 2, width: width, height: height)
        return layer
    }

    private static func bold(_ size: CGFloat) -> CTFont {
        CTFontCreateUIFontForLanguage(.emphasizedSystem, size, nil) ?? CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
    }

    private static func width(_ text: String, size: CGFloat) -> CGFloat {
        let attributed = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): bold(size)])
        return CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(attributed), nil, nil, nil))
    }
}
