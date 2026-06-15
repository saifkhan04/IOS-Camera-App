// PhotoCaptureProcessor.swift
// Handles the lifecycle of a SINGLE AVCapturePhotoOutput capture, then writes
// the result to the user's Photos library.
//
// Why a separate object per shot? AVCapturePhotoOutput holds its delegate
// WEAKLY and drives a multi-step async callback sequence (willCapture →
// didFinishProcessing). If we made CameraManager the delegate we'd have to
// juggle overlapping captures by hand. Instead CameraManager creates one of
// these per shutter press and retains it (keyed by the settings' uniqueID)
// until onFinish fires — the textbook AVFoundation capture pattern.

import AVFoundation
import Photos
import ImageIO
import UIKit

final class PhotoCaptureProcessor: NSObject {

    enum CaptureError: LocalizedError {
        case noData          // photo produced no encodable file data
        case noPhotoAccess   // user denied add-to-library permission

        var errorDescription: String? {
            switch self {
            case .noData:       return "The camera returned no image data."
            case .noPhotoAccess: return "Photos access is required to save the shot."
            }
        }
    }

    // Fires the instant the sensor exposes — used to drive the screen flash so
    // the flash lines up with the actual capture, not the button press.
    private let onWillCapture: () -> Void
    // Called on the MAIN queue once the shot is saved, with a downscaled
    // thumbnail (corner button) and the full encoded bytes (in-app viewer).
    private let onSaved: (UIImage, Data) -> Void
    // Called on the MAIN queue with success/failure once the photo is saved.
    private let onFinish: (Result<Void, Error>) -> Void

    init(onWillCapture: @escaping () -> Void,
         onSaved: @escaping (UIImage, Data) -> Void,
         onFinish: @escaping (Result<Void, Error>) -> Void) {
        self.onWillCapture = onWillCapture
        self.onSaved = onSaved
        self.onFinish = onFinish
    }

    private func finish(_ result: Result<Void, Error>) {
        DispatchQueue.main.async { [onFinish] in onFinish(result) }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension PhotoCaptureProcessor: AVCapturePhotoCaptureDelegate {

    // Sensor is about to expose — tell the UI to flash now.
    func photoOutput(_ output: AVCapturePhotoOutput,
                     willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        DispatchQueue.main.async { [onWillCapture] in onWillCapture() }
    }

    // The processed (ISP-developed) photo is ready. fileDataRepresentation()
    // hands back the fully-encoded HEIF/JPEG bytes — exactly what we write to
    // the library, so the saved file is byte-for-byte the camera's output.
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        if let error { finish(.failure(error)); return }
        guard let data = photo.fileDataRepresentation() else {
            finish(.failure(CaptureError.noData)); return
        }
        save(data)
    }

    // MARK: - Save to Photos

    private func save(_ data: Data) {
        // .addOnly is the minimal scope — we only ever write, never read the
        // library — so iOS shows the lighter "Add only" permission prompt.
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard let self else { return }
            guard status == .authorized || status == .limited else {
                self.finish(.failure(CaptureError.noPhotoAccess)); return
            }
            PHPhotoLibrary.shared().performChanges {
                // .photo resource with the raw file data preserves the original
                // codec + EXIF; no re-encode, no quality loss.
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            } completionHandler: { [weak self] ok, err in
                guard let self else { return }
                if let err {
                    self.finish(.failure(err))
                } else if ok {
                    // Only surface the shot once it's actually in the library —
                    // so the gallery button never points at a save that failed.
                    if let thumb = Self.makeThumbnail(from: data) {
                        DispatchQueue.main.async { [onSaved = self.onSaved] in
                            onSaved(thumb, data)
                        }
                    }
                    self.finish(.success(()))
                } else {
                    self.finish(.failure(CaptureError.noData))
                }
            }
        }
    }

    // Decode just a small thumbnail straight from the encoded bytes via ImageIO
    // — far cheaper than decoding the full ~12MP image and downscaling.
    // kCGImageSourceCreateThumbnailWithTransform applies the EXIF orientation so
    // the thumbnail is upright.
    private static func makeThumbnail(from data: Data, maxPixel: CGFloat = 240) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
