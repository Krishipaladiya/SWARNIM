import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../firebase_options.dart';
import 'api_client.dart';

/// Wakes a phone that is in somebody's pocket.
///
/// ## Why this exists
///
/// Nothing in the app could reach a customer who was not already looking at
/// it. The case that forced it: an engineer finishes a job and asks for the
/// confirmation code that closes the complaint. There is no SMS gateway, so
/// the code sat in the app - and the engineer stood at the door waiting for
/// the customer to think of opening it.
///
/// ## What is NOT in a notification
///
/// The confirmation code. A push is shown on a locked screen and is handled by
/// Google's servers on the way through; a code that closes a complaint belongs
/// in neither place. The server sends "a code is waiting" and the app fetches
/// the code itself over an authenticated call. The same rule applies to
/// anything else worth protecting - the payload carries ids, not contents.
///
/// ## Failure is always silent
///
/// Every method here swallows its errors. Push is an enhancement on top of a
/// system that already works by pulling: a phone with notifications denied, no
/// Play Services, or no network still sees everything the moment the app is
/// opened, because the Notification rows are read from the API like any other
/// list. A customer who cannot file a complaint because a token registration
/// failed would be a far worse outcome than one who misses a banner.
class PushService {
  PushService(this._ref);

  final Ref _ref;

  static bool _initialised = false;

  /// The token currently registered with the server, so sign-out can retire
  /// exactly that one rather than asking the SDK again at a point where it may
  /// already have been invalidated.
  String? _registered;

  /// Brings Firebase up. Called once, before the app runs.
  ///
  /// Separate from [registerForCurrentUser] because the SDK has to exist
  /// before anyone signs in - a notification tapped from a cold start is
  /// delivered during startup, not after the session is restored.
  static Future<void> initialise() async {
    if (_initialised) return;

    try {
      // Options passed explicitly rather than read from the bundled config
      // files. On iOS GoogleService-Info.plist is only bundled if it is a
      // member of the Runner target, which it was not - so this would have
      // thrown on every iPhone and push would have been quietly off. See
      // firebase_options.dart.
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      _initialised = true;
    } catch (e) {
      // A missing or malformed google-services.json lands here. The app must
      // still start: everything except notifications works without Firebase.
      debugPrint('Firebase did not start, push is off: $e');
    }
  }

  /// Asks permission, then tells the server which handset to notify.
  ///
  /// Called after a successful sign-in rather than at startup, for two
  /// reasons. The permission prompt makes sense once somebody has an account
  /// to be notified about - asking on first launch, before the login screen,
  /// is the pattern people decline out of hand. And the registration call
  /// needs a bearer token to say who the device belongs to.
  Future<void> registerForCurrentUser() async {
    if (!_initialised) return;

    try {
      final messaging = FirebaseMessaging.instance;

      final settings = await messaging.requestPermission();

      // Denied is a normal answer, not an error. Android below 13 returns
      // authorized without prompting; iOS and Android 13+ actually ask.
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      // On iOS the APNs token can lag behind the FCM one just after launch,
      // and asking for the FCM token first returns null. Waiting for APNs
      // avoids a registration that silently never happens on a real iPhone.
      if (Platform.isIOS) {
        final apns = await messaging.getAPNSToken();
        if (apns == null) return;
      }

      final token = await messaging.getToken();
      if (token == null || token.isEmpty) return;

      await _send(token);

      // Firebase replaces a token on reinstall, on a data clear, and
      // occasionally on its own. Without this the server keeps notifying a
      // token that no longer exists and the phone goes quiet for good.
      FirebaseMessaging.instance.onTokenRefresh.listen(_send);
    } catch (e) {
      debugPrint('Push registration failed: $e');
    }
  }

  Future<void> _send(String token) async {
    try {
      final info = await PackageInfo.fromPlatform();

      await _ref.read(dioProvider).post('/api/v1/devices', data: {
        'token': token,
        // 1 Android, 2 iOS - matches DevicePlatform on the server.
        'platform': Platform.isIOS ? 2 : 1,
        'appName': 1,
        'deviceModel': Platform.operatingSystemVersion,
        'appVersion': info.version,
      });

      _registered = token;
    } catch (e) {
      debugPrint('Could not register the device token: $e');
    }
  }

  /// Opens whatever the notification was about.
  ///
  /// Two entry points, and both are needed. [getInitialMessage] covers a tap
  /// that launched the app from cold; [onMessageOpenedApp] covers a tap while
  /// it was merely in the background. Wiring only the second means a
  /// notification tapped from a closed app opens the home screen, which reads
  /// as the notification being broken.
  ///
  /// A message arriving while the app is OPEN is deliberately not handled
  /// here. The system tray does not show it, and hijacking the screen someone
  /// is already using would be worse than silence - the refresh button and
  /// pull-to-refresh are how they see it.
  void wireTaps(void Function(String route) open) {
    if (!_initialised) return;

    void handle(RemoteMessage? message) {
      final route = _routeFor(message);
      if (route != null) open(route);
    }

    FirebaseMessaging.instance.getInitialMessage().then(handle);
    FirebaseMessaging.onMessageOpenedApp.listen(handle);
  }

  /// The screen a notification points at, or null if it points at nothing.
  String? _routeFor(RemoteMessage? message) {
    if (message == null) return null;

    final data = message.data;

    // The PUBLIC id. The integer key is in the payload too, for the office to
    // quote, but every route in this app is addressed by the GUID.
    final id = data['entityPublicId'] as String?;
    if (id == null || id.isEmpty) return null;

    // 1 = Complaint, matching OtpEntityType on the server. Anything else is
    // from a newer server than this build and is ignored rather than guessed.
    if (data['entityType'] != '1') return null;

    return _isStaff ? '/staff/complaints/$id' : '/complaints/$id';
  }

  /// Which app surface this session is, so a tap lands on the right screen.
  /// Set at registration, because the token already knows.
  bool _isStaff = false;

  set isStaff(bool value) => _isStaff = value;

  /// Retires this handset on sign-out.
  ///
  /// Site staff share a phone. Without this the next person to sign in would
  /// keep receiving the previous engineer's notifications, because the token
  /// is the device and the device has not changed.
  Future<void> unregister() async {
    final token = _registered;
    if (token == null) return;

    _registered = null;

    try {
      await _ref.read(dioProvider).delete('/api/v1/devices/$token');
    } catch (e) {
      // The session is ending either way; the server also reassigns a token
      // when somebody else signs in on the same handset.
      debugPrint('Could not retire the device token: $e');
    }
  }
}

final pushServiceProvider = Provider<PushService>(PushService.new);
