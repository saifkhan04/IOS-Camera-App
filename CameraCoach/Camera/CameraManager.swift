// CameraManager.swift
// Owns and configures the AVCaptureSession.
//
// Key Day 2 insight about LiDAR depth on iPhone Pro:
//   The individual back cameras (wide, ultra-wide, telephoto) report zero
//   supportedDepthDataFormats — they don't carry depth on their own.
//   The depth-capable device is .builtInLiDARDepthCamera, a virtual device
//   that pairs a YUV camera with the LiDAR scanner. Using it as the primary
//   input gives us video AND depth from a single session input, no
//   AVCaptureMultiCamSession needed.
//
//   Adding it alongside .builtInWideAngleCamera in a regular session fails —
//   that requires multi-cam. Using it as the sole input works fine.

import AVFoundation
import Combine

class CameraManager: NSObject, ObservableObject {

    // MARK: - Public

    let session = AVCaptureSession()

    @Published var faceNormRect: CGRect?      // portrait, top-left origin, 0–1
    @Published var subjectDistance: Float?    // metres, from LiDAR

    // Day 3: live image statistics computed in C++ from the Y plane.
    @Published var brightness: Float?         // mean luma, 0–255
    @Published var contrast: Float?           // std dev of luma
    @Published var histogram: [Float]?        // 256 normalised bins, 0–1

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

    // Assembles a FrameState from the latest published readings plus the
    // orientation passed in (orientation lives in MotionManager, the rest
    // here). Used by Teacher Mode to snapshot the reference on button press.
    // Falls back to frame-centre / zero when a face or depth isn't available.
    func currentFrameState(pitch: Float, roll: Float, yaw: Float) -> FrameState {
        FrameState(
            pitch: pitch,
            roll: roll,
            yaw: yaw,
            faceX: Float(faceNormRect?.midX ?? 0.5),
            faceY: Float(faceNormRect?.midY ?? 0.5),
            depthMeters: subjectDistance ?? 0,
            luminance: brightness ?? 0,
            hasFace: faceNormRect != nil
        )
    }

    private func configure() {
        // Don't let the capture session seize the app's audio session — the
        // voice recorder (SFSpeechRecognizer) needs to own it while recording.
        // Our session has no audio input, so it has no reason to manage it.
        session.automaticallyConfiguresApplicationAudioSession = false

        session.beginConfiguration()

        guard let device = addCameraInput() else {
            session.commitConfiguration()
            return
        }

        addVideoOutput()
        addDepthOutput()
        selectDepthCapableFormat(for: device)

        session.commitConfiguration()

        depthConnected = depthOutput.connection(with: .depthData) != nil
        print(depthConnected
            ? "✅ CameraManager: Depth connection confirmed"
            : "⚠️ CameraManager: No depth connection"
        )

        let syncOutputs: [AVCaptureOutput] = depthConnected
            ? [videoOutput, depthOutput]
            : [videoOutput]
        synchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: syncOutputs)
        synchronizer?.setDelegate(self, queue: sessionQueue)
    }

    // Try .builtInLiDARDepthCamera first — it's the virtual device that
    // pairs a YUV camera with the LiDAR scanner and is the only back-camera
    // device type that has non-empty supportedDepthDataFormats.
    // Fall back to .builtInWideAngleCamera on devices without LiDAR.
    @discardableResult
    private func addCameraInput() -> AVCaptureDevice? {
        let preferredTypes: [AVCaptureDevice.DeviceType] = [
            .builtInLiDARDepthCamera,
            .builtInWideAngleCamera
        ]
        for type in preferredTypes {
            guard let device = AVCaptureDevice.default(type, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input)
            else { continue }
            session.addInput(input)
            print("✅ CameraManager: Camera input added (\(type.rawValue))")
            return device
        }
        print("⚠️ CameraManager: Could not add any camera input")
        return nil
    }

    private func addVideoOutput() {
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
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
            print("⚠️ CameraManager: Cannot add depth output")
            return
        }
        session.addOutput(depthOutput)
        print("✅ CameraManager: Depth output added")
    }

    // Pick the highest-resolution format on the device that also supports
    // depth data delivery. On .builtInLiDARDepthCamera, 39 of 45 formats
    // qualify. On .builtInWideAngleCamera, none do (falls through silently).
    private func selectDepthCapableFormat(for device: AVCaptureDevice) {
        let depthCapable = device.formats.filter {
            !$0.supportedDepthDataFormats.isEmpty
        }
        guard let best = depthCapable.max(by: {
            CMVideoFormatDescriptionGetDimensions($0.formatDescription).width <
            CMVideoFormatDescriptionGetDimensions($1.formatDescription).width
        }) else {
            print("⚠️ CameraManager: No depth-capable formats on this device")
            return
        }
        let bestDepth = best.supportedDepthDataFormats.max {
            CMVideoFormatDescriptionGetDimensions($0.formatDescription).width <
            CMVideoFormatDescriptionGetDimensions($1.formatDescription).width
        }
        do {
            try device.lockForConfiguration()
            device.activeFormat = best
            if let bestDepth { device.activeDepthDataFormat = bestDepth }
            device.unlockForConfiguration()
            let d = CMVideoFormatDescriptionGetDimensions(best.formatDescription)
            print("✅ CameraManager: Format set → \(d.width)×\(d.height) (depth-capable)")
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

        // Day 3: run the C++ luminance + histogram pipeline on this frame.
        // analyzeFrame locks the buffer, reads the Y plane, and returns stats.
        let stats = ImageProcessor.analyzeFrame(pixelBuffer)
        let frameBrightness = stats?.averageBrightness
        let frameContrast   = stats?.contrast
        // The histogram arrives as NSData holding 256 packed Float32 values.
        // unsafeBytes gives a typed view; Array(...) copies them into a Swift
        // [Float] we can hand to SwiftUI safely.
        let frameHistogram: [Float]? = stats.map { s in
            s.histogram.withUnsafeBytes { raw in
                Array(raw.bindMemory(to: Float.self))
            }
        }

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

        DispatchQueue.main.async { [weak self] in
            self?.faceNormRect     = faceRect
            self?.subjectDistance  = distance
            self?.brightness       = frameBrightness
            self?.contrast         = frameContrast
            self?.histogram        = frameHistogram
        }
        frameCount += 1
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
