import QuartzCore
import UIKit

final class Screen: UIViewController {
    static let shared = Screen()

    private let picture = CALayer()
    private let metal = CAMetalLayer()
    private let shapes = CALayer()
    private var pictureSize = CGSize.zero
    private let pending = PendingFrame()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        #if !os(tvOS)
        view.isMultipleTouchEnabled = true
        #endif
        picture.magnificationFilter = .nearest
        picture.minificationFilter = .nearest
        picture.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        metal.isHidden = true
        metal.actions = ["bounds": NSNull(), "position": NSNull()]
        view.layer.addSublayer(picture)
        view.layer.addSublayer(metal)
        view.layer.addSublayer(shapes)
    }

    #if !os(tvOS)
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .all }
    #endif

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        shapes.frame = view.bounds
        metal.frame = view.bounds
        metal.contentsScale = view.contentScaleFactor
        placePicture()
        let scale = view.contentScaleFactor
        let insets = view.safeAreaInsets
        cn_screen(Int32(view.bounds.width * scale), Int32(view.bounds.height * scale), Float(scale),
                  Float(insets.top * scale), Float(insets.right * scale), Float(insets.bottom * scale), Float(insets.left * scale))
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
        let scale = view.contentScaleFactor
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

    private func placePicture() {
        guard pictureSize.width > 0, pictureSize.height > 0 else { return }
        let scale = view.contentScaleFactor
        let screenWidth = view.bounds.width * scale
        let screenHeight = view.bounds.height * scale
        let fit = min(screenWidth / pictureSize.width, screenHeight / pictureSize.height)
        let factor = fit >= 1 ? floor(fit) : fit
        let width = pictureSize.width * factor / scale
        let height = pictureSize.height * factor / scale
        picture.frame = CGRect(x: (view.bounds.width - width) / 2, y: (view.bounds.height - height) / 2, width: width, height: height)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { report(touches, phase: CN_TOUCH_BEGAN) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { report(touches, phase: CN_TOUCH_MOVED) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { report(touches, phase: CN_TOUCH_ENDED) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { report(touches, phase: CN_TOUCH_CANCELLED) }

    private func report(_ touches: Set<UITouch>, phase: Int) {
        let scale = view.contentScaleFactor
        var reported = touches.map { touch -> cn_touch in
            let point = touch.location(in: view)
            return cn_touch(id: Int64(ObjectIdentifier(touch).hashValue), phase: Int32(phase),
                            x: Float(point.x * scale), y: Float(point.y * scale))
        }
        cn_touches(&reported, Int32(reported.count))
    }
}
