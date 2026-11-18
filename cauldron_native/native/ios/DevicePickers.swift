import AVFoundation
import PhotosUI
import UIKit
import UniformTypeIdentifiers

extension Device {
    func openURL(_ url: URL) { UIApplication.shared.open(url) }

    #if os(tvOS)
    func haptic(_ style: String) {}

    func pickPhotos(_ id: String, limit: Int, videos: Bool) { answer(id, "error", "unsupported") }

    func capture(_ id: String, video: Bool) { answer(id, "error", "unsupported") }

    func pickFiles(_ id: String, types: [String], many: Bool) { answer(id, "error", "unsupported") }

    func startRecording(_ id: String) { answer(id, "error", "unsupported") }

    func share(text: String?, file: String?) {}
    #else
    func haptic(_ style: String) {
        switch style {
        case "selection": UISelectionFeedbackGenerator().selectionChanged()
        case "success": UINotificationFeedbackGenerator().notificationOccurred(.success)
        case "warning": UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case "error": UINotificationFeedbackGenerator().notificationOccurred(.error)
        default: UIImpactFeedbackGenerator(style: impact(style)).impactOccurred()
        }
    }

    func impact(_ style: String) -> UIImpactFeedbackGenerator.FeedbackStyle {
        switch style {
        case "medium": .medium
        case "heavy": .heavy
        case "soft": .soft
        case "rigid": .rigid
        default: .light
        }
    }
    #endif

    func present(_ controller: UIViewController, id: String) {
        guard let top = topController() else { return answer(id, "error", "no_screen") }
        pending[ObjectIdentifier(controller)] = id
        if let popover = controller.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        top.present(controller, animated: true)
    }

    func topController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController ?? scene?.windows.first?.rootViewController
        while let shown = top?.presentedViewController { top = shown }
        return top
    }

    func finish(_ controller: UIViewController, _ status: String, _ value: Any?) {
        guard let id = pending.removeValue(forKey: ObjectIdentifier(controller)) else { return }
        controller.dismiss(animated: true)
        answer(id, status, value)
    }

    #if !os(tvOS)
    func pickPhotos(_ id: String, limit: Int, videos: Bool) {
        var configuration = PHPickerConfiguration()
        configuration.selectionLimit = limit
        configuration.filter = videos ? .any(of: [.images, .videos]) : .images
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, id: id)
    }

    func capture(_ id: String, video: Bool) {
        guard declared("NSCameraUsageDescription"), !video || declared("NSMicrophoneUsageDescription") else {
            return answer(id, "error", "not_declared")
        }
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return answer(id, "error", "unavailable") }
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [video ? UTType.movie.identifier : UTType.image.identifier]
        picker.delegate = self
        present(picker, id: id)
    }

    func pickFiles(_ id: String, types: [String], many: Bool) {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types.map(contentType), asCopy: true)
        picker.allowsMultipleSelection = many
        picker.delegate = self
        present(picker, id: id)
    }

    #endif

    #if !os(tvOS)
    func share(text: String?, file: String?) {
        let controller = UIActivityViewController(activityItems: [shared(text: text, file: file)], applicationActivities: nil)
        guard let top = topController() else { return }
        if let popover = controller.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        top.present(controller, animated: true)
    }

    func shared(text: String?, file: String?) -> Any {
        if let file { return URL(fileURLWithPath: file) }
        let text = text ?? ""
        if text.hasPrefix("http://") || text.hasPrefix("https://"), let url = URL(string: text) { return url }
        return text
    }
    #endif
}

#if !os(tvOS)
extension Device: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        guard !results.isEmpty else { return finish(picker, "cancelled", nil) }
        let group = DispatchGroup()
        var paths = [String?](repeating: nil, count: results.count)
        for (index, result) in results.enumerated() {
            let provider = result.itemProvider
            let type = provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) ? UTType.movie : UTType.image
            group.enter()
            provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { [weak self] url, _ in
                let path = url.flatMap { self?.kept($0, in: "picked") }
                DispatchQueue.main.async {
                    paths[index] = path
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) { [weak self] in
            self?.finish(picker, "ok", paths.compactMap { $0 })
        }
    }
}

extension Device: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        if let movie = info[.mediaURL] as? URL {
            return finish(picker, "ok", kept(movie, in: "captures") as Any)
        }
        let file = storage("captures").appendingPathComponent("capture-\(stamp()).jpg")
        guard let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.9),
              (try? data.write(to: file)) != nil else {
            return finish(picker, "error", "unavailable")
        }
        finish(picker, "ok", file.path)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        finish(picker, "cancelled", nil)
    }
}

extension Device: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        finish(controller, "ok", urls.compactMap { kept($0, in: "files") })
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        finish(controller, "cancelled", nil)
    }
}
#endif
