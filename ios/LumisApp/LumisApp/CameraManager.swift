import AVFoundation
import UIKit
import Combine

/// Always-running back-camera session with on-demand still capture.
final class CameraManager: NSObject, ObservableObject {
    let session = AVCaptureSession()

    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "lumis.camera.session")
    private var configured = false
    private var continuation: CheckedContinuation<UIImage?, Never>?

    /// Configure (once) and start the live feed.
    func start() {
        queue.async {
            self.configureIfNeeded()
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    func stop() {
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    private func configureIfNeeded() {
        guard !configured else { return }
        configured = true

        session.beginConfiguration()
        session.sessionPreset = .photo

        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
        }
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        session.commitConfiguration()
    }

    /// Capture a still frame from the live feed.
    func capturePhoto() async -> UIImage? {
        await withCheckedContinuation { (cont: CheckedContinuation<UIImage?, Never>) in
            queue.async {
                guard self.session.isRunning else {
                    cont.resume(returning: nil)
                    return
                }
                self.continuation = cont
                let settings = AVCapturePhotoSettings()
                self.output.capturePhoto(with: settings, delegate: self)
            }
        }
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        let image = photo.fileDataRepresentation().flatMap { UIImage(data: $0) }
        let cont = continuation
        continuation = nil
        cont?.resume(returning: image)
    }
}
