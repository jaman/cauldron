import AVFoundation
import AVKit
import SwiftUI
import UIKit

struct VideoController: UIViewControllerRepresentable {
    let player: AVPlayer?
    let controls: Bool

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.allowsPictureInPicturePlayback = true
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
        controller.showsPlaybackControls = controls
    }
}

struct CameraLayer: UIViewRepresentable {
    let front: Bool

    func makeUIView(context: Context) -> CameraView {
        let view = CameraView()
        view.start(front: front)
        return view
    }

    func updateUIView(_ view: CameraView, context: Context) {
        view.start(front: front)
    }

    static func dismantleUIView(_ view: CameraView, coordinator: ()) {
        view.stop()
    }
}

final class CameraView: UIView {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "cauldron.camera")
    private var facing: Bool?

    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    func start(front: Bool) {
        guard facing != front else { return }
        facing = front
        let preview = layer as! AVCaptureVideoPreviewLayer
        preview.videoGravity = .resizeAspectFill
        preview.session = session
        let session = session
        queue.async {
            session.beginConfiguration()
            session.inputs.forEach { session.removeInput($0) }
            let position: AVCaptureDevice.Position = front ? .front : .back
            if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
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
}
