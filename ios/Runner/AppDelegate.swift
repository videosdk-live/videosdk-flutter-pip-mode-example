import UIKit
import Flutter
import videosdk

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
      
      let bgProcessor = WebRTCFrameProcessor()
      let videoSDK = VideoSDK.getInstance
      videoSDK.registerVideoProcessor(videoProcessorName: "Pavan", videoProcessor: bgProcessor)
      let controller = window?.rootViewController as! FlutterViewController
      
      let pipChannel = FlutterMethodChannel(name: "pip_channel",binaryMessenger: controller.binaryMessenger)
      
      pipChannel.setMethodCallHandler { (call, result) in
          switch call.method {
              
          case "setupPiP":
              PiPManager.setupPiP()
              result(nil)
          case "startPiP":
              PiPManager.startPIP()
              result(nil)
          case "stopPiP":
              PiPManager.stopPIP()
              result(nil)
          case "isPiPAvailable":
              PiPManager.isPIPAvailable(result)
          case "isPiPActive":
              PiPManager.isPIPActive(result)
          case "dispose":
              PiPManager.dispose()
          default:
              result(FlutterMethodNotImplemented)
          }

      }
      
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
