import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/api_client.dart';
import 'theme.dart';

/// Bytes for one authenticated file, by API path.
///
/// Fetched through Dio rather than [Image.network] because these endpoints need
/// a bearer token - and going through Dio means the auth interceptor attaches
/// it and refreshes an expired one, which a raw image request cannot.
///
/// Keyed on the whole path, not just an id: complaint attachments and project
/// photographs live behind different routes with different rules, and a
/// provider that assumed one prefix silently 404s the other.
final fileBytesProvider = FutureProvider.family<List<int>, String>((ref, path) async {
  final response = await ref.watch(dioProvider).get<List<int>>(
        path,
        options: Options(responseType: ResponseType.bytes),
      );
  return response.data ?? const [];
});

/// An image served from an authenticated endpoint.
class AuthedImage extends ConsumerWidget {
  const AuthedImage({super.key, required this.path, this.fit = BoxFit.cover});

  /// Full API path, e.g. `/api/v1/files/<id>` or `/api/v1/project-images/<id>`.
  final String path;

  final BoxFit fit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(fileBytesProvider(path)).when(
          loading: () => Container(
            color: SwarnimColors.borderLight.withValues(alpha: 0.35),
            child: const Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 1.6),
              ),
            ),
          ),
          error: (_, _) => Container(
            color: SwarnimColors.borderLight.withValues(alpha: 0.35),
            child: const Center(
              child: Icon(Icons.broken_image_outlined,
                  size: 22, color: SwarnimColors.metaOnLight),
            ),
          ),
          data: (bytes) => Image.memory(
            Uint8List.fromList(bytes),
            fit: fit,
            gaplessPlayback: true,
          ),
        );
  }
}

/// The frame every screen uses: navy header, light scrolling body.
///
/// The real system status bar draws over the navy header - we do not paint a
/// fake one. The mockup shows "9:41" and a notch because it is a picture of a
/// phone; reproducing that in the app would render twice on a real device.
class SwarnimScreen extends StatelessWidget {
  const SwarnimScreen({
    super.key,
    required this.title,
    this.subtitle,
    this.eyebrow,
    this.leading,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(24, 20, 24, 24),
  });

  final String title;
  final String? subtitle;

  /// Small uppercase line above the title, e.g. "YOUR UNIT".
  final String? eyebrow;

  final Widget? leading;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    // Its own Scaffold rather than borrowing the shell's. A screen that only
    // renders when some ancestor happens to provide Material is a trap: it
    // works inside the tab shell and crashes the first time it is pushed on the
    // root navigator, which is exactly what the staff routes do.
    return Scaffold(
      backgroundColor: SwarnimColors.navy,
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: SwarnimColors.navy,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (leading != null) ...[
                      leading!,
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (eyebrow != null) ...[
                            Text(
                              eyebrow!.toUpperCase(),
                              style: SwarnimTheme.fieldLabelDark,
                            ),
                            const SizedBox(height: 8),
                          ],
                          Text(title, style: SwarnimTheme.screenTitle),
                          if (subtitle != null) ...[
                            const SizedBox(height: 4),
                            Text(subtitle!, style: SwarnimTheme.screenSubtitle),
                          ],
                        ],
                      ),
                    ),
                    ?trailing,
                  ],
                ),
              ),
            ),
          ),
          Container(height: 1, color: SwarnimColors.dividerDark),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: SwarnimColors.bodyGradient,
              ),
              child: SingleChildScrollView(padding: padding, child: child),
            ),
          ),
        ],
      ),
    );
  }
}

/// Light card with the gold rule down its left edge - the signature element of
/// this design. [accent] overrides the rule colour (goldSoft marks the cards
/// that need the customer's attention).
class SwarnimCard extends StatelessWidget {
  const SwarnimCard({
    super.key,
    required this.child,
    this.accent = SwarnimColors.gold,
    this.onTap,
    this.margin = const EdgeInsets.only(bottom: 12),
  });

  final Widget child;
  final Color accent;
  final VoidCallback? onTap;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        gradient: SwarnimColors.cardGradient,
        borderRadius: BorderRadius.circular(SwarnimRadius.control),
        border: Border(left: BorderSide(color: accent, width: 4)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    );
  }
}

enum ComplaintPillStyle { inProgress, awaitingVerification, open, resolved }

class StatusPill extends StatelessWidget {
  const StatusPill(this.label, {super.key, required this.style});

  final String label;
  final ComplaintPillStyle style;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (style) {
      ComplaintPillStyle.inProgress => (
        SwarnimColors.navyMid,
        SwarnimColors.gold,
      ),
      ComplaintPillStyle.awaitingVerification => (
        SwarnimColors.goldSoft,
        Colors.white,
      ),
      ComplaintPillStyle.open => (SwarnimColors.statusOpen, Colors.white),
      ComplaintPillStyle.resolved => (
        SwarnimColors.statusResolvedBg,
        SwarnimColors.metaOnLight,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

/// Uppercase label above a field or list section, on the light body.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key, this.topGap = 0});

  final String text;
  final double topGap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: topGap, bottom: 8),
      child: Text(text.toUpperCase(), style: SwarnimTheme.fieldLabel),
    );
  }
}

/// Pale outlined button used for quick actions and secondary choices.
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.selected = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  /// Used by the priority chooser, where one of three is active.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    // A button with no handler has to look unavailable. Without this a dead
    // control is indistinguishable from a live one and reads as a broken app.
    final enabled = onPressed != null;
    final content = enabled
        ? SwarnimColors.inkOnLight
        : SwarnimColors.metaOnLight.withValues(alpha: 0.55);

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: enabled ? SwarnimColors.secondaryButtonGradient : null,
        color: enabled
            ? null
            : SwarnimColors.borderLight.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(SwarnimRadius.control),
        border: Border.all(
          color: selected ? SwarnimColors.gold : SwarnimColors.borderLight,
          width: selected ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(SwarnimRadius.control),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 13),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20, color: content),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: content,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dashed evidence-upload target.
class UploadBox extends StatelessWidget {
  const UploadBox({
    super.key,
    this.onTap,
    this.label = 'Upload image or video',
  });

  final VoidCallback? onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: CustomPaint(
        painter: _DashedBorderPainter(),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
          decoration: const BoxDecoration(gradient: SwarnimColors.cardGradient),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.photo_camera_outlined,
                size: 20,
                color: SwarnimColors.metaOnLight,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: SwarnimColors.metaOnLight,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = SwarnimColors.borderLight
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(SwarnimRadius.control),
    );

    // Walk the rounded rect and draw alternating 6px on / 4px off segments.
    for (final metric in (Path()..addRRect(rect)).computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, (distance + 6).clamp(0, metric.length)),
          paint,
        );
        distance += 10;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Circular initials avatar in navy with gold letters.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar(this.initials, {super.key, this.size = 72});

  final String initials;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        gradient: SwarnimColors.avatarGradient,
        shape: BoxShape.circle,
      ),
      child: Text(
        initials,
        style: GoogleFonts.poppins(
          fontSize: size / 3,
          fontWeight: FontWeight.w700,
          color: SwarnimColors.gold,
        ),
      ),
    );
  }
}
