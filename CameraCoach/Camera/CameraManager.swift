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
import UIKit

class CameraManager: NSObject, ObservableObject {

    // MARK: - Public

    let session = AVCaptureSession()

    @Published var faceNormRect: CGRect?      // portrait, top-left origin, 0–1
    @Published var subjectDistance: Float?    // metres, from LiDAR

    // Day 3: live image statistics computed in C++ from the Y plane.
    @Published var brightness: Float?         // mean luma, 0–255
    @Published var contrast: Float?           // std dev of luma
    @Published var histogram: [Float]?        // 256 normalised bins, 0–1

    // Day 7: the most recently saved capture this session. The thumbnail drives
    // the corner gallery button; the full encoded bytes back the in-app
    // full-screen review. Persist across mode switches (manager is hoisted in
    // ContentView). Data is the small HEIF bytes, decoded on demand by the viewer.
    @Published var lastCapturedThumbnail: UIImage?
    @Published var lastCapturedImageData: Data?

    // Day 8 (story 1): a recent upright snapshot of the live preview, refreshed a
    // few times a second. Teacher Mode grabs this at lock time to store on the
    // ReferenceFrame (the picture the shooter recreates).
    @Published var latestVideoImage: UIImage?

    // MARK: - Private: Outputs

    private let videoOutput = AVCaptureVideoDataOutput()
    private let depthOutput = AVCaptureDepthDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private var synchronizer: AVCaptureDataOutputSynchronizer?
    private var depthConnected = false

    // Day 7: in-flight photo captures, keyed by AVCapturePhotoSettings.uniqueID.
    // AVCapturePhotoOutput only holds its delegate weakly, so we must retain the
    // per-shot processor here until its capture completes. Mutated only on
    // sessionQueue.
    private var photoProcessors: [Int64: PhotoCaptureProcessor] = [:]

    // Guards against re-running configure() (which would add duplicate inputs/
    // outputs and wedge the session). The session is configured exactly once.
    private var isConfigured = false

    // MARK: - Private: Processing

    private let faceDetector = FaceDetector()
    private var frameCount = 0

    // Reused across frames — CIContext creation is expensive, so make one.
    private let ciContext = CIContext(options: nil)

    // MARK: - Private: Threading

    private let sessionQueue = DispatchQueue(
        label: "com.cameracoach.session",
        qos: .userInitiated
    )

    // MARK: - Lifecycle

    override init() {
        super.init()
        // Recover the session automatically. A heavy LiDAR + 30fps pipeline can
        // be interrupted (resource pressure, thermal, a phone call, control
        // center) or hit a runtime error; without these the preview freezes and
        // never comes back — and a wedged session can carry into the next launch.
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(handleRuntimeError(_:)),
                       name: .AVCaptureSessionRuntimeError, object: session)
        nc.addObserver(self, selector: #selector(handleInterruptionEnded(_:)),
                       name: .AVCaptureSessionInterruptionEnded, object: session)
        nc.addObserver(self, selector: #selector(handleWasInterrupted(_:)),
                       name: .AVCaptureSessionWasInterrupted, object: session)
    }

    // Idempotent: configures once, then ensures the session is running. Safe to
    // call repeatedly (e.g. every time the view appears or the app foregrounds).
    func start() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.isConfigured {
                self.configure()
                self.isConfigured = true
            }
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }

    // MARK: - Session recovery

    @objc private func handleRuntimeError(_ note: Notification) {
        let err = note.userInfo?[AVCaptureSessionErrorKey] as? NSError
        print("⚠️ CameraManager: session runtime error \(String(describing: err)) — restarting")
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    @objc private func handleWasInterrupted(_ note: Notification) {
        print("⚠️ CameraManager: session interrupted \(note.userInfo ?? [:])")
    }

    @objc private func handleInterruptionEnded(_ note: Notification) {
        print("✅ CameraManager: interruption ended — resuming")
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
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

    // MARK: - Photo capture (Day 7)

    enum PhotoCaptureError: LocalizedError {
        case sessionNotReady
        var errorDescription: String? { "The camera isn't ready to capture." }
    }

    // Captures one still and saves it to Photos. onWillCapture fires when the
    // sensor exposes (drive the screen flash there); completion fires on the
    // main queue with the save result. Runs on sessionQueue so it's serialised
    // against configuration and the processor registry is touched on one queue.
    func capturePhoto(onWillCapture: @escaping () -> Void,
                      completion: @escaping (Result<Void, Error>) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.session.isRunning,
                  self.session.outputs.contains(self.photoOutput)
            else {
                DispatchQueue.main.async { completion(.failure(PhotoCaptureError.sessionNotReady)) }
                return
            }

            // The preview is portrait-locked; match the saved image to it. 90°
            // is portrait for the back camera's native sensor orientation.
            if let conn = self.photoOutput.connection(with: .video),
               conn.isVideoRotationAngleSupported(90) {
                conn.videoRotationAngle = 90
            }

            let settings = self.makePhotoSettings()
            let id = settings.uniqueID

            let processor = PhotoCaptureProcessor(
                onWillCapture: onWillCapture,
                onSaved: { [weak self] image, data in
                    // already on main
                    self?.lastCapturedThumbnail = image
                    self?.lastCapturedImageData = data
                },
                onFinish: { [weak self] result in
                    completion(result)
                    // Release the processor once its capture is done.
                    self?.sessionQueue.async { self?.photoProcessors[id] = nil }
                }
            )
            self.photoProcessors[id] = processor
            self.photoOutput.capturePhoto(with: settings, delegate: processor)
        }
    }

    // HEIF (HEVC) when available — same codec the native Camera app uses, ~half
    // the size of JPEG at equal quality. Quality prioritization lets the ISP
    // take its time (multi-frame fusion, noise reduction) for the final shot.
    private func makePhotoSettings() -> AVCapturePhotoSettings {
        let settings: AVCapturePhotoSettings
        if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        } else {
            settings = AVCapturePhotoSettings()
        }
        settings.photoQualityPrioritization = .quality
        settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions
        // We use an on-screen white flash, not the LED — and the LiDAR depth
        // camera doesn't pair with the flash anyway.
        settings.flashMode = .off
        return settings
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
        addPhotoOutput()
        selectDepthCapableFormat(for: device)
        configurePhotoOutput(for: device)

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

    // Day 7: still-photo capture alongside the live video+depth streams.
    // maxPhotoQualityPrioritization MUST be set while configuring (before the
    // session runs) — it's what unlocks Apple's full quality ISP pipeline at
    // capture time. The per-shot setting can then ask for .quality.
    private func addPhotoOutput() {
        guard session.canAddOutput(photoOutput) else {
            print("⚠️ CameraManager: Cannot add photo output")
            return
        }
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .quality
        print("✅ CameraManager: Photo output added")
    }

    // Cap the photo output at the largest still the ACTIVE format supports.
    // We deliberately keep the depth-capable active format (live guidance needs
    // it), so this is the best resolution available without tearing the session
    // down. supportedMaxPhotoDimensions is tied to activeFormat, so this must
    // run AFTER selectDepthCapableFormat.
    private func configurePhotoOutput(for device: AVCaptureDevice) {
        guard session.outputs.contains(photoOutput) else { return }
        let best = device.activeFormat.supportedMaxPhotoDimensions.max {
            Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height)
        }
        if let best {
            photoOutput.maxPhotoDimensions = best
            let mp = Double(best.width) * Double(best.height) / 1_000_000
            print(String(format: "✅ CameraManager: Photo dimensions → %d×%d (%.1f MP)",
                         best.width, best.height, mp))
        }
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

        // Story 1: refresh the preview snapshot a few times a second (every 6th
        // frame ≈ 5fps). Converting every frame would waste CPU; this is only a
        // "latest frame" cache for the reference, not a live feed.
        var previewImage: UIImage? = nil
        if frameCount % 6 == 0 {
            previewImage = makePreviewImage(from: pixelBuffer)
        }

        DispatchQueue.main.async { [weak self] in
            self?.faceNormRect     = faceRect
            self?.subjectDistance  = distance
            self?.brightness       = frameBrightness
            self?.contrast         = frameContrast
            self?.histogram        = frameHistogram
            if let previewImage { self?.latestVideoImage = previewImage }
        }
        frameCount += 1
    }

    // Convert the current sensor buffer into an upright, downscaled UIImage.
    // The buffer is landscape sensor orientation; .right (EXIF 6) rotates it to
    // the portrait the preview shows — matching FaceDetector's orientation so the
    // snapshot lines up with the live scene and the face box.
    private func makePreviewImage(from pixelBuffer: CVPixelBuffer,
                                  maxDimension: CGFloat = 1280) -> UIImage? {
        var ci = CIImage(cvPixelBuffer: pixelBuffer)
        let extent = ci.extent
        let scale = Swift.min(1, maxDimension / Swift.max(extent.width, extent.height))
        if scale < 1 {
            ci = ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        guard let cg = ciContext.createCGImage(ci, from: ci.extent) else { return nil }
        return UIImage(cgImage: cg, scale: 1, orientation: .right)
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
