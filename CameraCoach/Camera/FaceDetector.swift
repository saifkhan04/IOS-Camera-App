// FaceDetector.swift
// Wraps VNDetectFaceRectanglesRequest into a simple per-frame utility.
//
// Vision framework overview:
//   VNRequest         — a description of what to detect (faces, barcodes, etc.)
//   VNImageRequestHandler — runs one or more requests against a single image
//   VNObservation     — one result returned by a request
//
// The request object (VNDetectFaceRectanglesRequest) is created ONCE and
// reused every frame. Creating it per-frame would waste time re-loading
// the underlying Core ML model from disk each call.

import Vision
import CoreVideo

class FaceDetector {

    private let request = VNDetectFaceRectanglesRequest()

    // Detects the largest face in the pixel buffer and returns its bounding
    // box in normalized AVFoundation coordinates: origin top-left, y-down,
    // both axes in [0, 1]. Returns nil if no face is detected.
    //
    // Orientation — why .right?
    //   The pixel buffer from AVCaptureVideoDataOutput is in the camera
    //   sensor's native orientation: landscape (wider than tall).
    //   When you hold the iPhone portrait, the sensor's "up" direction
    //   points to the RIGHT side of the raw buffer.
    //   CGImagePropertyOrientation.right tells Vision to rotate the image
    //   90° CW before analysis, so faces appear upright to the detector.
    //   Without this hint, Vision sees a sideways face and detection drops.
    //
    // Coordinate flip — why flip Y?
    //   Vision returns bounding boxes in CoreGraphics PDF space:
    //     origin = bottom-left, y increases upward.
    //   AVFoundation (and UIKit) use screen space:
    //     origin = top-left, y increases downward.
    //   We convert once here so all callers work in one consistent system.
    func detectFace(in pixelBuffer: CVPixelBuffer) -> CGRect? {
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .right,
            options: [:]
        )
        try? handler.perform([request])

        // If multiple faces are visible, pick the largest bounding box —
        // it's most likely the intended subject closest to the camera.
        guard let observation = request.results?.max(by: {
            $0.boundingBox.width < $1.boundingBox.width
        }) else { return nil }

        let v = observation.boundingBox
        // Vision: origin bottom-left, y-up  →  AVFoundation: origin top-left, y-down
        return CGRect(
            x: v.origin.x,
            y: 1.0 - v.origin.y - v.height,
            width: v.width,
            height: v.height
        )
    }
}
