import AVFoundation
import Vision
import SwiftUI
import AppKit

class CameraManager: NSObject, ObservableObject {
    static let shared = CameraManager()

    private var checkTimer: Timer?
    private var isProcessingFrame = false
    private var shouldProcessNextFrame = false

    @Published var session = AVCaptureSession()
    var previewLayer: AVCaptureVideoPreviewLayer?

    @Published var mouthRect: CGRect?
    @Published var handsFingersPositions: [[CGPoint]] = []
    @Published var handInMouth = false
    @Published var lastBitingImage: NSImage?
    @Published var isPopoverOpen = false
    @Published var checkInterval: Double = 2.0 {
        didSet {
            setupTimer()
        }
    }
    
    @Published var cameraResolution: AVCaptureSession.Preset = .medium {
        didSet {
            reconfigureSession()
        }
    }

    private var currentBuffer: CVPixelBuffer?

    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let videoDataOutputQueue = DispatchQueue(label: "VideoDataOutput", qos: .userInitiated)

    private var lastFaceDetectionTime: Date = .distantPast
    private let faceDetectionTimeout: TimeInterval = 10.0
    
    private let processingQueue = DispatchQueue(label: "BackgroundProcessing", qos: .userInitiated)
    private var frameCount = 0
    private let framesBetweenDetections = 2

    private override init() {
        super.init()
    
        checkPermissionAndSetupSession()
        setupTimer()
    }

    private func setupTimer() {
        checkTimer?.invalidate()
        checkTimer = Timer(timeInterval: max(0.1, checkInterval), target: self, selector: #selector(timerFired), userInfo: nil, repeats: true)
        RunLoop.main.add(checkTimer!, forMode: .common)
    }

    @objc private func timerFired() {
        shouldProcessNextFrame = true
    }

    func checkPermissionAndSetupSession() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                setupCaptureSession()

            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                    if granted {
                        DispatchQueue.main.async {
                            self?.setupCaptureSession()
                        }
                    } else {
                        print("❌ Camera permission denied")
                    }
                }

            case .denied:
                if let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                    NSWorkspace.shared.open(settingsURL)
                }

            case .restricted:
                print("❌ Camera access restricted")

            @unknown default:
                print("❓ Unknown camera permission status")
        }
    }

    private func setupCaptureSession() {
        print("🎥 Setting up camera session...")

        if !session.inputs.isEmpty {
            session.beginConfiguration()
            session.inputs.forEach { session.removeInput($0) }
            session.outputs.forEach { session.removeOutput($0) }
            session.commitConfiguration()
        }

        session.beginConfiguration()
        session.sessionPreset = cameraResolution

        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            print("❌ Failed to get front camera device")
            return
        }

        do {
            let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
            if session.canAddInput(videoDeviceInput) {
                session.addInput(videoDeviceInput)
            } else {
                print("❌ Cannot add video input")
                return
            }
        } catch {
            print("❌ Error creating video input: \(error)")
            return
        }

        videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        videoDataOutput.alwaysDiscardsLateVideoFrames = true

        if session.canAddOutput(videoDataOutput) {
            session.addOutput(videoDataOutput)
        } else {
            print("❌ Cannot add video output")
            return
        }

        session.commitConfiguration()
        
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspect
        self.previewLayer = layer

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }
    
    private func reconfigureSession() {
        guard session.isRunning else { return }
        
        session.beginConfiguration()
        if session.canSetSessionPreset(cameraResolution) {
            session.sessionPreset = cameraResolution
        }
        session.commitConfiguration()
    }

    func cleanup() {
        print("🧹 Cleaning up resources...")
        checkTimer?.invalidate()
        checkTimer = nil
        session.stopRunning()
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // If we are not due to process a frame, return early.
        if !shouldProcessNextFrame {
            return
        }

        frameCount += 1
        // Only run the Vision requests every N frames
        if frameCount % framesBetweenDetections != 0 {
            return
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        currentBuffer = pixelBuffer

        isProcessingFrame = true
        shouldProcessNextFrame = false

        // Run heavy operations on a background queue
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
            let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])

            let faceRequest = VNDetectFaceLandmarksRequest { [weak self] request, error in
                self?.handleMouthDetection(request: request)
            }
            

            do {
                try requestHandler.perform([faceRequest])

                // Only proceed with hand detection if we have a mouthRect
                if let _ = self.mouthRect {
                    let handRequest = VNDetectHumanHandPoseRequest { [weak self] request, error in
                        self?.handleHandsWithFingersDetection(request: request)
                    }
                    handRequest.maximumHandCount = 1
                    try requestHandler.perform([handRequest])
                } else {
                    DispatchQueue.main.async {
                        self.handsFingersPositions = []
                        self.updateHandInMouthIfChanged(false)
                    }
                }
            } catch {
            }

            DispatchQueue.main.async {
                self.isProcessingFrame = false
            }
        }
    }

    private func handleMouthDetection(request: VNRequest) {
        guard let observations = request.results as? [VNFaceObservation],
              let faceObservation = observations.first else {
            DispatchQueue.main.async {
                self.mouthRect = nil
            }
            return
        }

        self.lastFaceDetectionTime = Date()

        if let landmarks = faceObservation.landmarks,
           let mouth = landmarks.outerLips {

            let mouthPoints = mouth.normalizedPoints.map {
                CGPoint(x: $0.x * faceObservation.boundingBox.width + faceObservation.boundingBox.origin.x,
                        y: $0.y * faceObservation.boundingBox.height + faceObservation.boundingBox.origin.y)
            }

            let xCoords = mouthPoints.map { $0.x }
            let yCoords = mouthPoints.map { $0.y }

            if let minX = xCoords.min(),
               let maxX = xCoords.max(),
               let minY = yCoords.min(),
               let maxY = yCoords.max() {
                let mouthBounds = CGRect(x: minX,
                                         y: minY,
                                         width: maxX - minX,
                                         height: maxY - minY)

                DispatchQueue.main.async {
                    if self.isPopoverOpen, let previewLayer = self.previewLayer {
                        // Convert Vision coordinates to preview layer coordinates.
                        let topLeftVision = CGPoint(x: mouthBounds.minX, y: mouthBounds.maxY)
                        let bottomRightVision = CGPoint(x: mouthBounds.maxX, y: mouthBounds.minY)

                        // Flip y for both points since Vision is bottom-left and previewLayer expects top-left:
                        let adjustedTopLeft = CGPoint(x: topLeftVision.x, y: 1 - topLeftVision.y)
                        let adjustedBottomRight = CGPoint(x: bottomRightVision.x, y: 1 - bottomRightVision.y)

                        let topLeftLayer = previewLayer.layerPointConverted(fromCaptureDevicePoint: adjustedTopLeft)
                        let bottomRightLayer = previewLayer.layerPointConverted(fromCaptureDevicePoint: adjustedBottomRight)

                        let mouthRectLayer = CGRect(x: topLeftLayer.x,
                                                    y: topLeftLayer.y,
                                                    width: bottomRightLayer.x - topLeftLayer.x,
                                                    height: bottomRightLayer.y - topLeftLayer.y)

                        self.updateMouthRectIfChanged(mouthRectLayer)
                    } else {
                        // Popover is not open or previewLayer is not available, use the Vision coordinates directly.
                        self.updateMouthRectIfChanged(mouthBounds)
                    }
                }
            }
        }
    }

    private func calculateAveragePoint(from points: [CGPoint]) -> CGPoint? {
        guard !points.isEmpty else { return nil }
        let xSum = points.reduce(0, { $0 + $1.x })
        let ySum = points.reduce(0, { $0 + $1.y })
        return CGPoint(x: xSum / CGFloat(points.count), y: ySum / CGFloat(points.count))
    }


    private func handleHandsWithFingersDetection(request: VNRequest) {
        // If it's been too long since we saw a face, skip processing hands.
        if Date().timeIntervalSince(lastFaceDetectionTime) > faceDetectionTimeout {
            DispatchQueue.main.async {
                self.handsFingersPositions = []
                self.updateHandInMouthIfChanged(false)
            }
            return
        }
        
        guard let observations = request.results as? [VNHumanHandPoseObservation],
              let observation = observations.first else {
            DispatchQueue.main.async {
                self.handsFingersPositions = []
                self.updateHandInMouthIfChanged(false)
            }
                        
            return
        }

        var fingerPositions: [CGPoint] = []

        let fingerGroups: [(VNHumanHandPoseObservation.JointsGroupName, VNHumanHandPoseObservation.JointName)] = [
            (.thumb, .thumbTip),
            (.indexFinger, .indexTip),
            (.middleFinger, .middleTip),
            (.ringFinger, .ringTip),
            (.littleFinger, .littleTip)
        ]
    
        for (group, tip) in fingerGroups {
            if let points = try? observation.recognizedPoints(group),
               let tipPoint = points[tip],
               tipPoint.confidence > 0.3 {
                    let point = CGPoint(x: tipPoint.location.x, y: tipPoint.location.y)
                    fingerPositions.append(point)
                }
        }

        if fingerPositions.count >= 1 {
            DispatchQueue.main.async {
                let wasInMouth = self.handInMouth
                
                if self.isPopoverOpen, let previewLayer = self.previewLayer {
                    // Do the conversion only if the popover is open and previewLayer is available
                    let convertedFingerPositions = fingerPositions.map { pt -> CGPoint in
                        let adjustedPoint = CGPoint(x: pt.x, y: 1 - pt.y)
                        return previewLayer.layerPointConverted(fromCaptureDevicePoint: adjustedPoint)
                    }
                    
                    self.handsFingersPositions = [convertedFingerPositions]
                    self.updateHandInMouthIfChanged(self.isHandNearFace(handsFingersPositions: [convertedFingerPositions]))
                    
                    if !wasInMouth && self.handInMouth {
                        self.captureScreenshot()
                    }
                    
                } else {
                    // Popover is not open or no previewLayer available, use raw Vision coordinates
                    self.handsFingersPositions = [fingerPositions]
                    self.updateHandInMouthIfChanged(self.isHandNearFace(handsFingersPositions: [fingerPositions]))
                    
                    if !wasInMouth && self.handInMouth {
                        self.captureScreenshot()
                    }
                }
            }
        } else {
            DispatchQueue.main.async {
                self.handsFingersPositions = []
                self.updateHandInMouthIfChanged(false)
            }
        }
    }

    private func isHandNearFace(handsFingersPositions: [[CGPoint]]) -> Bool {
        guard let mouthRect = self.mouthRect else { return false }
    


        for handFingersPositions in handsFingersPositions {
            for fingerPosition in handFingersPositions {
                if mouthRect.contains(fingerPosition) {
                    return true
                }
            }
        }

        return false
    }

    private func captureScreenshot() {
        guard let pixelBuffer = currentBuffer else { return }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let scale = 0.5
        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let context = CIContext(options: [.useSoftwareRenderer: false]) // Use GPU when available
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return }

        let screenshot = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))

        DispatchQueue.main.async {
            self.lastBitingImage = screenshot
        }
    }
    
    private func updateMouthRectIfChanged(_ newRect: CGRect?) {
        guard mouthRect != newRect else { return }
        mouthRect = newRect
    }

    private func updateHandInMouthIfChanged(_ newValue: Bool) {
        guard handInMouth != newValue else { return }
        handInMouth = newValue
    }
}
