import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Register with Apple's push service ourselves.
    //
    // WHY THIS LINE EXISTS - it is not boilerplate, and removing it breaks
    // push on iOS silently.
    //
    // firebase_messaging normally does this for us. Its iOS plugin observes
    // UIApplicationDidFinishLaunchingNotification and calls
    // registerForRemoteNotifications from that handler, with a comment in its
    // own source explaining that registration has to happen early in app
    // initialisation and that calling it from Dart would be too late.
    //
    // That observer is installed when the PLUGIN is registered. This project
    // uses Flutter's newer implicit-engine template, where
    // GeneratedPluginRegistrant.register runs in
    // didInitializeImplicitFlutterEngine, below - which happens AFTER
    // UIApplicationDidFinishLaunchingNotification has already been posted.
    // So the plugin installs its observer too late, never sees the
    // notification, and never registers.
    //
    // The symptom is brutal to diagnose: Firebase starts, the permission
    // prompt appears, the user taps Allow, and getAPNSToken() then returns
    // nil for ever. No error, on the device or at Apple. Every piece of
    // configuration looks correct because it is correct.
    //
    // Calling it here puts registration back inside didFinishLaunching, where
    // the plugin expects it to have happened. It is idempotent, so it does no
    // harm if a future plugin version also calls it.
    //
    // Android is unaffected - it has no APNs step at all, which is why this
    // could never have shown up in an emulator.
    application.registerForRemoteNotifications()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
