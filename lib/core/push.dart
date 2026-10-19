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

  /// What happened the last time registration ran, in one short sentence.
  ///
  /// Shown on the account screen. A TestFlight build has no console, so
  /// without this the only symptom of a failure is an empty table on the
  /// server and no way to tell which step gave up.
  static String _status = 'Not set up yet.';

  static String get status => _status;

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
    if (!_initialised) {
      _status = 'Notifications are unavailable on this build.';
      return;
    }

    try {
      final messaging = FirebaseMessaging.instance;

      final settings = await messaging.requestPermission();

      // Denied is a normal answer, not an error. Android below 13 returns
      // authorized without prompting; iOS and Android 13+ actually ask.
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        _status = 'Notifications are turned off for this app.';
        return;
      }

      // Show the banner even when the app is open.
      //
      // iOS does NOT display a notification while the app is in the
      // foreground - it hands it silently to the app and shows nothing. That
      // is Apple's default and it is wrong for this app: an engineer reading
      // a complaint when the closure code arrives, or a resident with the app
      // open when their engineer picks the job up, would see nothing at all.
      // It also made testing deeply confusing, because the server reported
      // the message as delivered and the phone stayed blank.
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // On iOS the APNs token can lag behind the FCM one just after launch,
      // and asking for the FCM token first returns null. Waiting for APNs
      // avoids a registration that silently never happens on a real iPhone.
      if (Platform.isIOS && !await _waitForApns(messaging)) {
        _status = 'Apple did not issue a push token for this device.';
        return;
      }

      final token = await messaging.getToken();
      if (token == null || token.isEmpty) {
        _status = 'No notification token was issued.';
        return;
      }

      await _send(token);

      // Firebase replaces a token on reinstall, on a data clear, and
      // occasionally on its own. Without this the server keeps notifying a
      // token that no longer exists and the phone goes quiet for good.
      FirebaseMessaging.instance.onTokenRefresh.listen(_send);
    } catch (e) {
      _status = 'Notification setup failed on this device.';
      debugPrint('Push registration failed: $e');
    }
  }

  /// Waits for Apple to hand over the device's APNs token.
  ///
  /// WHY A WAIT AND NOT A SINGLE CALL
  ///
  /// This asked once and gave up on null. On a real iPhone the APNs token is
  /// almost always null for the first few seconds after launch - registration
  /// with Apple is asynchronous and has not finished by the time somebody has
  /// typed a password and signed in. So on every real device the answer was
  /// null, this returned, and no token was ever registered. Nothing in the
  /// logs, nothing on screen: the database simply stayed empty, which is
  /// exactly what it did.
  ///
  /// It never showed in testing because Android has no APNs step at all.
  ///
  /// Asking for the FCM token before APNs is ready is not an option either -
  /// it throws on iOS. So this polls briefly and then gives up honestly.
  Future<bool> _waitForApns(FirebaseMessaging messaging) async {
    // Ten seconds in short steps. Long enough for a slow first launch on a
    // cold network, short enough that nobody is kept waiting - this runs in
    // the background and the app is already usable.
    for (var attempt = 0; attempt < 20; attempt++) {
      final apns = await messaging.getAPNSToken();
      if (apns != null && apns.isNotEmpty) return true;

      await Future<void>.delayed(const Duration(milliseconds: 500));
    }

    return false;
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
      _status = 'On. This device will receive notifications.';
    } catch (e) {
      _status = 'Could not reach the server to register this device.';
      debugPrint('Could not register the device token: $e');
    }
  }

  /// Opens whatever the notification was about.
  ///
  /// Two entry points, and both are needed. [getInitialMessage] covers a tap
  /// that launched the app from cold; [onMessageOpenedApp] covers a tap while
  /// it was merely in the background. Wiring only the second means a
  /// notification tapped from a closed app opens the home screen, which reads
  /// as the notification doing nothing.
  ///
  /// A message arriving while the app is already OPEN is deliberately not
  /// routed. iOS now shows the banner (see
  /// setForegroundNotificationPresentationOptions above), and throwing
  /// somebody off the screen they are using because a notification arrived
  /// would be worse than letting them tap it.
  void wireTaps(void Function(String route) open) {
    _open = open;

    if (!_initialised) return;

    FirebaseMessaging.instance.getInitialMessage().then(_handleTap);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);
  }

  void Function(String route)? _open;

  /// A tap that arrived before the app knew who was signed in.
  String? _pendingEntityId;

  /// Set once the session is restored or a sign-in completes.
  bool _sessionReady = false;

  void _handleTap(RemoteMessage? message) {
    final id = _entityIdOf(message);
    if (id == null) return;

    // THE COLD-START CASE, which is most taps.
    //
    // getInitialMessage resolves within moments of launch - before the stored
    // tokens have been read, so the app does not yet know whether this is a
    // customer or a member of staff, and the two have different routes for
    // the same complaint. Worse, the router is still on its splash redirect
    // and would discard anything pushed now.
    //
    // So the tap is held and replayed by [onSessionReady] once both are
    // settled. Taps while the app is merely in the background skip this,
    // because the session is already known.
    if (!_sessionReady) {
      _pendingEntityId = id;
      return;
    }

    _openComplaint(id);
  }

  /// Called when the session is known - a fresh sign-in or a restored one.
  void onSessionReady({required bool isStaff}) {
    _isStaff = isStaff;
    _sessionReady = true;

    final pending = _pendingEntityId;
    if (pending == null) return;

    _pendingEntityId = null;

    // One frame later, so the router has finished the redirect it performs
    // the moment the session becomes known. Pushing into the middle of that
    // loses the route.
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      _openComplaint(pending);
    });
  }

  void _openComplaint(String id) =>
      _open?.call(_isStaff ? '/staff/complaints/$id' : '/complaints/$id');

  /// The complaint a notification points at, or null if it points at nothing.
  String? _entityIdOf(RemoteMessage? message) {
    if (message == null) return null;

    final data = message.data;

    // The PUBLIC id. The integer key is in the payload too, for the office to
    // quote, but every route in this app is addressed by the GUID.
    final id = data['entityPublicId'] as String?;
    if (id == null || id.isEmpty) return null;

    // 1 = Complaint, matching OtpEntityType on the server. Anything else came
    // from a newer server than this build and is ignored rather than guessed
    // at - a wrong route is worse than none.
    if (data['entityType'] != '1') return null;

    return id;
  }

  bool _isStaff = false;

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
