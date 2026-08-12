import UIKit
import Flutter
import videosdk

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
    // Under the UIScene life cycle the window does not exist yet in
    // didFinishLaunchingWithOptions, so setup happens here instead.
    func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
        GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

        // Video SDK setup
        let bgProcessor = FrameProcessor()
        let videoSDK = VideoSDK.getInstance
        videoSDK.registerVideoProcessor(videoProcessorName: "processor", videoProcessor: bgProcessor)

        // PiP Channel Setup
        let pipChannel = FlutterMethodChannel(
            name: "pip_channel",
            binaryMessenger: engineBridge.applicationRegistrar.messenger()
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
    }
}
