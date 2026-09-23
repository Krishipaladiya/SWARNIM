import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:swarnim_connect/main.dart' as app;

/// Captures the App Store screenshots by driving the real app.
///
/// WHY THIS RUNS ON A SIMULATOR RATHER THAN BEING MOCKED UP
///
/// Apple wants screenshots of the app as it actually is, at an exact pixel
/// size. An iPhone 16 Pro Max simulator renders at 1320x2868 and an iPad Pro
/// 13" at 2064x2752, both of which Apple accepts as-is - so capturing on those
/// two devices means nothing is ever resized, and a resized screenshot looks
/// resized. It also means the images cannot drift from the shipped app: they
/// are re-taken from the same commit that builds the binary.
///
/// SIGNING IN
///
/// The login screen needs no account, so it is always captured. Everything
/// past it does, and the credentials are passed in at build time:
///
///   --dart-define=SCREENSHOT_USER=... --dart-define=SCREENSHOT_PASS=...
///
/// Without them the run captures the login screen and stops, rather than
/// failing the build - a missing screenshot account should not break the
/// pipeline that also ships the binary. Use a dedicated demo flat, never a real
/// customer: whatever is on screen goes onto a public product page, and a real
/// resident's name, mobile number and complaints would go with it.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const user = String.fromEnvironment('SCREENSHOT_USER');
  const pass = String.fromEnvironment('SCREENSHOT_PASS');

  // Android renders Flutter into a surface the framework cannot read back
  // until it is converted - and the conversion asserts !_isSurfaceRendered, so
  // it may happen exactly ONCE per run. Calling it before every capture throws
  // on the second one, which is a failed build with the first screenshot
  // already written to disk and nothing obviously wrong in the output.
  //
  // iOS needs none of this; takeScreenshot reads the layer directly.
  var surfaceConverted = false;

  /// One capture.
  ///
  /// settle() first, every time. A screenshot taken mid-animation catches a
  /// half-faded card or a bottom sheet part-way up, and that is exactly the
  /// frame that ends up on the store page.
  Future<void> shoot(WidgetTester tester, String name) async {
    await tester.pumpAndSettle(const Duration(milliseconds: 400));

    if (Platform.isAndroid && !surfaceConverted) {
      await binding.convertFlutterSurfaceToImage();
      surfaceConverted = true;
      await tester.pumpAndSettle();
    }

    await binding.takeScreenshot(name);
  }

  /// Waits for something to appear, then reports whether it did.
  ///
  /// Returns false instead of throwing: a screen that did not load is a
  /// screenshot worth skipping, not a build worth failing. The caller decides.
  Future<bool> waitFor(WidgetTester tester, Finder finder,
      {Duration timeout = const Duration(seconds: 30)}) async {
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 300));
      if (finder.evaluate().isNotEmpty) return true;
    }

    return false;
  }

  testWidgets('App Store screenshots', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // ---------------------------------------------------------- 01 · sign in
    final signIn = find.text('Sign In');
    if (await waitFor(tester, signIn)) {
      await shoot(tester, '01-sign-in');
    } else {
      // Already signed in from a previous run on this simulator. Nothing to
      // do about it here, and the screens below are the ones that matter.
      debugPrint('screenshots: login screen not shown, carrying on');
    }

    if (user.isEmpty || pass.isEmpty) {
      debugPrint('screenshots: no SCREENSHOT_USER/PASS, stopping after login');
      return;
    }

    // ------------------------------------------------------------ signing in
    final fields = find.byType(TextFormField);
    if (fields.evaluate().length >= 2) {
      await tester.enterText(fields.at(0), user);
      await tester.pumpAndSettle();
      await tester.enterText(fields.at(1), pass);
      await tester.pumpAndSettle();

      await tester.tap(signIn);

      // Deliberately generous. This talks to the live API over the simulator's
      // network, and a cold app pool on shared hosting can take a while to
      // answer the first request of the day.
      await tester.pumpAndSettle(const Duration(seconds: 2));
      await waitFor(tester, find.text('QUICK ACTIONS'), timeout: const Duration(seconds: 40));
    }

    // -------------------------------------------------------------- 02 · home
    if (find.text('QUICK ACTIONS').evaluate().isNotEmpty) {
      await shoot(tester, '02-home');
    } else {
      debugPrint('screenshots: sign-in did not reach the home screen');
      return;
    }

    // The bottom bar is a plain Row of icons, not a NavigationBar, and the
    // labels are not rendered - so the icon IS the handle. Tapping by index
    // would be neater but the items are a private widget the test cannot see.
    Future<void> tab(IconData icon, String name, Finder landmark) async {
      final target = find.byIcon(icon);
      if (target.evaluate().isEmpty) {
        debugPrint('screenshots: no tab for $icon, skipping $name');
        return;
      }

      await tester.tap(target.first);
      await tester.pumpAndSettle(const Duration(milliseconds: 600));

      // A tab that never loads is skipped rather than captured: an empty
      // spinner is worse on a product page than one fewer screenshot.
      if (!await waitFor(tester, landmark, timeout: const Duration(seconds: 25))) {
        debugPrint('screenshots: $name did not load, skipping');
        return;
      }

      await shoot(tester, name);
    }

    await tab(Icons.assignment_outlined, '03-complaints', find.text('My Complaints'));
    await tab(Icons.folder_outlined, '04-documents', find.textContaining('Document'));
    await tab(Icons.person_outline, '05-profile', find.text('My Profile'));
  });
}
