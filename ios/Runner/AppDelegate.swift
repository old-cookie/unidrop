import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let shareChannelName = "com.oldcokie.unidrop/share"
  private let sharedMediaDefaultsKey = "unidrop_shared_media_payload"
  private let hostUrlSchemeDefaultsKey = "unidrop_host_url_scheme"

  private var shareChannel: FlutterMethodChannel?
  private var initialSharedMedia: [[String: String]] = []

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    updateSharedHostUrlScheme()
    initialSharedMedia = loadSharedMediaFromDefaults()
    setupShareChannelIfNeeded()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    setupShareChannelIfNeeded()
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if isShareUrl(url) {
      let media = loadSharedMediaFromDefaults()
      initialSharedMedia = media
      if !media.isEmpty {
        DispatchQueue.main.async { [weak self] in
          self?.shareChannel?.invokeMethod("onSharedMedia", arguments: media)
        }
      }
      return true
    }

    return super.application(app, open: url, options: options)
  }

  private func setupShareChannelIfNeeded() {
    guard shareChannel == nil,
          let controller = window?.rootViewController as? FlutterViewController else {
      return
    }

    let channel = FlutterMethodChannel(
      name: shareChannelName,
      binaryMessenger: controller.binaryMessenger
    )

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "UNAVAILABLE", message: "AppDelegate released", details: nil))
        return
      }

      switch call.method {
      case "getInitialSharedMedia":
        result(self.initialSharedMedia)
      case "clearInitialSharedMedia":
        self.initialSharedMedia = []
        self.clearSharedMediaFromDefaults()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    shareChannel = channel
  }

  private func isShareUrl(_ url: URL) -> Bool {
    return url.scheme?.hasPrefix("ShareMedia-") ?? false
  }

  private func appGroupId() -> String {
    if let configured = Bundle.main.object(forInfoDictionaryKey: "AppGroupId") as? String,
       !configured.isEmpty {
      return configured
    }

    if let bundleId = Bundle.main.bundleIdentifier, !bundleId.isEmpty {
      return "group.\(bundleId)"
    }

    return "group.com.oldcokie.unidrop"
  }

  private func loadSharedMediaFromDefaults() -> [[String: String]] {
    guard let defaults = UserDefaults(suiteName: appGroupId()) else {
      return []
    }

    if let json = defaults.string(forKey: sharedMediaDefaultsKey),
       let data = json.data(using: .utf8),
       let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
      return raw.compactMap { entry in
        guard let path = entry["path"] as? String,
              let fileName = entry["fileName"] as? String else {
          return nil
        }
        let mimeType = (entry["mimeType"] as? String) ?? ""
        return [
          "path": path,
          "fileName": fileName,
          "mimeType": mimeType,
        ]
      }
    }

    if let rawArray = defaults.array(forKey: sharedMediaDefaultsKey) as? [[String: String]] {
      return rawArray
    }

    return []
  }

  private func clearSharedMediaFromDefaults() {
    guard let defaults = UserDefaults(suiteName: appGroupId()) else {
      return
    }
    defaults.removeObject(forKey: sharedMediaDefaultsKey)
    defaults.synchronize()
  }

  private func updateSharedHostUrlScheme() {
    guard let defaults = UserDefaults(suiteName: appGroupId()) else {
      return
    }
    let bundleId = Bundle.main.bundleIdentifier ?? ""
    guard !bundleId.isEmpty else {
      return
    }
    defaults.set("ShareMedia-\(bundleId)", forKey: hostUrlSchemeDefaultsKey)
    defaults.synchronize()
  }
}
