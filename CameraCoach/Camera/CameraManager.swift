// CameraManager.swift
// Owns and configures the AVCaptureSession — the central object in
// AVFoundation that wires camera hardware to processing pipelines.
//
// Think of AVCaptureSession as a switchboard:
//   Inputs  → physical hardware (camera lens, LiDAR scanner)
//   Outputs → destinations for the data (our frame processor, depth processor,
//             photo capture)
//
// You configure the session by adding inputs and outputs, then call
// startRunning() to begin the flow of data. Frames start arriving on
// the output delegate callbacks immediately after.
//
// Threading model (IMPORTANT):
//   All AVCaptureSession configuration MUST happen on a background queue.
//   Frame delivery also happens on a background queue (sessionQueue).
//   UI updates must happen on the main queue.
//   Violating this causes crashes or silent frame drops.

import AVFoundation
import Combine

class CameraManager: NSObject, ObservableObject {

    // MARK: - Public

    // The session is exposed so CameraPreviewView can attach its
    // preview layer to it. The layer subscribes directly to the session
    // and renders frames without us doing anything extra.
    let session = AVCaptureSession()

    // MARK: - Private: Outputs

    // AVCaptureVideoDataOutput delivers raw video frames to our delegate.
    // Each frame is a CMSampleBuffer containing a CVPixelBuffer —
    // the raw pixel data that we'll pass into our C++ pipeline.
    private let videoOutput = AVCaptureVideoDataOutput()

    // AVCaptureDepthDataOutput delivers LiDAR depth maps synchronized
    // with video frames. Each depth map is a 2D float buffer where
    // each pixel = distance in meters from the camera to that point.
    // This is wired up fully in Day 2 using AVCaptureDataOutputSynchronizer.
    private let depthOutput = AVCaptureDepthDataOutput()

    // MARK: - Private: Threading

    // A serial DispatchQueue dedicated to camera work.
    // Serial means tasks run one at a time in order — no concurrency.
    // We use .userInitiated QoS (Quality of Service) because camera
    // processing is latency-sensitive: delayed frames feel laggy.
    private let sessionQueue = DispatchQueue(
        label: "com.cameracoach.session",
        qos: .userInitiated
    )

    // MARK: - Lifecycle

    func start() {
        // Jump to the background queue for all session work.
        // async means this returns immediately to the caller —
        // the camera starts up without blocking the UI thread.
        sessionQueue.async { [weak self] in
            self?.configure()
            self?.session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }

    // MARK: - Configuration

    private func configure() {
        // beginConfiguration / commitConfiguration batch all changes
        // so the session applies them atomically. Without this, adding
        // an input and then an output could cause a brief invalid state.
        session.beginConfiguration()

        // --- Session preset ---
        // .photo gives us the highest quality frames the sensor can
        // produce, which matters for the 48MP main camera on iPhone 17 Pro.
        // Alternatives like .high or .hd1920x1080 downsample the sensor.
        //
        // Note: "photo" here means "camera configuration optimised for
        // still capture" — it doesn't prevent us from also getting video
        // frames for our real-time guidance pipeline.
        session.sessionPreset = .photo

        // --- Input: Back camera ---
        // .builtInWideAngleCamera = the main lens (the one you use most).
        // On iPhone 17 Pro this is the 48MP f/1.78 primary camera.
        // We'll add lens selection (ultra-wide, telephoto) post-MVP.
        addCameraInput()

        // --- Output: Video frames ---
        addVideoOutput()

        // --- Output: LiDAR depth ---
        // Added now so the session knows it needs to activate the
        // LiDAR scanner. Full depth processing wired up in Day 2.
        addDepthOutput()

        session.commitConfiguration()
    }

    private func addCameraInput() {
        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ) else {
            print("⚠️ CameraManager: No back camera found")
            return
        }

        guard let input = try? AVCaptureDeviceInput(device: device) else {
            print("⚠️ CameraManager: Could not create camera input")
            return
        }

        guard session.canAddInput(input) else {
            print("⚠️ CameraManager: Session cannot add camera input")
            return
        }

        session.addInput(input)
        print("✅ CameraManager: Camera input added")
    }

    private func addVideoOutput() {
        // Pixel format selection — this is a key image processing decision.
        //
        // kCVPixelFormatType_420YpCbCr8BiPlanarFullRange is the iPhone
        // camera's NATIVE output format. Breaking down the name:
        //   420        → YCbCr 4:2:0 chroma subsampling (color channels are
        //                at half resolution — the eye is less sensitive to color
        //                than brightness, so this saves bandwidth with no
        //                visible quality loss)
        //   YpCbCr     → Y' (luma/brightness) + Cb (blue chroma) + Cr (red chroma)
        //   8          → 8 bits per channel
        //   BiPlanar   → stored in two memory planes:
        //                  Plane 0: Y channel, full resolution (width × height bytes)
        //                  Plane 1: CbCr interleaved, half resolution
        //   FullRange  → Y values span 0–255 (vs limited range 16–235)
        //
        // We choose this format because:
        //   1. No format conversion cost — it's what the hardware produces
        //   2. Our C++ LuminanceAnalyzer reads the Y plane directly
        //   3. It's the format Vision framework also expects
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]

        // alwaysDiscardsLateVideoFrames: if our processing can't keep
        // up with 30fps, drop frames rather than queuing them. Queuing
        // would cause the guidance to lag behind reality — worse than
        // dropping a frame.
        videoOutput.alwaysDiscardsLateVideoFrames = true

        // setSampleBufferDelegate: tells AVFoundation to call our
        // captureOutput(_:didOutput:from:) method for each frame,
        // on sessionQueue (same queue, so no extra context switches).
        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)

        guard session.canAddOutput(videoOutput) else {
            print("⚠️ CameraManager: Cannot add video output")
            return
        }
        session.addOutput(videoOutput)
        print("✅ CameraManager: Video output added")
    }

    private func addDepthOutput() {
        // isFilteringEnabled applies a temporal smoothing filter to the
        // depth map — it reduces frame-to-frame flicker in the LiDAR data.
        // This makes distance readings more stable, which means the
        // "step 0.4m closer" message won't jitter between frames.
        depthOutput.isFilteringEnabled = true

        guard session.canAddOutput(depthOutput) else {
            // Depth output fails gracefully on devices without LiDAR.
            // We check for this in Day 2 before using depth values.
            print("⚠️ CameraManager: Cannot add depth output (no LiDAR?)")
            return
        }
        session.addOutput(depthOutput)
        print("✅ CameraManager: Depth output added (LiDAR active)")
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

// This protocol has one key method that fires for every video frame.
// The `extension` keyword keeps delegate code separate from setup code
// — a Swift convention for readable organisation.
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // CMSampleBuffer is a wrapper around the raw frame data.
        // CMSampleBufferGetImageBuffer extracts the CVPixelBuffer —
        // the actual memory block containing pixel data.
        //
        // CVPixelBuffer is what we pass to:
        //   - Vision framework for face detection
        //   - Our C++ LuminanceAnalyzer for brightness computation
        //
        // Day 1: just confirm frames arrive. We'll process them in Day 3.
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        // Width and height of the frame in pixels.
        // On iPhone 17 Pro with .photo preset, this can be up to 4032×3024.
        let width  = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let _ = (width, height)   // suppress unused warning for now
    }
}
