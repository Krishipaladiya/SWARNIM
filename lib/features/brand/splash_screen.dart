import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';

/// The Swarnim wordmark, on the navy the artwork was cut against.
///
/// The supplied logo is gold **and white** type on solid `#0D2031`. That is why
/// it sits flush on the app's navy chrome with no cut-out, and also why it can
/// never go on a light surface: "GROUP" and "TRUST · BUILD · GROW" would
/// disappear.
class SwarnimLogo extends StatelessWidget {
  const SwarnimLogo({super.key, this.width = 200});

  final double width;

  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/brand/logo.png',
        width: width,
        // The asset's own background is the page background, so a failure to
        // decode should leave the navy rather than a broken-image box.
        errorBuilder: (_, _, _) => SizedBox(width: width, height: width * 0.8),
      );
}

/// Whether the launch animation has finished.
///
/// The router holds on `/splash` until this is true, so the animation is
/// actually seen. Without it the screen is correct but invisible: restoring a
/// session takes a few hundred milliseconds and the router moves on before the
/// first frame is drawn.
///
/// It latches. The animation is a cold-start moment, not something to sit
/// through again after signing out.
final splashDoneProvider = NotifierProvider<SplashDone, bool>(SplashDone.new);

class SplashDone extends Notifier<bool> {
  @override
  bool build() => false;

  void done() => state = true;
}

/// The launch screen: the brand animation, then straight to the app.
///
/// **Why the GIF and not the MP4.** The supplied MP4 is HEVC, recorded on an
/// iPhone. It plays on modern hardware, but plenty of cheaper Android handsets
/// have no HEVC decoder - and even where it works, ExoPlayer needs a platform
/// view and a codec handshake before the first frame, which meant nobody ever
/// saw the animation. `Image.asset` animates a GIF on the raster thread with no
/// plugin, no codec and nothing to fail.
///
/// **Nothing else draws the wordmark.** The Android launch screen, the iOS
/// storyboard and this scaffold are all bare [SwarnimColors.splashField] - the
/// animation's own background colour, sampled from the file. They used to carry
/// the finished logo, so the launch read as: final wordmark, then the animation
/// starting over from an empty field and drawing it again. The ending, then the
/// beginning. Now the field never changes and the animation is the only thing
/// that ever appears on it.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  /// The animation's own length, read from the file: 96 frames totalling 4000 ms.
  ///
  /// A GIF cannot report when it has finished, so the hand-off is timed.
  static const _animation = Duration(milliseconds: 4000);

  /// Covers the gap between the frame being available and it being on screen.
  static const _margin = Duration(milliseconds: 250);

  /// However slow the device, the app still has to start.
  ///
  /// If decoding stalls or the asset is broken, this is what gets the user to
  /// the login screen anyway. A launch screen must never be the reason the app
  /// will not open.
  static const _backstop = Duration(seconds: 8);

  static const _image = AssetImage('assets/brand/splash.gif');

  ImageStream? _stream;
  ImageStreamListener? _listener;
  Timer? _timer;
  bool _started = false;

  @override
  void initState() {
    super.initState();

    // Start the clock when the first frame is actually decoded, NOT here.
    //
    // This is the whole trick. Decoding a 894x714, 96-frame GIF takes a real
    // fraction of a second - and on a debug build, several. A timer started in
    // initState spends that budget on an empty screen and then navigates away
    // just as the animation becomes visible, which is exactly what it did: the
    // animation flashed for one frame and was gone.
    _listener = ImageStreamListener(
      (_, _) => _begin(_animation + _margin),
      onError: (_, _) => _begin(Duration.zero),
    );
    _stream = _image.resolve(const ImageConfiguration())..addListener(_listener!);

    _timer = Timer(_backstop, _finish);
  }

  /// Runs the animation for [after], then hands over. First call wins.
  void _begin(Duration after) {
    if (_started || !mounted) return;
    _started = true;
    _timer?.cancel();
    _timer = Timer(after, _finish);
  }

  void _finish() {
    if (mounted) ref.read(splashDoneProvider.notifier).done();
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_listener != null) _stream?.removeListener(_listener!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SwarnimColors.splashField,
      body: Center(
        child: Image(
          image: _image,

          // Contain, not cover. The animation draws a wide wordmark; filling a
          // tall phone with it would crop the ends off the very thing it spells.
          fit: BoxFit.contain,
          width: double.infinity,
          gaplessPlayback: true,

          // If the asset is missing or will not decode, show the static logo
          // rather than a broken-image glyph.
          errorBuilder: (_, _, _) => const _StaticBrand(),
        ),
      ),
    );
  }
}

/// The fallback if the animation cannot be decoded.
class _StaticBrand extends StatelessWidget {
  const _StaticBrand();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(48),
        child: SwarnimLogo(width: 260),
      );
}
