import AVFoundation
import MediaPlayer
import Photos
import UniformTypeIdentifiers
import UserNotifications

extension Notification.Name {
    static let cauldronPermissionsChanged = Notification.Name("cauldronPermissionsChanged")
}

func answerRequest(_ id: String, _ status: String, _ value: Any?) {
    var message: [String: Any] = ["id": id, "status": status]
    if let value { message["value"] = value }
    guard let data = try? JSONSerialization.data(withJSONObject: message) else { return }
    data.withUnsafeBytes { bytes in
        cn_result(bytes.bindMemory(to: UInt8.self).baseAddress, data.count)
    }
}

func linkOpened(_ url: URL) {
    let data = Data(url.absoluteString.utf8)
    data.withUnsafeBytes { bytes in
        cn_url(bytes.bindMemory(to: UInt8.self).baseAddress, data.count)
    }
}

@_cdecl("cn_platform_request")
func cnPlatformRequest(_ json: UnsafePointer<UInt8>, _ size: Int) {
    let data = Data(bytes: json, count: size)
    guard let request = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
    DispatchQueue.main.async { Device.shared.handle(request) }
}

final class Device: NSObject {
    static let shared = Device()

    var pending: [ObjectIdentifier: String] = [:]
    private var recorder: AVAudioRecorder?
    private var recording: String?
    private var player: AVPlayer?
    private var playing: String?
    private var commandsReady = false

    func handle(_ request: [String: Any]) {
        let id = request["id"] as? String ?? ""
        switch request["action"] as? String {
        case "haptic": haptic(request["style"] as? String ?? "")
        case "pick_photos": pickPhotos(id, limit: request["limit"] as? Int ?? 1, videos: request["videos"] as? Bool ?? false)
        case "take_photo": capture(id, video: false)
        case "record_video": capture(id, video: true)
        case "pick_files": pickFiles(id, types: request["types"] as? [String] ?? ["any"], many: request["many"] as? Bool ?? false)
        case "permission": permission(id, request["name"] as? String ?? "")
        case "record_start": startRecording(id)
        case "record_stop": stopRecording()
        case "share": share(text: request["text"] as? String, file: request["file"] as? String)
        case "open_url": if let url = URL(string: request["url"] as? String ?? "") { openURL(url) }
        case "play": play(id, request)
        case "playback": playback(request["command"] as? String ?? "")
        case "location": Locator.shared.current(id, precise: request["precise"] as? Bool ?? true)
        case "location_watch":
            Locator.shared.watch(id, precise: request["precise"] as? Bool ?? true, distance: request["distance"] as? Double ?? 10)
        case "location_stop": Locator.shared.stop()
        case "background_schedule": Refresh.schedule(id, minutes: (request["minutes"] as? NSNumber)?.doubleValue ?? 15)
        case "background_done": Refresh.done()
        case "background_cancel": Refresh.cancel()
        case "widget_update": WidgetBridge.update(request)
        case "purchase_products": Purchases.products(id, request["keys"] as? [String] ?? [])
        case "purchase_buy": Purchases.buy(id, request["key"] as? String ?? "")
        case "purchase_owned": Purchases.owned(id)
        case "purchase_restore": Purchases.restore(id)
        case "purchase_watch": Purchases.watch(id)
        case "purchase_subscription": Purchases.subscription(id, request["keys"] as? [String] ?? [])
        case "purchase_transactions": Purchases.transactions(id)
        case "purchase_refund": Purchases.refund(id, request["transaction"] as? String ?? "")
        case "purchase_manage": Purchases.manage()
        case "purchase_redeem": Purchases.redeem(id)
        case "request_review": Task { @MainActor in StoreSheets.review() }
        case "activity_start": LiveActivities.start(id, request)
        case "activity_update": LiveActivities.update(id, request)
        case "activity_finish": LiveActivities.finish(id, request)
        case "weather":
            Weather.current(id, latitude: request["latitude"] as? Double ?? 0, longitude: request["longitude"] as? Double ?? 0)
        case "notify": Notifier.shared.schedule(id, request)
        case "notify_cancel": Notifier.shared.cancel(id)
        case "push_register": Notifier.shared.registerPush(id)
        default: break
        }
    }


    private func permission(_ id: String, _ name: String) {
        let granted: (Bool) -> Void = { [weak self] allowed in
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .cauldronPermissionsChanged, object: nil)
                self?.answer(id, "ok", allowed ? "granted" : "denied")
            }
        }
        switch name {
        case "camera" where declared("NSCameraUsageDescription"):
            AVCaptureDevice.requestAccess(for: .video, completionHandler: granted)
        case "microphone" where declared("NSMicrophoneUsageDescription"):
            AVAudioApplication.requestRecordPermission(completionHandler: granted)
        case "photos" where declared("NSPhotoLibraryUsageDescription"):
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { granted($0 == .authorized || $0 == .limited) }
        case "location":
            Locator.shared.permission(id)
        case "notifications":
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { allowed, _ in granted(allowed) }
        default:
            answer(id, "error", "not_declared")
        }
    }

    func contentType(_ name: String) -> UTType {
        switch name {
        case "image": .image
        case "video": .movie
        case "audio": .audio
        case "pdf": .pdf
        case "text": .text
        default: .item
        }
    }

    func declared(_ key: String) -> Bool {
        Bundle.main.object(forInfoDictionaryKey: key) != nil
    }

    #if !os(tvOS)
    private func startRecording(_ id: String) {
        guard declared("NSMicrophoneUsageDescription") else { return answer(id, "error", "not_declared") }
        guard AVAudioApplication.shared.recordPermission == .granted else { return answer(id, "error", "denied") }
        let file = storage("recordings").appendingPathComponent("recording-\(stamp()).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        do {
            #if !os(macOS)
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try AVAudioSession.sharedInstance().setActive(true)
            #endif
            let created = try AVAudioRecorder(url: file, settings: settings)
            created.record()
            recorder = created
            recording = id
        } catch {
            answer(id, "error", "unavailable")
        }
    }
    #endif

    private func stopRecording() {
        guard let recorder, let recording else { return }
        recorder.stop()
        self.recorder = nil
        self.recording = nil
        #if !os(macOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        #endif
        answer(recording, "ok", recorder.url.path)
    }


    private func play(_ id: String, _ request: [String: Any]) {
        guard let url = mediaURL(request["source"] as? String ?? "") else { return answer(id, "error", "bad_source") }
        #if !os(macOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        player?.pause()
        let created = AVPlayer(url: url)
        NotificationCenter.default.addObserver(self, selector: #selector(ended(_:)), name: AVPlayerItem.didPlayToEndTimeNotification, object: created.currentItem)
        player = created
        playing = id
        created.play()
        nowPlaying(title: request["title"] as? String ?? "", artist: request["artist"] as? String ?? "")
        remoteCommands()
    }

    @objc private func ended(_ note: Notification) {
        guard let item = note.object as? AVPlayerItem, item === player?.currentItem, let playing else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        answer(playing, "ok", "finished")
    }

    private func nowPlaying(title: String, artist: String) {
        var info: [String: Any] = [MPMediaItemPropertyTitle: title, MPNowPlayingInfoPropertyPlaybackRate: 1.0]
        if !artist.isEmpty { info[MPMediaItemPropertyArtist] = artist }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        guard let item = player?.currentItem else { return }
        Task { @MainActor in
            guard let duration = try? await item.asset.load(.duration) else { return }
            Device.shared.timed(duration, of: item)
        }
    }

    private func timed(_ duration: CMTime, of item: AVPlayerItem) {
        guard item === player?.currentItem, duration.isNumeric, var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPMediaItemPropertyPlaybackDuration] = duration.seconds
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player?.currentTime().seconds ?? 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func remoteCommands() {
        guard !commandsReady else { return }
        commandsReady = true
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in self?.playback("resume"); return .success }
        center.pauseCommand.addTarget { [weak self] _ in self?.playback("pause"); return .success }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.playback(self?.player?.rate == 0 ? "resume" : "pause")
            return .success
        }
    }

    private func playback(_ command: String) {
        guard let player else { return }
        switch command {
        case "pause": player.pause()
        case "resume": player.play()
        case "stop":
            player.pause()
            self.player = nil
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        default: return
        }
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyPlaybackRate] = Double(player.rate)
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player.currentTime().seconds
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func storage(_ folder: String) -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent(folder)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    func stamp() -> String { String(Int(Date().timeIntervalSince1970 * 1000)) }

    func kept(_ url: URL, in folder: String) -> String? {
        let target = storage(folder).appendingPathComponent("\(UUID().uuidString)-\(url.lastPathComponent)")
        do {
            try FileManager.default.copyItem(at: url, to: target)
            return target.path
        } catch {
            return nil
        }
    }

    func answer(_ id: String, _ status: String, _ value: Any?) {
        answerRequest(id, status, value)
    }
}
