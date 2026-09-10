import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'app/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // The app is dark-only, so the system bars must be told to draw light icons.
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0D2031),
    systemNavigationBarIconBrightness: Brightness.light,
  ));

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
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        minScaleFactor: 1.0,
        maxScaleFactor: 1.3,
        child: child!,
      ),
    );
  }
}
