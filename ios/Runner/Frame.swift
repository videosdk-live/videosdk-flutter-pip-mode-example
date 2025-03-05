import UIKit
import AVKit
import videosdk_webrtc
import Combine
import SwiftUI
import CoreVideo
import Accelerate

// MARK: - Custom Video View
class CustomVideoView: UIView {
    override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }
    var displayLayer: AVSampleBufferDisplayLayer { layer as! AVSampleBufferDisplayLayer }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        displayLayer.videoGravity = .resizeAspectFill
        displayLayer.flushAndRemoveImage()
    }
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - RTCFrameRenderer
class RTCFrameRenderer: NSObject, RTCVideoRenderer {
    private var videoView: CustomVideoView?
    private let processingQueue = DispatchQueue(label: "com.app.frameProcessing", qos: .userInteractive)
    
    // Pixel buffer pool for reusing memory
    private var pixelBufferPool: CVPixelBufferPool?
    private var pixelBufferPoolWidth: Int = 0
    private var pixelBufferPoolHeight: Int = 0
    
    // Frame skipping for performance
    private var frameCount: Int = 0
    private let frameProcessingInterval: Int = 2
    
    override init() {
        super.init()
    }
    
    deinit {
        pixelBufferPool = nil
    }

    func attachVideoView(_ view: CustomVideoView) {
        self.videoView = view
    }

    func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame = frame else {
            return
        }
        
        // Skip frames for performance
        frameCount += 1
        if frameCount % frameProcessingInterval != 0 {
            return
        }
        
        // Process frame on background queue
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
            autoreleasepool {
                guard let sampleBuffer = self.convertFrameToSampleBuffer(frame) else {
                    return
                }
                
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, let videoView = self.videoView else { return }
                    
                    if videoView.displayLayer.status == .failed {
                        videoView.displayLayer.flush()
                    }
                    
                    videoView.displayLayer.enqueue(sampleBuffer)
                }
            }
        }
    }

    // Implement required method from RTCVideoRenderer
    func setSize(_ size: CGSize) {
        // Update pixel buffer pool when size changes
        createPixelBufferPoolIfNeeded(width: Int(size.width), height: Int(size.height))
    }
    
    private func createPixelBufferPoolIfNeeded(width: Int, height: Int) {
        // Only create a new pool if dimensions changed
        guard width != pixelBufferPoolWidth || height != pixelBufferPoolHeight || pixelBufferPool == nil else {
            return
        }
        
        // Release old pool
        pixelBufferPool = nil
        
        pixelBufferPoolWidth = width
        pixelBufferPoolHeight = height
        
        let poolAttributes: [String: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey as String: 3
        ]
        
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        
        var cvPixelBufferPool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(kCFAllocatorDefault,
                                             poolAttributes as CFDictionary,
                                             pixelBufferAttributes as CFDictionary,
                                             &cvPixelBufferPool)
        
        if status == kCVReturnSuccess {
            pixelBufferPool = cvPixelBufferPool
        }
    }
    
    private func convertFrameToSampleBuffer(_ frame: RTCVideoFrame) -> CMSampleBuffer? {
        var pixelBuffer: CVPixelBuffer?
        
        // Reuse existing pixel buffer if possible
        if let buffer = frame.buffer as? RTCCVPixelBuffer {
            pixelBuffer = buffer.pixelBuffer
        } else if let buffer = frame.buffer as? RTCI420Buffer {
            pixelBuffer = convertI420BufferToPixelBuffer(buffer)
        } else {
            return nil
        }
        
        guard let validPixelBuffer = pixelBuffer else {
            return nil
        }
        
        // Reuse format description if possible
        var formatDescription: CMVideoFormatDescription?
        let status = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: validPixelBuffer,
            formatDescriptionOut: &formatDescription
        )

        guard status == noErr, let formatDescription = formatDescription else {
            return nil
        }

        let timestamp = CMTime(value: CMTimeValue(frame.timeStampNs), timescale: 1_000_000_000)

        var sampleBuffer: CMSampleBuffer?
        var timing = CMSampleTimingInfo(
            duration: CMTime.invalid,
            presentationTimeStamp: timestamp,
            decodeTimeStamp: CMTime.invalid
        )

        let result = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: validPixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )

        return result == noErr ? sampleBuffer : nil
    }

    private func convertI420BufferToPixelBuffer(_ i420Buffer: RTCI420Buffer) -> CVPixelBuffer? {
        let width = Int(i420Buffer.width)
        let height = Int(i420Buffer.height)
        
        // Create/update pixel buffer pool if needed
        if pixelBufferPool == nil || width != pixelBufferPoolWidth || height != pixelBufferPoolHeight {
            createPixelBufferPoolIfNeeded(width: width, height: height)
        }
        
        // Get pixel buffer from pool
        var pixelBuffer: CVPixelBuffer?
        if let pool = pixelBufferPool {
            let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
            if status != kCVReturnSuccess {
                pixelBuffer = nil
            }
        }
        
        // If we couldn't get a buffer from the pool, create a new one
        if pixelBuffer == nil {
            let attributes: [CFString: Any] = [
                kCVPixelBufferCGImageCompatibilityKey: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey: true,
                kCVPixelBufferIOSurfacePropertiesKey: [:]
            ]
            
            let status = CVPixelBufferCreate(
                kCFAllocatorDefault,
                width,
                height,
                kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                attributes as CFDictionary,
                &pixelBuffer
            )
            
            if status != kCVReturnSuccess {
                return nil
            }
        }
        
        // Safely unwrap the pixel buffer
        guard let pixelBuffer = pixelBuffer else {
            return nil
        }
        
        // Lock the pixel buffer for writing
        let lockFlags = CVPixelBufferLockFlags(rawValue: 0)
        guard CVPixelBufferLockBaseAddress(pixelBuffer, lockFlags) == kCVReturnSuccess else {
            return nil
        }
        
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, lockFlags) }
        
        // Y-plane processing using Accelerate framework for better performance
        if let yBaseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) {
            let yDestStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
            let ySrcStride = Int(i420Buffer.strideY)
            
            // Use vDSP for faster memory copying when possible
            if ySrcStride == yDestStride {
                let ySrc = i420Buffer.dataY
                vDSP_vclr(yBaseAddress.assumingMemoryBound(to: Float.self), 1, vDSP_Length(height * yDestStride / 4))
                memcpy(yBaseAddress, ySrc, height * ySrcStride)
            } else {
                for row in 0..<height {
                    let src = i420Buffer.dataY + row * ySrcStride
                    let dest = yBaseAddress.advanced(by: row * yDestStride)
                    memcpy(dest, src, min(ySrcStride, width))
                }
            }
        }
        
        // UV-plane processing
        if let uvBaseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1) {
            let uvDestStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
            let uvHeight = height / 2
            let uvWidth = width / 2
            
            let uPlane = i420Buffer.dataU
            let vPlane = i420Buffer.dataV
            let uStride = Int(i420Buffer.strideU)
            let vStride = Int(i420Buffer.strideV)
            
            // Process UV plane more efficiently
            for row in 0..<uvHeight {
                let destRow = uvBaseAddress.advanced(by: row * uvDestStride)
                let uRow = uPlane + row * uStride
                let vRow = vPlane + row * vStride
                
                var destPtr = destRow.assumingMemoryBound(to: UInt8.self)
                
                // Process 4 pixels at a time when possible
                var col = 0
                while col < uvWidth - 3 {
                    destPtr[0] = uRow[col]
                    destPtr[1] = vRow[col]
                    destPtr[2] = uRow[col+1]
                    destPtr[3] = vRow[col+1]
                    destPtr[4] = uRow[col+2]
                    destPtr[5] = vRow[col+2]
                    destPtr[6] = uRow[col+3]
                    destPtr[7] = vRow[col+3]
                    
                    destPtr = destPtr.advanced(by: 8)
                    col += 4
                }
                
                // Process remaining pixels
                while col < uvWidth {
                    destPtr[0] = uRow[col]
                    destPtr[1] = vRow[col]
                    destPtr = destPtr.advanced(by: 2)
                    col += 1
                }
            }
        }
        
        return pixelBuffer
    }
}

// MARK: - SplitVideoView
class SplitVideoView: UIView {
    let localVideoView = CustomVideoView()
    let remoteVideoView = CustomVideoView()
    let statusLabel = UILabel()
    private var hasRemoteStream: Bool = false
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    private func setupViews() {
        [localVideoView, remoteVideoView, statusLabel].forEach {
            addSubview($0)
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        
        localVideoView.transform = CGAffineTransform(rotationAngle: .pi/2)
        statusLabel.textColor = .white
        statusLabel.backgroundColor = .black
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        
        NSLayoutConstraint.activate([
            localVideoView.leadingAnchor.constraint(equalTo: leadingAnchor),
            localVideoView.topAnchor.constraint(equalTo: topAnchor),
            localVideoView.bottomAnchor.constraint(equalTo: bottomAnchor),
            localVideoView.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.5),
            
            remoteVideoView.leadingAnchor.constraint(equalTo: localVideoView.trailingAnchor),
            remoteVideoView.topAnchor.constraint(equalTo: topAnchor),
            remoteVideoView.trailingAnchor.constraint(equalTo: trailingAnchor),
            remoteVideoView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            statusLabel.leadingAnchor.constraint(equalTo: localVideoView.trailingAnchor),
            statusLabel.topAnchor.constraint(equalTo: topAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            statusLabel.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        
        updateViewState()
    }
    
    func updateStatus(hasRemote: Bool, message: String? = nil) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.hasRemoteStream = hasRemote
            self.statusLabel.text = message ?? "You are alone in the meeting"
            self.updateViewState()
        }
    }
    
    private func updateViewState() {
        remoteVideoView.isHidden = !hasRemoteStream
        statusLabel.isHidden = hasRemoteStream
    }
}

// MARK: - MultiStreamFrameRenderer
class MultiStreamFrameRenderer: NSObject {
    static let shared = MultiStreamFrameRenderer()
    
    private var localVideoView: CustomVideoView?
    private var remoteVideoView: CustomVideoView?
    
    private let localRenderer = RTCFrameRenderer()
    private let remoteRenderer = RTCFrameRenderer()
    
    private override init() {
        super.init()
    }
    
    func attachViews(localView: CustomVideoView, remoteView: CustomVideoView) {
        self.localVideoView = localView
        self.remoteVideoView = remoteView
        
        localRenderer.attachVideoView(localView)
        remoteRenderer.attachVideoView(remoteView)
    }
    
    func renderLocalFrame(_ frame: RTCVideoFrame) {
        localRenderer.renderFrame(frame)
    }
    
    func renderRemoteFrame(_ frame: RTCVideoFrame) {
        remoteRenderer.renderFrame(frame)
    }
}

// MARK: - Enhanced PiP Manager
class PiPManager: NSObject, AVPictureInPictureControllerDelegate {
    
    static var pipVideoCallViewController: UIViewController?
    static var pipController: AVPictureInPictureController?
    
    static let shared = PiPManager()
    
    // Split view containing both local and remote video views
    var splitVideoView: SplitVideoView?
    
    static func setupPiP(hasRemote: Bool = false) {
            guard AVPictureInPictureController.isPictureInPictureSupported(),
                  let uiView = UIApplication.shared.keyWindow?.rootViewController?.view else {
                return
            }
            
            if shared.splitVideoView == nil {
                let splitVideoView = SplitVideoView(frame: CGRect(x: 0, y: 0, width: 60, height: 30))
                shared.splitVideoView = splitVideoView
            }
            
            shared.splitVideoView?.updateStatus(hasRemote: hasRemote)
            
            let pipVideoCallViewController = AVPictureInPictureVideoCallViewController()
            self.pipVideoCallViewController = pipVideoCallViewController
            
            if let splitVideoView = shared.splitVideoView {
                MultiStreamFrameRenderer.shared.attachViews(
                    localView: splitVideoView.localVideoView,
                    remoteView: splitVideoView.remoteVideoView
                )
                pipVideoCallViewController.view.addConstrained(subview: splitVideoView)
            }
            
            pipVideoCallViewController.preferredContentSize = CGSize(width: 60, height: 30)
            
            let pipContentSource = AVPictureInPictureController.ContentSource(
                activeVideoCallSourceView: uiView,
                contentViewController: pipVideoCallViewController
            )
            
            pipController = AVPictureInPictureController(contentSource: pipContentSource)
            pipController?.delegate = shared
            pipController?.canStartPictureInPictureAutomaticallyFromInline = true
            
            NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                                 object: nil, queue: .main) { _ in
                stopPIP()
            }
        }
    
    static func updateRemoteStatus(hasRemote: Bool, message: String? = nil) {
        shared.splitVideoView?.updateStatus(hasRemote: hasRemote, message: message)
    }
    static func startPIP() {
        pipController?.startPictureInPicture()
    }

    static func stopPIP() {
        pipController?.stopPictureInPicture()
    }
    
    static func dispose() {
        // Clean up resources
        pipController?.stopPictureInPicture()
        
        // Remove all frames from both display layers
        if let splitView = shared.splitVideoView {
            splitView.localVideoView.displayLayer.flushAndRemoveImage()
            splitView.remoteVideoView.displayLayer.flushAndRemoveImage()
        }
        
        // Remove the split view from the PiP controller
        pipVideoCallViewController?.view.subviews.forEach { $0.removeFromSuperview() }
        
        // Deallocate PiP-related objects
        pipController = nil
        pipVideoCallViewController = nil
        shared.splitVideoView = nil
        
        // Remove notification observer
        NotificationCenter.default.removeObserver(shared)
    }

    static func isPIPAvailable(_ result: @escaping FlutterResult) {
        result(AVPictureInPictureController.isPictureInPictureSupported())
    }

    static func isPIPActive(_ result: @escaping FlutterResult) {
        result(pipController?.isPictureInPictureActive ?? false)
    }
    
    // MARK: - AVPictureInPictureControllerDelegate Methods
    
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {}

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {}

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {}

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {}

    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {}

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        completionHandler(true)
    }
}

// MARK: - Frame Processor for Local and Remote
class FrameProcessor: VideoProcessor {
    private var isProcessing = false
    
    override func onFrameReceived(_ frame: RTCVideoFrame) -> RTCVideoFrame? {
        guard let buffer = frame.buffer as? RTCCVPixelBuffer,
              CVPixelBufferGetWidth(buffer.pixelBuffer) > 0,
              !isProcessing else {
            return frame
        }
        
        isProcessing = true
        MultiStreamFrameRenderer.shared.renderLocalFrame(frame)
        isProcessing = false
        
        return frame
    }
    
    static func updateRemote(remoteId: String) {
        DispatchQueue.main.async {
            switch remoteId {
            case "Nothing":
                PiPManager.updateRemoteStatus(hasRemote: false)
                
            case "No Cam":
                PiPManager.updateRemoteStatus(hasRemote: false, message: "No camera")
                
            default:
                if let remoteTrack = FlutterWebRTCPlugin.sharedSingleton()?.remoteTrack(forId: remoteId) as? RTCVideoTrack {
                    PiPManager.updateRemoteStatus(hasRemote: true)
                    remoteTrack.add(RemoteFrameObserver())
                } else {
                    PiPManager.updateRemoteStatus(hasRemote: false, message: "Remote connection failed")
                }
            }
        }
    }
}

// MARK: - Remote Frame Observer
class RemoteFrameObserver: NSObject, RTCVideoRenderer {
    private var isProcessing = false
    
    func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame = frame, !isProcessing else { return }
        
        isProcessing = true
        // Send remote frame to the remote video view
        MultiStreamFrameRenderer.shared.renderRemoteFrame(frame)
        isProcessing = false
    }
    
    func setSize(_ size: CGSize) {
        // No specific action needed
    }
}

// MARK: - UIView Extension for Convenience
extension UIView {
    func addConstrained(subview: UIView) {
        addSubview(subview)
        subview.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            subview.topAnchor.constraint(equalTo: topAnchor),
            subview.leadingAnchor.constraint(equalTo: leadingAnchor),
            subview.trailingAnchor.constraint(equalTo: trailingAnchor),
            subview.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}

// MARK: - VideoViewController
class VideoViewController: UIViewController {
    private let splitVideoView = SplitVideoView()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupVideoView()
        PiPManager.setupPiP()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        splitVideoView.localVideoView.displayLayer.flushAndRemoveImage()
        splitVideoView.remoteVideoView.displayLayer.flushAndRemoveImage()
        PiPManager.dispose()
    }
    
    private func setupVideoView() {
        view.addSubview(splitVideoView)
        splitVideoView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            splitVideoView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            splitVideoView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            splitVideoView.widthAnchor.constraint(equalTo: splitVideoView.heightAnchor, multiplier: 2.0),
            splitVideoView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.9)
        ])
        
        MultiStreamFrameRenderer.shared.attachViews(
            localView: splitVideoView.localVideoView,
            remoteView: splitVideoView.remoteVideoView
        )
    }
    
    func updateRemoteStream(remoteId: String) {
        FrameProcessor.updateRemote(remoteId: remoteId)
    }
}
