import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var wakeAlarmPreviewPlayer: AVAudioPlayer?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "de.khonager.trans/wake_alarm_preview",
        binaryMessenger: controller.binaryMessenger
      )

      channel.setMethodCallHandler { [weak self] call, result in
        switch call.method {
        case "play":
          guard
            let arguments = call.arguments as? [String: Any],
            let path = arguments["path"] as? String
          else {
            result(FlutterError(
              code: "missing_path",
              message: "Missing preview sound path.",
              details: nil
            ))
            return
          }

          do {
            try self?.playWakeAlarmPreview(path: path)
            result(nil)
          } catch {
            result(FlutterError(
              code: "play_failed",
              message: error.localizedDescription,
              details: nil
            ))
          }
        case "stop":
          self?.stopWakeAlarmPreview()
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func playWakeAlarmPreview(path: String) throws {
    stopWakeAlarmPreview()

    try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
    try AVAudioSession.sharedInstance().setActive(true)

    let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
    player.prepareToPlay()
    player.play()
    wakeAlarmPreviewPlayer = player
  }

  private func stopWakeAlarmPreview() {
    wakeAlarmPreviewPlayer?.stop()
    wakeAlarmPreviewPlayer = nil
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
