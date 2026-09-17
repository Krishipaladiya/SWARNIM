import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'app/theme.dart';

/// The app's chrome is navy everywhere, so the system bars must draw LIGHT
/// icons everywhere.
///
/// Declared once, here, and asserted on every frame by the
/// [AnnotatedRegion] in the builder below. Calling
/// [SystemChrome.setSystemUIOverlayStyle] at startup is not enough on its own -
/// it is a one-shot write that Flutter overwrites as soon as anything in the
/// tree expresses an opinion, and the result was a black clock and black
/// battery icon sitting on navy.
const _systemBars = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarBrightness: Brightness.dark,          // iOS
  statusBarIconBrightness: Brightness.light,     // Android
  systemNavigationBarColor: Color(0xFF0D2031),
  systemNavigationBarIconBrightness: Brightness.light,
  systemNavigationBarDividerColor: Color(0xFF0D2031),
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(_systemBars);

  // Poppins comes from the bundle, never from the network.
  //
  // Left on, google_fonts fetches the family from fonts.gstatic.com the first
  // time it is used. That puts a network round trip in front of the app's own
  // typeface: on a slow connection the text renders in a fallback and then
  // reflows, and on a connection that hangs rather than fails it blocked the
  // UI thread long enough for Android to offer to close the app. Customers on
  // Indian mobile data get exactly that connection.
  //
  // The font files are declared in pubspec under assets/google_fonts/, which
  // is where google_fonts looks first. Turning fetching OFF makes a missing
  // weight a loud error during development instead of a silent download in a
  // customer's hand.
  GoogleFonts.config.allowRuntimeFetching = false;

  runApp(const ProviderScope(child: SwarnimConnectApp()));
}

class SwarnimConnectApp extends ConsumerWidget {
  const SwarnimConnectApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Swarnim Connect',
      debugShowCheckedModeBanner: false,
      theme: SwarnimTheme.build(),
      routerConfig: ref.watch(routerProvider),

      // Customers will hold phones with system font scaling turned up. Allow
      // it, but cap it so a 44px control cannot grow past its own row.
      // Wraps every route, so no screen has to remember either of these.
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: _systemBars,
        child: MediaQuery.withClampedTextScaling(
          minScaleFactor: 1.0,
          maxScaleFactor: 1.3,
          child: child!,
        ),
      ),
    );
  }
}
