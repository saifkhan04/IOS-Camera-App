// CameraManager.swift
// Owns and configures the AVCaptureSession.
//
// Day 2 adds two major pieces on top of Day 1:
//
// 1. AVCaptureDataOutputSynchronizer
//    Video frames and LiDAR depth frames arrive on different internal queues
//    at slightly different times. If we processed them independently we could
//    accidentally pair a video frame with a depth map from 33 ms earlier.
//    The synchronizer watches both outputs, waits until it has a matched pair
//    (same presentation timestamp), then delivers them together to a single
//    delegate method. This replaces the individual setSampleBufferDelegate
//    calls — the synchronizer takes over frame delivery entirely.
//
// 2. Face detection + depth sampling pipeline
//    Each matched pair: detect face (Vision) → sample depth at face center
//    (LiDAR) → publish results to SwiftUI on the main thread.

import AVFoundation
import Combine

class CameraManager: NSObject, ObservableObject {

    // MARK: - Public

    let session = AVCaptureSession()

    // SwiftUI reads these. @Published triggers a re-render whenever they change.
    // nil means "no face detected" or "no depth reading" for this frame.
    @Published var faceNormRect: CGRect?      // portrait, top-left origin, 0–1
    @Published var subjectDistance: Float?    // metres, from LiDAR

    // MARK: - Private: Outputs

    private let videoOutput = AVCaptureVideoDataOutput()
    private let depthOutput = AVCaptureDepthDataOutput()

    // Synchronizer is created after both outputs are added to the session.
    // Stored as a property so ARC keeps it alive for the session's lifetime.
    private var synchronizer: AVCaptureDataOutputSynchronizer?

    // True only when depthOutput was added AND has a live connection.
    // AVCaptureDataOutputSynchronizer crashes if any output it's given
    // has no connection — this flag lets us exclude depth gracefully when
    // the selected format doesn't support LiDAR delivery.
    private var depthConnected = false

    // MARK: - Private: Processing

    // Reused every frame — see FaceDetector.swift for why.
    private let faceDetector = FaceDetector()

    // MARK: - Private: Threading

    private let sessionQueue = DispatchQueue(
        label: "com.cameracoach.session",
        qos: .userInitiated
    )

    // MARK: - Lifecycle

    func start() {
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
        session.beginConfiguration()
        session.sessionPreset = .photo
        addCameraInput()
        addVideoOutput()
        addDepthOutput()

        // Synchronizer requires every output it receives to already have a
        // live connection to the session. The .photo preset can pick a format
        // that doesn't support LiDAR depth, leaving depthOutput with no
        // connection. We check depthConnected and only include depth when it's
        // actually wired up — otherwise the initialiser throws a fatal error.
        let syncOutputs: [AVCaptureOutput] = depthConnected
            ? [videoOutput, depthOutput]
            : [videoOutput]
        synchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: syncOutputs)
        synchronizer?.setDelegate(self, queue: sessionQueue)

        session.commitConfiguration()
    }

    private func addCameraInput() {
        guard
            let device = AVCaptureDevice.default(
                .builtInWideAngleCamera, for: .video, position: .back
            ),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            print("⚠️ CameraManager: Could not add camera input")
            return
        }
        session.addInput(input)
        print("✅ CameraManager: Camera input added")
    }

    private func addVideoOutput() {
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        // setSampleBufferDelegate is intentionally NOT called here.
        // The synchronizer takes over all frame delivery for this output.
        guard session.canAddOutput(videoOutput) else {
            print("⚠️ CameraManager: Cannot add video output")
            return
        }
        session.addOutput(videoOutput)
        print("✅ CameraManager: Video output added")
    }

    private func addDepthOutput() {
        depthOutput.isFilteringEnabled = true
        guard session.canAddOutput(depthOutput) else {
            print("⚠️ CameraManager: Cannot add depth output (no LiDAR?)")
            return
        }
        session.addOutput(depthOutput)
        // A connection exists only when the active format supports depth.
        // The .photo preset may choose a high-resolution format (e.g. 48 MP)
        // that doesn't deliver LiDAR data. We record whether we actually got
        // a connection so the synchronizer can be built safely.
        depthConnected = depthOutput.connection(with: .depthData) != nil
        print(depthConnected
            ? "✅ CameraManager: Depth output connected (LiDAR active)"
            : "⚠️ CameraManager: Depth output added but no connection — format may not support depth"
        )
    }
}

// MARK: - AVCaptureDataOutputSynchronizerDelegate

extension CameraManager: AVCaptureDataOutputSynchronizerDelegate {

    // Called on sessionQueue for every matched video+depth pair.
    func dataOutputSynchronizer(
        _ synchronizer: AVCaptureDataOutputSynchronizer,
        didOutput collection: AVCaptureSynchronizedDataCollection
    ) {
        // --- Extract video frame ---
        // synchronizedData(for:) looks up the matching data for a specific
        // output in this synchronized collection.
        guard
            let syncedVideo = collection
                .synchronizedData(for: videoOutput) as? AVCaptureSynchronizedSampleBufferData,
            !syncedVideo.sampleBufferWasDropped,
            let pixelBuffer = CMSampleBufferGetImageBuffer(syncedVideo.sampleBuffer)
        else { return }

        // --- Face detection (Vision, on sessionQueue) ---
        let faceRect = faceDetector.detectFace(in: pixelBuffer)

        // --- LiDAR depth at face centre ---
        var distance: Float? = nil
        if let faceRect,
           let syncedDepth = collection
               .synchronizedData(for: depthOutput) as? AVCaptureSynchronizedDepthData,
           !syncedDepth.depthDataWasDropped
        {
            distance = sampleDepth(
                from: syncedDepth.depthData,
                at: CGPoint(x: faceRect.midX, y: faceRect.midY)
            )
        }

        // --- Publish to SwiftUI (must be on main thread) ---
        DispatchQueue.main.async { [weak self] in
            self?.faceNormRect     = faceRect
            self?.subjectDistance  = distance
        }
    }

    // MARK: - Depth sampling

    // Returns the average depth (metres) sampled from a 5×5 pixel patch
    // centred on a normalised point, ignoring NaN and near-zero values.
    //
    // Why a patch?
    //   LiDAR reports NaN for specular surfaces — hair, glasses, earrings.
    //   A single pixel at the exact face centre often hits one of these.
    //   Averaging a small neighbourhood smooths over those bad pixels.
    //
    // Coordinate note:
    //   normalizedPoint comes from the Vision face rect (portrait space).
    //   The depth map is in the sensor's native landscape orientation, so
    //   an exact mapping requires a coordinate transform. For Day 2 we pass
    //   portrait coords directly; the error is small for centre-frame faces
    //   and imperceptible for the guidance text. Day 3 adds the exact transform.
    private func sampleDepth(from depthData: AVDepthData, at normalizedPoint: CGPoint) -> Float? {
        // Convert to float32 depth (metres) if the hardware delivered a
        // different format (e.g. float16 disparity on some configurations).
        let metersData = depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        let map = metersData.depthDataMap

        CVPixelBufferLockBaseAddress(map, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }

        let mapW = CVPixelBufferGetWidth(map)
        let mapH = CVPixelBufferGetHeight(map)
        guard let base = CVPixelBufferGetBaseAddress(map) else { return nil }

        // bytesPerRow can include hardware padding at the end of each row.
        // Dividing by Float32's byte size gives the actual number of floats
        // to skip to reach the next row — which may be larger than mapW.
        let rowStride = CVPixelBufferGetBytesPerRow(map) / MemoryLayout<Float32>.size
        let floats = base.assumingMemoryBound(to: Float32.self)

        let cx = Int(normalizedPoint.x * CGFloat(mapW))
        let cy = Int(normalizedPoint.y * CGFloat(mapH))

        var sum: Float = 0
        var count = 0
        for dy in -2...2 {
            for dx in -2...2 {
                let px = Swift.max(0, Swift.min(cx + dx, mapW - 1))
                let py = Swift.max(0, Swift.min(cy + dy, mapH - 1))
                let v  = floats[py * rowStride + px]
                if !v.isNaN && v > 0.1 {
                    sum += v
                    count += 1
                }
            }
        }
        return count > 0 ? sum / Float(count) : nil
    }
}
