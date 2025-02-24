import UIKit
import AVKit
import videosdk_webrtc
import Combine
import SwiftUI

// MARK: - CustomVideoView
class CustomVideoView: UIView {
    override class var layerClass: AnyClass {
        return AVSampleBufferDisplayLayer.self
    }
    
    var displayLayer: AVSampleBufferDisplayLayer {
        return layer as! AVSampleBufferDisplayLayer
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        displayLayer.videoGravity = .resizeAspectFill
        displayLayer.flushAndRemoveImage()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - RTCFrameRenderer
class RTCFrameRenderer {
    static let shared = RTCFrameRenderer()
    private var videoView: CustomVideoView?
    
    private init() {}
    
    func attachVideoView(_ view: CustomVideoView) {
        self.videoView = view
    }
    
    func renderFrame(_ frame: RTCVideoFrame) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let sampleBuffer = self.convertFrameToSampleBuffer(frame) else {
                print("Failed to convert RTC frame to sample buffer")
                return
            }
            self.videoView?.displayLayer.enqueue(sampleBuffer)
        }
    }
    
    private func convertFrameToSampleBuffer(_ frame: RTCVideoFrame) -> CMSampleBuffer? {
        guard let pixelBuffer = (frame.buffer as? RTCCVPixelBuffer)?.pixelBuffer else {
            print("Invalid pixel buffer")
            return nil
        }
        
        var formatDescription: CMVideoFormatDescription?
        let status = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        
        guard status == noErr, let formatDescription = formatDescription else {
            print("Failed to create format description: \(status)")
            return nil
        }
        
        let timestamp = CMTime(
            value: CMTimeValue(frame.timeStampNs),
            timescale: 1_000_000_000
        )
        
        var sampleBuffer: CMSampleBuffer?
        var timing = CMSampleTimingInfo(
            duration: CMTime.invalid,
            presentationTimeStamp: timestamp,
            decodeTimeStamp: CMTime.invalid
        )
        
        let result = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        
        guard result == noErr else {
            print("Failed to create sample buffer: \(result)")
            return nil
        }
        
        return sampleBuffer
    }
}

// MARK: - Frame Processor
class WebRTCFrameProcessor: VideoProcessor {
    private var isProcessing = false
    
    override func onFrameReceived(_ frame: RTCVideoFrame) -> RTCVideoFrame? {
        guard let buffer = frame.buffer as? RTCCVPixelBuffer,
              CVPixelBufferGetWidth(buffer.pixelBuffer) > 0 else {
            print("Invalid frame buffer")
            return frame
        }
        
        guard !isProcessing else { return frame }
        
        isProcessing = true
        RTCFrameRenderer.shared.renderFrame(frame)
        isProcessing = false
        
        return frame
    }
}

// MARK: - VideoViewController
class VideoViewController: UIViewController, AVPictureInPictureControllerDelegate {
    private let videoView = CustomVideoView()
    private var pipController: AVPictureInPictureController?
    private var playerLayer: AVPlayerLayer?
    private var player: AVPlayer?
    private var pipVideoCallViewController: AVPictureInPictureVideoCallViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        print("VideoViewController Loaded")
        setupVideoView()
    }
    
    private func setupVideoView() {
        view.addSubview(videoView)
        videoView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            videoView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            videoView.widthAnchor.constraint(equalTo: videoView.heightAnchor, multiplier: 9.0/16.0),
            videoView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.9)
        ])
        
        RTCFrameRenderer.shared.attachVideoView(videoView)
    }
}



//MARK: - PiP View

class PiPManager: NSObject, AVPictureInPictureControllerDelegate {
    
    static var pipVideoCallViewController: UIViewController?
    static var pipController: AVPictureInPictureController?
    
    static let shared = PiPManager()
    
    static func setupPiP() {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            print("PiP Mode is not supported at this time")
            return
        }
        
        guard let uiView = UIApplication.shared.keyWindow?.rootViewController?.view else {
            print("hello error view not receiving")
            return
        }
        
        let pipVideoCallViewController = AVPictureInPictureVideoCallViewController()
        self.pipVideoCallViewController = pipVideoCallViewController
        
        let videoView = CustomVideoView()
        RTCFrameRenderer.shared.attachVideoView(videoView)
        
        pipVideoCallViewController.view.addConstrained(subview: videoView)
        videoView.transform = CGAffineTransform(rotationAngle: .pi / 2)
        pipVideoCallViewController.preferredContentSize = CGSize(width: 9, height: 16)
        
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

        print("nil")
    }
    
    static func startPIP() {
        pipController?.startPictureInPicture()
    }

    static func stopPIP() {
        pipController?.stopPictureInPicture()
    }
    
    static func dispose() {
        pipController?.stopPictureInPicture()
        
        // Remove all frames from the AVSampleBufferDisplayLayer
        if let videoView = pipVideoCallViewController?.view.subviews.first as? CustomVideoView {
            videoView.displayLayer.flushAndRemoveImage()
        }
        
        // Remove the video view from the PiP controller
        pipVideoCallViewController?.view.subviews.forEach { $0.removeFromSuperview() }
        
        // Deallocate PiP-related objects
        pipController = nil
        pipVideoCallViewController = nil
    }


    static func isPIPAvailable(_ result: @escaping FlutterResult) {
        result(AVPictureInPictureController.isPictureInPictureSupported())
    }

    static func isPIPActive(_ result: @escaping FlutterResult) {
        result(pipController?.isPictureInPictureActive ?? false)
    }
    
    // MARK: - AVPictureInPictureControllerDelegate Methods
    
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print(#function)
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print(#function)
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print(#function)
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        print(#function, error)
    }

    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print(#function)
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        print(#function)
        completionHandler(true)
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
