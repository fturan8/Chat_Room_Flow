import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    // Mikrofon izni için method channel
    if let controller = window?.rootViewController as? FlutterViewController {
      let microphoneChannel = FlutterMethodChannel(
        name: "com.example.chat_flow_new/microphone",
        binaryMessenger: controller.binaryMessenger
      )
      
      microphoneChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
        switch call.method {
        case "requestMicrophonePermission":
          self.requestMicrophonePermission(result: result)
        case "checkMicrophonePermission":
          self.checkMicrophonePermission(result: result)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  private func requestMicrophonePermission(result: @escaping FlutterResult) {
    AVAudioSession.sharedInstance().requestRecordPermission { granted in
      DispatchQueue.main.async {
        result(granted)
      }
    }
  }
  
  private func checkMicrophonePermission(result: @escaping FlutterResult) {
    let status = AVAudioSession.sharedInstance().recordPermission
    result(status == .granted)
  }
}
