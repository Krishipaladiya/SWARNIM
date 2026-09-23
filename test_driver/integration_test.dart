import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Receives the frames captured by integration_test/screenshots_test.dart and
/// writes them where `fastlane deliver` looks for them.
///
/// Why the files land in fastlane/screenshots/en-US rather than anywhere
/// tidier: deliver reads that folder and works out which App Store slot each
/// image belongs to FROM ITS PIXEL SIZE. An iPhone 16 Pro Max simulator
/// renders at 1320x2868 and an iPad Pro 13" at 2064x2752, which are already
/// two of the sizes Apple accepts - so nothing is resized, cropped or padded
/// anywhere in this pipeline. A resized screenshot is a rejected screenshot.
///
/// The name each frame arrives under is set in the test, and the leading
/// number is load-bearing: App Store Connect orders screenshots
/// alphabetically, so "01-login" before "02-home" is what puts the login
/// screen first on the product page.
Future<void> main() => integrationDriver(
      onScreenshot: (String name, List<int> bytes, [Map<String, Object?>? args]) async {
        // SCREENSHOT_DIR lets the CI job point each simulator run at its own
        // folder. Without it everything lands in one place, which is fine
        // locally and wrong in CI - the second device would overwrite the
        // first, and deliver would upload one set twice.
        final dir = Platform.environment['SCREENSHOT_DIR'] ??
            'fastlane/screenshots/en-US';

        // Both devices write into the SAME locale folder, because that is
        // where deliver looks and it tells them apart by pixel size. Which
        // means the names must not collide: without a prefix the iPad run
        // overwrites the iPhone run file for file, and the upload silently
        // carries one set twice.
        final prefix = Platform.environment['SCREENSHOT_PREFIX'] ?? '';

        final file = File('$dir/$prefix$name.png');
        await file.create(recursive: true);
        await file.writeAsBytes(bytes);

        stdout.writeln('captured $dir/$prefix$name.png (${bytes.length} bytes)');
        return true;
      },
    );
