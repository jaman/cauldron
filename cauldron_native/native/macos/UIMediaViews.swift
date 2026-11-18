import AVFoundation
import AVKit
import SwiftUI

struct VideoController: NSViewRepresentable {
    let player: AVPlayer?
    let controls: Bool

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.allowsPictureInPicturePlayback = true
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
        view.controlsStyle = controls ? .floating : .none
    }
}

struct CameraLayer: NSViewRepresentable {
    let front: Bool

    func makeNSView(context: Context) -> CameraView {
        let view = CameraView()
        view.start(front: front)
        return view
    }

    func updateNSView(_ view: CameraView, context: Context) {
        view.start(front: front)
    }

    static func dismantleNSView(_ view: CameraView, coordinator: ()) {
        view.stop()
    }
}

final class CameraView: NSView {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "cauldron.camera")
    private var facing: Bool?

    override func makeBackingLayer() -> CALayer {
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        return preview
    }

    func start(front: Bool) {
        wantsLayer = true
        guard facing != front else { return }
        facing = front
        let session = session
        queue.async {
            session.beginConfiguration()
            session.inputs.forEach { session.removeInput($0) }
            if let device = CameraView.camera(front: front),
               let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
                session.addInput(input)
            }
            session.commitConfiguration()
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        let session = session
        queue.async { session.stopRunning() }
    }

    private static func camera(front: Bool) -> AVCaptureDevice? {
        let found = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
                                                     mediaType: .video, position: .unspecified).devices
        let wanted: AVCaptureDevice.Position = front ? .front : .back
        return found.first { $0.position == wanted } ?? found.first
    }
}
