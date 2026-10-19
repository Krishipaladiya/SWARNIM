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
    // ordering is the entire point.
    //
    // THE PROBLEM
    //
    // firebase_messaging normally does this itself: its iOS plugin observes
    // UIApplicationDidFinishLaunchingNotification and calls
    // registerForRemoteNotifications from that handler, noting in its own
    // source that this must happen early and that "calling this from Dart
    // would be too late".
    //
    // That observer is installed when the PLUGIN is registered. This project
    // uses Flutter's newer implicit-engine template, where plugins are
    // registered here rather than inside didFinishLaunchingWithOptions - by
    // which time UIApplicationDidFinishLaunchingNotification has already been
    // posted. The plugin installs its observer too late, never sees the
    // notification, and never registers. getAPNSToken() then returns nil for
    // ever.
    //
    // WHY HERE AND NOT IN didFinishLaunchingWithOptions
    //
    // Calling it there - the obvious place, and where this was first put -
    // does not work either. Apple answers asynchronously on
    // application:didRegisterForRemoteNotificationsWithDeviceToken:, which is
    // implemented BY THE PLUGIN; it is only delivered once the plugin is in
    // the Flutter registry. Registering before that line means the token
    // arrives with nobody listening and is dropped, which looks identical to
    // not registering at all.
    //
    // Here, the plugin is already registered and will receive the callback.
    // Firebase itself need not be configured yet - the plugin caches the
    // token when FIRMessaging is still nil and applies it once Dart brings
    // Firebase up.
    //
    // Idempotent, and iOS returns a cached token quickly on later calls, so
    // this is safe if a future plugin version also registers.
    //
    // Android is unaffected: it has no APNs step at all, which is why none of
    // this could ever reproduce on an emulator.
    UIApplication.shared.registerForRemoteNotifications()
  }
}
