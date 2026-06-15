// CameraPreviewView.swift
// Bridges AVFoundation's camera preview into SwiftUI.
//
// SwiftUI has no built-in camera preview widget. The preview is rendered by
// AVCaptureVideoPreviewLayer (a CALayer subclass), so we wrap a UIView that's
// backed by that layer in a UIViewRepresentable.

import SwiftUI
import AVFoundation

struct CameraPreviewView: UIViewRepresentable {

    let session: AVCaptureSession

    // ContentView captures the layer reference so it can convert normalised
    // face coordinates to screen points for the overlay.
    var onLayerReady: ((AVCaptureVideoPreviewLayer) -> Void)? = nil

    // Fired when the physical Camera Control button is pressed.
    var onCameraControl: (() -> Void)? = nil

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        // resizeAspectFill: scale the feed to fill the view, cropping the
        // sides if the camera's aspect ratio differs from the screen's.
        // Same behaviour as the native Camera app.
        view.previewLayer.videoGravity = .resizeAspectFill
        // Fire the callback so ContentView can store the layer reference.
        // The layer exists now, though its final bounds are set after layout.
        onLayerReady?(view.previewLayer)

        // Attach the Camera Control button interaction, if a handler was given.
        if let onCameraControl {
            view.cameraControlHandler.attach(to: view, onPress: onCameraControl)
        }
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}
}

// MARK: - PreviewUIView

// A UIView whose backing layer is AVCaptureVideoPreviewLayer.
//
// Every UIView is backed by a CALayer that handles drawing. By overriding
// layerClass we replace the default CALayer with AVCaptureVideoPreviewLayer
// — a specialised layer that renders camera frames on the GPU efficiently.
// The layer IS the view's bounds, so it auto-resizes with no extra code.
class PreviewUIView: UIView {

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    // Owns the Camera Control interaction so it stays alive with the view.
    let cameraControlHandler = CameraControlHandler()
}
