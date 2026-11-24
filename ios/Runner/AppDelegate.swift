import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private static func configuredMapsApiKey() -> String {
    let raw = (Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if raw.isEmpty || raw.hasPrefix("$(") {
      return ""
    }
    return raw
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Key comes from ios/Flutter/Secrets.xcconfig (git-ignored): MAPS_API_KEY=your-key
    let apiKey = Self.configuredMapsApiKey()
    if !apiKey.isEmpty {
      GMSServices.provideAPIKey(apiKey)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CleanSpotMapsChannel") {
      let channel = FlutterMethodChannel(
        name: "com.example.clean_spot/maps",
        binaryMessenger: registrar.messenger()
      )
      channel.setMethodCallHandler { call, result in
        let key = Self.configuredMapsApiKey()
        switch call.method {
        case "hasMapsApiKey":
          result(!key.isEmpty)
        case "getMapsApiKey":
          result(key)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }
}
