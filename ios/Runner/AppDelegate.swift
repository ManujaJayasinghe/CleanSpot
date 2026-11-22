import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Key comes from ios/Flutter/Secrets.xcconfig (git-ignored): MAPS_API_KEY=your-key
    let infoKey = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String
    let apiKey = (infoKey != nil && !infoKey!.isEmpty && !infoKey!.hasPrefix("$("))
      ? infoKey!
      : "AIzaSyANLC73Ygb4w3da30nZ3XPE1aPVe-OaCN0"
    GMSServices.provideAPIKey(apiKey)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
