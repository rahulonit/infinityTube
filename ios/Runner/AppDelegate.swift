import Flutter
import AVFAudio
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    do {
      try AVAudioSession.sharedInstance().setCategory(
        .playback,
        mode: .moviePlayback,
        options: [.allowAirPlay]
      )
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      NSLog("InfinityTube could not activate background audio: \(error)")
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let storageChannel = FlutterMethodChannel(
      name: "infinitytube/storage",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    storageChannel.setMethodCallHandler { call, result in
      guard call.method == "getStorageInfo" else {
        result(FlutterMethodNotImplemented)
        return
      }
      do {
        let values = try FileManager.default.attributesOfFileSystem(
          forPath: NSHomeDirectory()
        )
        let total = (values[.systemSize] as? NSNumber)?.int64Value ?? 0
        let free = (values[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        result(["totalBytes": total, "freeBytes": free])
      } catch {
        result(FlutterError(code: "storage_unavailable", message: error.localizedDescription, details: nil))
      }
    }
  }
}
