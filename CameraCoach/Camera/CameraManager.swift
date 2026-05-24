// CameraManager.swift
// Owns and configures the AVCaptureSession.
//
// Day 2 note — why we don't use sessionPreset:
//   sessionPreset = .photo lets Apple pick the format automatically.
//   On iPhone 17 Pro it often selects the 48 MP mode, which doesn't support
//   simultaneous LiDAR depth delivery. Instead we enumerate the device's
//   available formats, find the highest-resolution one that has
//   supportedDepthDataFormats, and set it directly. Setting activeFormat
//   manually causes AVFoundation to silently change the preset to
//   .inputPriority — that's expected and fine.

import AVFoundation
import Combine

class CameraManager: NSObject, ObservableObject {

    // MARK: - Public

    let session = AVCaptureSession()

    @Published var faceNormRect: CGRect?      // portrait, top-left origin, 0–1
    @Published var subjectDistance: Float?    // metres, from LiDAR

    // MARK: - Private: Outputs

    private let videoOutput = AVCaptureVideoDataOutput()
    private let depthOutput = AVCaptureDepthDataOutput()
    private var synchronizer: AVCaptureDataOutputSynchronizer?
    private var depthConnected = false

    // MARK: - Private: Processing

    private let faceDetector = FaceDetector()
    private var frameCount = 0

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

        // No preset — we pick the format manually so we can guarantee
        // depth support. See selectDepthCapableFormat below.
        guard let device = addCameraInput() else {
            session.commitConfiguration()
            return
        }

        addVideoOutput()
        addDepthOutput()
        selectDepthCapableFormat(for: device)

        session.commitConfiguration()

        // Check connections AFTER commitConfiguration — connections are
        // fully resolved once the session applies all pending changes.
        depthConnected = depthOutput.connection(with: .depthData) != nil
        print("📊 depthOutput.connections count: \(depthOutput.connections.count)")
        print("📊 depthOutput.connection(with: .depthData): \(String(describing: depthOutput.connection(with: .depthData)))")
        print(depthConnected
            ? "✅ CameraManager: Depth connection confirmed"
            : "⚠️ CameraManager: Still no depth connection after format selection"
        )

        // AVCaptureDataOutputSynchronizer crashes if any output it receives
        // lacks a live connection. Only include depthOutput when it's connected.
        let syncOutputs: [AVCaptureOutput] = depthConnected
            ? [videoOutput, depthOutput]
            : [videoOutput]
        synchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: syncOutputs)
        synchronizer?.setDelegate(self, queue: sessionQueue)
    }

    // Returns the device so configure() can pass it to selectDepthCapableFormat.
    @discardableResult
    private func addCameraInput() -> AVCaptureDevice? {
        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera, for: .video, position: .back
        ) else {
            print("⚠️ CameraManager: No back camera found")
            return nil
        }
        guard let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            print("⚠️ CameraManager: Could not add camera input")
            return nil
        }
        session.addInput(input)
        print("✅ CameraManager: Camera input added")
        return device
    }

    private func addVideoOutput() {
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        // No setSampleBufferDelegate — the synchronizer handles delivery.
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
        print("✅ CameraManager: Depth output added")
    }

    // Picks the highest-resolution video format that also supports depth data,
    // then sets the matching depth format on the device.
    //
    // Why this is necessary:
    //   AVCaptureDevice.formats lists every mode the sensor supports.
    //   Each format has a supportedDepthDataFormats array — if it's empty,
    //   that mode cannot deliver LiDAR depth alongside video. The 48 MP
    //   ProRAW / HEIF format on iPhone 17 Pro typically has no depth formats.
    //   We skip those and pick the best one that does.
    private func selectDepthCapableFormat(for device: AVCaptureDevice) {
        let allFormats = device.formats
        print("📊 Total formats on device: \(allFormats.count)")

        let depthCapable = allFormats.filter { !$0.supportedDepthDataFormats.isEmpty }
        print("📊 Depth-capable formats: \(depthCapable.count)")

        guard !depthCapable.isEmpty else {
            print("⚠️ CameraManager: Device has no depth-capable formats")
            return
        }

        // Log a few depth-capable formats so we can see what's available.
        for f in depthCapable.prefix(5) {
            let d = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
            print("   depth-capable: \(d.width)×\(d.height), depthFormats: \(f.supportedDepthDataFormats.count)")
        }

        let best = depthCapable.max {
            CMVideoFormatDescriptionGetDimensions($0.formatDescription).width <
            CMVideoFormatDescriptionGetDimensions($1.formatDescription).width
        }!

        let bestDepth = best.supportedDepthDataFormats.max {
            CMVideoFormatDescriptionGetDimensions($0.formatDescription).width <
            CMVideoFormatDescriptionGetDimensions($1.formatDescription).width
        }

        do {
            try device.lockForConfiguration()
            device.activeFormat = best
            if let bestDepth { device.activeDepthDataFormat = bestDepth }
            device.unlockForConfiguration()

            let dims = CMVideoFormatDescriptionGetDimensions(best.formatDescription)
            print("✅ CameraManager: Active format → \(dims.width)×\(dims.height)")
        } catch {
            print("⚠️ CameraManager: Could not lock device for format selection: \(error)")
        }
    }
}

// MARK: - AVCaptureDataOutputSynchronizerDelegate

extension CameraManager: AVCaptureDataOutputSynchronizerDelegate {

    func dataOutputSynchronizer(
        _ synchronizer: AVCaptureDataOutputSynchronizer,
        didOutput collection: AVCaptureSynchronizedDataCollection
    ) {
        guard
            let syncedVideo = collection
                .synchronizedData(for: videoOutput) as? AVCaptureSynchronizedSampleBufferData,
            !syncedVideo.sampleBufferWasDropped,
            let pixelBuffer = CMSampleBufferGetImageBuffer(syncedVideo.sampleBuffer)
        else { return }

        let faceRect = faceDetector.detectFace(in: pixelBuffer)

        var distance: Float? = nil
        if let faceRect {
            // Diagnose depth pipeline once per ~second (every 30 frames).
            let raw = collection.synchronizedData(for: depthOutput)
            if frameCount % 30 == 0 {
                print("📊 depth raw: \(String(describing: type(of: raw))), faceRect: \(faceRect)")
            }
            if let syncedDepth = raw as? AVCaptureSynchronizedDepthData,
               !syncedDepth.depthDataWasDropped {
                distance = sampleDepth(
                    from: syncedDepth.depthData,
                    at: CGPoint(x: faceRect.midX, y: faceRect.midY)
                )
                if frameCount % 30 == 0 {
                    print("📊 distance: \(String(describing: distance))")
                }
            }
        }
        frameCount += 1

        DispatchQueue.main.async { [weak self] in
            self?.faceNormRect     = faceRect
            self?.subjectDistance  = distance
        }
    }

    // MARK: - Depth sampling

    private func sampleDepth(from depthData: AVDepthData, at normalizedPoint: CGPoint) -> Float? {
        let metersData = depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        let map = metersData.depthDataMap

        CVPixelBufferLockBaseAddress(map, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }

        let mapW = CVPixelBufferGetWidth(map)
        let mapH = CVPixelBufferGetHeight(map)
        guard let base = CVPixelBufferGetBaseAddress(map) else { return nil }

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
