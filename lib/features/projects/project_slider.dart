import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/api_client.dart';
import '../../core/projects.dart';

/// The "Our Projects" slider, shared by the login screen and the customer home.
///
/// One widget for both because the only real difference is which endpoint the
/// images come from - and that difference is a single flag. Two near-identical
/// carousels would drift apart the first time either was touched.
/// One item on screen, whichever list it came from.
///
/// The widget draws this, not a project and not a slide. Adding the curated
/// home slider as a second source was then a matter of mapping it into this
/// shape, rather than a second copy of the page view, the auto-play timer and
/// the dots - which would have been two carousels to keep in step.
typedef SliderItem = ({String url, String? caption, String? title, String? subtitle});

class ProjectSlider extends ConsumerStatefulWidget {
  const ProjectSlider({
    super.key,
    required this.signedIn,
    this.onDark = false,
    this.height = 200,
    this.heading,
    this.leadIn,
    this.curated = false,
  });

  /// The section label, e.g. "OUR PROJECTS".
  ///
  /// Owned by this widget rather than written above it by the caller. The
  /// slider renders nothing when the builder has uploaded no photographs, and
  /// a heading outside it survived that - so both the login screen and the
  /// home screen showed "OUR PROJECTS" over an empty gap. A label and the
  /// thing it labels have to appear and disappear together, which only works
  /// if one widget decides.
  final String? heading;

  /// Rendered above the heading, and dropped with it - the home screen's rule
  /// separating this section from the one before.
  final Widget? leadIn;

  /// Signed-in sliders fetch through Dio with the bearer token; the login
  /// screen fetches the public route with no credentials at all.
  final bool signedIn;

  /// The login screen is navy; the home screen is light.
  final bool onDark;

  final double height;

  /// Draw the curated home slider instead of project photographs.
  ///
  /// The login screen cannot use it: /api/v1/slider needs a token, and the
  /// public showcase exists precisely for the screen where nobody has one.
  final bool curated;

  @override
  ConsumerState<ProjectSlider> createState() => _ProjectSliderState();
}

class _ProjectSliderState extends ConsumerState<ProjectSlider> {
  final _controller = PageController();
  Timer? _timer;
  int _index = 0;
  int _count = 0;

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Advances the slider, but only while there is more than one slide and the
  /// widget is on screen. A timer left running behind a pushed route keeps
  /// rebuilding a page nobody is looking at.
  void _startAutoPlay(int count) {
    if (_count == count) return;
    _count = count;
    _timer?.cancel();

    if (count < 2) return;

    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_controller.hasClients) return;
      final next = (_index + 1) % _count;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // Both sources resolve to List<SliderItem>, so everything below this line
    // is the same code for either.
    final AsyncValue<List<SliderItem>> source = widget.curated
        ? ref.watch(appSliderProvider).whenData((slides) => [
              for (final s in slides)
                (url: s.imageUrl, caption: s.caption, title: null, subtitle: null),
            ])
        : ref.watch(widget.signedIn ? customerShowcaseProvider : publicShowcaseProvider)
            .whenData((projects) => [
                  for (final p in projects)
                    for (final sl in p.slides)
                      (url: sl.imageUrl, caption: sl.caption, title: p.name, subtitle: p.tagline),
                ]);

    return source.when(
      // Nothing at all while loading or on error. A broken frame on the login
      // screen is worse than no frame, and the slider is decoration - it must
      // never be the reason someone cannot sign in.
      loading: () => SizedBox(height: widget.height),
      error: (_, _) => const SizedBox.shrink(),
      data: (slides) {
        if (slides.isEmpty) return const SizedBox.shrink();

        WidgetsBinding.instance.addPostFrameCallback((_) => _startAutoPlay(slides.length));

        final captionColour =
            widget.onDark ? SwarnimColors.metaOnDark : SwarnimColors.metaOnLight;
        final titleColour =
            widget.onDark ? SwarnimColors.inkOnDark : SwarnimColors.inkOnLight;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.leadIn != null) widget.leadIn!,
            if (widget.heading != null) ...[
              Text(
                widget.heading!,
                textAlign: widget.onDark ? TextAlign.center : TextAlign.start,
                style: widget.onDark
                    ? SwarnimTheme.fieldLabelDark
                    : SwarnimTheme.fieldLabel,
              ),
              const SizedBox(height: 10),
            ],
            SizedBox(
              height: widget.height,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(SwarnimRadius.image),
                child: PageView.builder(
                  controller: _controller,
                  itemCount: slides.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (context, i) => _Slide(
                    url: slides[i].url,
                    caption: slides[i].caption,
                    signedIn: widget.signedIn,
                  ),
                ),
              ),
            ),

            if (slides.length > 1) ...[
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < slides.length; i++)
                    Container(
                      width: i == _index ? 16 : 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: i == _index
                            ? SwarnimColors.gold
                            : (widget.onDark
                                ? SwarnimColors.inputUnderline
                                : SwarnimColors.borderLight),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),
            ],

            // A curated slide carries no title: it is a banner, not a
            // building, and an empty line under it would leave the dots
            // floating away from the image.
            if (slides[_index.clamp(0, slides.length - 1)].title case final title?) ...[
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: titleColour,
                ),
              ),
            ],

            if (slides[_index.clamp(0, slides.length - 1)].subtitle
                case final tagline?) ...[
              const SizedBox(height: 2),
              Text(
                tagline,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(fontSize: 11.5, color: captionColour),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _Slide extends ConsumerWidget {
  const _Slide({required this.url, required this.caption, required this.signedIn});

  final String url;
  final String? caption;
  final bool signedIn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The public route needs no Authorization header, so Image.network is
    // enough and gets the platform's own image cache. The signed-in route needs
    // the token, which only the Dio-backed widget can attach.
    final image = signedIn
        ? AuthedImage(path: url, fit: BoxFit.cover)
        : Image.network(
            '${AppConfig.apiBaseUrl}$url',
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const _Placeholder(),
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : const _Placeholder(),
          );

    return Stack(
      fit: StackFit.expand,
      children: [
        image,
        if (caption != null && caption!.isNotEmpty)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 18, 12, 10),
              decoration: BoxDecoration(
                // Scrim rather than a solid bar: captions have to stay readable
                // over a photograph without hiding the photograph.
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    SwarnimColors.navy.withValues(alpha: 0.72),
                  ],
                ),
              ),
              child: Text(
                caption!,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) => Container(
        color: SwarnimColors.borderLight.withValues(alpha: 0.3),
        child: const Center(
          child: Icon(Icons.apartment_outlined, size: 40, color: SwarnimColors.borderLight),
        ),
      );
}
