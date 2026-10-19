import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Register with Apple's push service - AFTER the line above, and that
    // ordering is the whole point. Do not move this call.
    //
    // firebase_messaging normally does this itself: its iOS plugin observes
    // UIApplicationDidFinishLaunchingNotification and calls
    // registerForRemoteNotifications from that handler, noting in its own
    // source that registration must happen early and that "calling this from
    // Dart would be too late".
    //
    // That observer is installed when the PLUGIN is registered. This project
    // uses Flutter's implicit-engine template, where plugins are registered
    // here rather than inside didFinishLaunchingWithOptions - by which time
    // the notification has already been posted. The plugin installs its
    // observer too late, never sees it, and never registers.
    //
    // It also cannot go in didFinishLaunchingWithOptions, which was the first
    // attempt. Apple answers asynchronously on
    // application:didRegisterForRemoteNotificationsWithDeviceToken:, which is
    // implemented BY THE PLUGIN and is only delivered once the plugin is in
    // the Flutter registry. Registering before that line means the token
    // comes back with nobody listening and is dropped - which looks exactly
    // like never registering at all.
    //
    // The symptom either way: Firebase starts, the permission prompt appears,
    // the user taps Allow, and getAPNSToken() then returns nil for ever, with
    // no error on the device or at Apple.
    //
    // Idempotent, and iOS returns a cached token quickly on later calls, so
    // this stays safe if a future plugin version registers as well.
    //
    // Android is unaffected - it has no APNs step, which is why none of this
    // can reproduce on an emulator.
    UIApplication.shared.registerForRemoteNotifications()
  }
}
