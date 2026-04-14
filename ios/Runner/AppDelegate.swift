import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var wakeAlarmPreviewPlayer: AVAudioPlayer?
  private var wakeAlarmPreviewChannel: FlutterMethodChannel?
  private var deviceTimezoneChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func registerWakeAlarmPreviewChannel(binaryMessenger: FlutterBinaryMessenger) {
    wakeAlarmPreviewChannel = FlutterMethodChannel(
      name: "de.khonager.trans/wake_alarm_preview",
      binaryMessenger: binaryMessenger
    )

    wakeAlarmPreviewChannel?.setMethodCallHandler { [weak self] call, result in
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

  private func registerDeviceTimezoneChannel(binaryMessenger: FlutterBinaryMessenger) {
    deviceTimezoneChannel = FlutterMethodChannel(
      name: "de.khonager.trans/device_timezone",
      binaryMessenger: binaryMessenger
    )

    deviceTimezoneChannel?.setMethodCallHandler { call, result in
      switch call.method {
      case "get":
        result(TimeZone.current.identifier)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func playWakeAlarmPreview(path: String) throws {
    stopWakeAlarmPreview()

    try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
    try AVAudioSession.sharedInstance().setActive(true)

    if AVAudioSession.sharedInstance().outputVolume == 0 {
      throw NSError(
        domain: "WakeAlarmPreview",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Your iPhone output volume is set to 0."]
      )
    }

    let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
    player.prepareToPlay()
    if !player.play() {
      throw NSError(
        domain: "WakeAlarmPreview",
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: "iOS refused to start audio playback."]
      )
    }
    wakeAlarmPreviewPlayer = player
  }

  private func stopWakeAlarmPreview() {
    wakeAlarmPreviewPlayer?.stop()
    wakeAlarmPreviewPlayer = nil
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerWakeAlarmPreviewChannel(
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    registerDeviceTimezoneChannel(
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
  }
}
