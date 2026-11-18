import AppKit
import QuartzCore

final class ScreenView: NSView {
    weak var screen: Screen?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        screen?.laidOut()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        screen?.laidOut()
    }

    override func mouseDown(with event: NSEvent) { screen?.pointer(event, phase: CN_TOUCH_BEGAN) }
    override func mouseDragged(with event: NSEvent) { screen?.pointer(event, phase: CN_TOUCH_MOVED) }
    override func mouseUp(with event: NSEvent) { screen?.pointer(event, phase: CN_TOUCH_ENDED) }
}

final class Screen: NSViewController {
    static let shared = Screen()

    private let picture = CALayer()
    private let metal = CAMetalLayer()
    private let shapes = CALayer()
    private var pictureSize = CGSize.zero
    private let pending = PendingFrame()

    override func loadView() {
        let screenView = ScreenView()
        screenView.screen = self
        let root = CALayer()
        root.backgroundColor = CGColor(gray: 0, alpha: 1)
        root.isGeometryFlipped = true
        screenView.layer = root
        screenView.wantsLayer = true
        picture.magnificationFilter = .nearest
        picture.minificationFilter = .nearest
        picture.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        metal.isHidden = true
        metal.actions = ["bounds": NSNull(), "position": NSNull()]
        root.addSublayer(picture)
        root.addSublayer(metal)
        root.addSublayer(shapes)
        view = screenView
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        laidOut()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        laidOut()
    }

    private var scale: CGFloat { view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }

    func laidOut() {
        let bounds = view.bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapes.frame = bounds
        metal.frame = bounds
        metal.contentsScale = scale
        placePicture()
        CATransaction.commit()
        guard bounds.width > 0, bounds.height > 0 else { return }
        cn_screen(Int32(bounds.width * scale), Int32(bounds.height * scale), Float(scale), 0, 0, 0, 0)
    }

    func show(_ image: CGImage) {
        let size = CGSize(width: image.width, height: image.height)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        picture.contents = image
        if size != pictureSize {
            pictureSize = size
            placePicture()
        }
        CATransaction.commit()
    }

    func draw(_ overlay: [OverlayShape]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapes.sublayers?.forEach { $0.removeFromSuperlayer() }
        for shape in overlay {
            let circleLayer = OverlayLayers.circle(shape, scale: scale)
            circleLayer.opacity = shape.alpha
            shapes.addSublayer(circleLayer)
            if !shape.label.isEmpty {
                let labelLayer = OverlayLayers.label(shape, scale: scale)
                labelLayer.opacity = shape.alpha
                shapes.addSublayer(labelLayer)
            }
        }
        CATransaction.commit()
    }

    var metalLayer: CAMetalLayer { metal }

    func showMetal() { metal.isHidden = false }

    func hideMetal() { metal.isHidden = true }

    func takeFrame() -> CGImage? { pending.take() }
    func offerFrame(_ image: CGImage) -> Bool { pending.offer(image) }

    func pointer(_ event: NSEvent, phase: Int) {
        let point = view.convert(event.locationInWindow, from: nil)
        var touch = cn_touch(id: 1, phase: Int32(phase), x: Float(point.x * scale), y: Float(point.y * scale))
        cn_touches(&touch, 1)
    }

    private func placePicture() {
        guard pictureSize.width > 0, pictureSize.height > 0 else { return }
        let bounds = view.bounds
        let fit = min(bounds.width * scale / pictureSize.width, bounds.height * scale / pictureSize.height)
        let factor = fit >= 1 ? floor(fit) : fit
        let width = pictureSize.width * factor / scale
        let height = pictureSize.height * factor / scale
        picture.frame = CGRect(x: (bounds.width - width) / 2, y: (bounds.height - height) / 2, width: width, height: height)
    }
}
