import UIKit
import Flutter
import videosdk

@main
@objc class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)

        // Video SDK setup
        let bgProcessor = FrameProcessor()
        let videoSDK = VideoSDK.getInstance
        videoSDK.registerVideoProcessor(videoProcessorName: "processor", videoProcessor: bgProcessor)

        guard let controller = window?.rootViewController as? FlutterViewController else {
            return super.application(application, didFinishLaunchingWithOptions: launchOptions)
        }

        // PiP Channel Setup
        let pipChannel = FlutterMethodChannel(
            name: "pip_channel",
            binaryMessenger: controller.binaryMessenger
        )

        pipChannel.setMethodCallHandler { (call, result) in
            switch call.method {
            case "setupPiP":
                PiPManager.setupPiP()
                result(nil)

            case "remoteStream":
                guard let args = call.arguments as? [String: Any],
                      let remoteId = args["remoteId"] as? String else {
                    result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing remoteId", details: nil))
                    return
                }
                FrameProcessor.updateRemote(remoteId: remoteId)
                result(nil)

            case "startPiP":
                PiPManager.startPIP()
                result(nil)

            case "stopPiP":
                PiPManager.stopPIP()
                result(nil)

            case "dispose":
                PiPManager.dispose()
                result(nil)

            default:
                result(FlutterMethodNotImplemented)
            }
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}
