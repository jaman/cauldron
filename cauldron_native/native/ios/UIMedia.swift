import AVFoundation
import AVKit
import SwiftUI

func mediaURL(_ source: String) -> URL? {
    if source.hasPrefix("http://") || source.hasPrefix("https://") { return URL(string: source) }
    return URL(fileURLWithPath: source)
}

struct NodeVideo: View {
    let node: UINode
    @State private var player: AVPlayer?
    @State private var source: String?

    var body: some View {
        VideoController(player: player, controls: node.props["controls"] as? Bool ?? true)
            .aspectRatio(16 / 9, contentMode: .fit)
            .onAppear(perform: load)
            .onChange(of: node.string("source")) { load() }
            .onChange(of: node.bool("muted")) { player?.isMuted = node.bool("muted") }
            .onDisappear { player?.pause() }
            .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification)) { note in
                guard let item = note.object as? AVPlayerItem, item === player?.currentItem else { return }
                ended()
            }
    }

    private func load() {
        let wanted = node.string("source") ?? ""
        guard wanted != source, let url = mediaURL(wanted) else { return }
        source = wanted
        let created = AVPlayer(url: url)
        created.isMuted = node.bool("muted")
        if node.bool("autoplay") { created.play() }
        player = created
    }

    private func ended() {
        if node.events.contains("end") { UIEvents(id: node.id).send("end") }
        guard node.bool("loop"), let player else { return }
        player.seek(to: .zero)
        player.play()
    }
}

struct NodeCameraPreview: View {
    let node: UINode
    @Environment(\.scenePhase) private var phase
    @State private var granted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized

    var body: some View {
        Group {
            if granted {
                CameraLayer(front: node.string("facing") == "front")
            } else {
                ContentUnavailableView("No access to the camera", systemImage: "camera")
            }
        }
        .aspectRatio(3 / 4, contentMode: .fit)
        .onChange(of: phase) { granted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized }
        .onReceive(NotificationCenter.default.publisher(for: .cauldronPermissionsChanged)) { _ in
            granted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        }
    }
}
