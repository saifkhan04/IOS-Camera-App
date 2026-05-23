// CameraPreviewView.swift
// Bridges AVFoundation's camera preview into SwiftUI.
//
// SwiftUI has no built-in camera preview widget. The preview is rendered
// by AVCaptureVideoPreviewLayer, which is a CALayer subclass — part of
// UIKit's older layer-based drawing system. To use it in SwiftUI, we
// wrap a UIView in a UIViewRepresentable.
//
// UIViewRepresentable is the standard SwiftUI protocol for wrapping
// any UIKit view. You implement two required methods:
//   makeUIView  — called once to CREATE the UIKit view
//   updateUIView — called whenever SwiftUI state changes and the
//                  UIKit view might need updating
//
// Think of this file as a translation layer: SwiftUI speaks "views",
// AVFoundation speaks "layers". This file translates between them.

import SwiftUI
import AVFoundation

struct CameraPreviewView: UIViewRepresentable {

    // The session is the AVFoundation object that owns the camera pipeline.
    // We pass it in from CameraManager rather than creating it here, because
    // the session needs to outlive this view and be shared with outputs.
    let session: AVCaptureSession

    // MARK: - UIViewRepresentable

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        // Attach the session to the preview layer. The layer subscribes
        // to the session's frame output and renders each frame automatically.
        view.previewLayer.session = session
        // .resizeAspectFill: scale the camera feed to fill the view,
        // cropping the sides if necessary. Same as the native Camera app.
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    // We have nothing to update dynamically — the session is set once
    // and the layer handles everything after that.
    func updateUIView(_ uiView: PreviewUIView, context: Context) {}
}

// MARK: - PreviewUIView

// A UIView whose backing layer is AVCaptureVideoPreviewLayer.
//
// Every UIView is backed by a CALayer that handles the actual drawing.
// By default it's a plain CALayer. By overriding layerClass, we replace
// it with AVCaptureVideoPreviewLayer — a special layer that knows how
// to render camera frames efficiently using the GPU.
//
// This approach is more efficient than adding the preview layer as a
// sublayer manually, because the preview layer IS the view's bounds —
// it auto-resizes with the view with no extra code.
class PreviewUIView: UIView {

    override class var layerClass: AnyClass {
        // Returning this class makes UIKit instantiate an
        // AVCaptureVideoPreviewLayer as the view's `layer` property
        // instead of the default CALayer.
        AVCaptureVideoPreviewLayer.self
    }

    // Convenience accessor so callers don't need to cast layer themselves.
    var previewLayer: AVCaptureVideoPreviewLayer {
        // Safe force-cast: we guarantee this is always an
        // AVCaptureVideoPreviewLayer because of layerClass above.
        layer as! AVCaptureVideoPreviewLayer
    }
}
