import UIKit
import Vision
import VisionKit
import PhotosUI

/// Photographs the printed DLS sheet and reads its text on the device (nothing is sent anywhere).
/// The page shows what was read so the umpire can check it against the paper before using it.
@MainActor
final class DLSScanner: NSObject, VNDocumentCameraViewControllerDelegate, PHPickerViewControllerDelegate {
    private var done: (([String: Any]?) -> Void)?

    /// `done` gets nil if the user cancels.
    func start(source: String, from presenter: UIViewController, done: @escaping ([String: Any]?) -> Void) {
        self.done = done
        if source == "camera" {
            guard VNDocumentCameraViewController.isSupported else {
                finish(["error": "This device can't scan with the camera. Choose a photo instead."]); return
            }
            let camera = VNDocumentCameraViewController()
            camera.delegate = self
            presenter.present(camera, animated: true)
        } else {
            var config = PHPickerConfiguration()
            config.filter = .images
            config.selectionLimit = 1
            let picker = PHPickerViewController(configuration: config)
            picker.delegate = self
            presenter.present(picker, animated: true)
        }
    }

    func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                      didFinishWith scan: VNDocumentCameraScan) {
        let image = scan.pageCount > 0 ? scan.imageOfPage(at: 0) : nil
        controller.dismiss(animated: true)
        read(image)
    }

    func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
        controller.dismiss(animated: true)
        finish(nil)
    }

    func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
        controller.dismiss(animated: true)
        finish(["error": "The camera didn't work. Check camera access in Settings, or choose a photo."])
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider else { finish(nil); return }
        guard provider.canLoadObject(ofClass: UIImage.self) else { read(nil); return }
        _ = provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            let image = object as? UIImage
            Task { @MainActor in self?.read(image) }
        }
    }

    private func read(_ image: UIImage?) {
        guard let image else { finish(["error": "Couldn't open that photo."]); return }
        // Redraw upright, no bigger than needed, so rotation can't scramble the rows.
        let scale = min(1, 3000 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let upright = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let cg = upright.cgImage else { finish(["error": "Couldn't open that photo."]); return }
        let preview = upright.jpegData(compressionQuality: 0.6)?.base64EncodedString() ?? ""

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false   // it is mostly numbers
        do {
            try VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
        } catch {
            finish(["error": "Couldn't read the text. Try again or type it in."]); return
        }
        let items: [[String: Any]] = (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let box = observation.boundingBox
            return ["t": text, "x": Double(box.minX), "y": Double(box.minY), "h": Double(box.height)]
        }
        finish(["items": items, "image": preview])
    }

    private func finish(_ result: [String: Any]?) {
        let callback = done
        done = nil
        callback?(result)
    }
}
