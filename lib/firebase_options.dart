import 'dart:io';

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

/// The Firebase project, compiled in.
///
/// ## Why this file exists rather than the config files alone
///
/// On Android the Google Services Gradle plugin reads
/// `android/app/google-services.json` at build time and there is nothing more
/// to do. iOS has no equivalent: it expects `GoogleService-Info.plist` to be a
/// member of the Runner target in the Xcode project, and a file merely sitting
/// in `ios/Runner/` is not bundled. It was not a member, so on iOS
/// `Firebase.initializeApp()` would have thrown, push would have been off, and
/// nothing would have said so - the failure is caught and logged.
///
/// Passing the options explicitly removes that trap entirely. The values are
/// the same ones in the two config files, and neither file has to be wired
/// into the Xcode project for Firebase to start.
///
/// ## These are not secrets
///
/// A Firebase API key identifies the project; it does not authorise anything.
/// It ships inside every copy of the app and Google documents it as public.
/// The key that can actually send notifications is the service account, which
/// lives on the server and is not in this repository.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform =>
      Platform.isIOS ? ios : android;

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyB0iSq1ACqrscDQ0IBJ18KxV-PPTYkDQKs',
    appId: '1:257722816651:android:ea0447f170dc7d227a9c8e',
    messagingSenderId: '257722816651',
    projectId: 'swarnim-connect',
    storageBucket: 'swarnim-connect.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAZhP-sJN7clAZITdLoOulwwHYjcqTKQI0',
    appId: '1:257722816651:ios:28aaf4d1bf2c018c7a9c8e',
    messagingSenderId: '257722816651',
    projectId: 'swarnim-connect',
    storageBucket: 'swarnim-connect.firebasestorage.app',
    iosBundleId: 'in.cloudverve.swarnim',
  );
}
