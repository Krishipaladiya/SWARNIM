import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../core/api_client.dart';

/// One piece of evidence, named the same way whoever is looking at it.
///
/// The staff screen and the customer screen each had their own attachment
/// type, so the viewer takes this instead of either - a thumbnail strip should
/// not care which app surface it is drawn on.
class MediaItem {
  const MediaItem({required this.path, required this.isVideo, this.caption});

  /// The authenticated API path, e.g. "/api/v1/files/{id}".
  final String path;

  final bool isVideo;
  final String? caption;
}

/// Opens the evidence full screen, starting at the one that was tapped.
///
/// WHY THIS EXISTS
///
/// The thumbnails had no tap handler at all. An engineer could see that a
/// customer had photographed a leak and could not look at it - which is the
/// one thing the photograph is for, since a 104-pixel tile shows that there is
/// a picture and nothing about what is in it.
Future<void> showMediaViewer(
  BuildContext context,
  WidgetRef ref, {
  required List<MediaItem> items,
  int initialIndex = 0,
}) async {
  if (items.isEmpty) return;

  await Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => _MediaViewer(items: items, initialIndex: initialIndex),
    ),
  );
}

class _MediaViewer extends ConsumerStatefulWidget {
  const _MediaViewer({required this.items, required this.initialIndex});

  final List<MediaItem> items;
  final int initialIndex;

  @override
  ConsumerState<_MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends ConsumerState<_MediaViewer> {
  late final PageController _pages =
      PageController(initialPage: widget.initialIndex);

  late int _index = widget.initialIndex;
  bool _busy = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  /// Downloads the file and hands it to whatever the phone uses to open it.
  ///
  /// This is how video is handled at all. Phone video arrives as .mov, which
  /// Android cannot decode, so an inline player would be a black rectangle
  /// with dead controls. The device's own player can open it, but only from a
  /// file - the URL needs a bearer token no external app has.
  ///
  /// It doubles as "save this" for photographs, which is what an engineer
  /// wants when they are about to send one on.
  Future<void> _openExternally(MediaItem item) async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final bytes = await _fetch(item.path);

      // The cache directory, not documents: this is a copy for the phone's
      // viewer to open, not something the customer should find later in their
      // files.
      final dir = await getTemporaryDirectory();
      final name = item.path.split('/').last;
      final file = File('${dir.path}/$name${item.isVideo ? '.mp4' : '.jpg'}');

      await file.writeAsBytes(bytes);
      await OpenFilex.open(file.path);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open that file.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Uint8List> _fetch(String path) async {
    final response = await ref.read(dioProvider).get<List<int>>(
          path,
          options: Options(responseType: ResponseType.bytes),
        );

    return Uint8List.fromList(response.data!);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.items[_index];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.items.length == 1
              ? (item.caption ?? 'Photo')
              : '${_index + 1} of ${widget.items.length}',
          style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        actions: [
          IconButton(
            tooltip: item.isVideo ? 'Play' : 'Open',
            onPressed: _busy ? null : () => _openExternally(item),
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.open_in_new),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pages,
        itemCount: widget.items.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) {
          final m = widget.items[i];

          if (m.isVideo) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.play_circle_outline,
                      size: 72, color: Colors.white70),
                  const SizedBox(height: 12),
                  Text(
                    'Tap open to play this video',
                    style: GoogleFonts.poppins(
                        fontSize: 13, color: Colors.white70),
                  ),
                ],
              ),
            );
          }

          return FutureBuilder<Uint8List>(
            future: _fetch(m.path),
            builder: (context, snap) {
              if (snap.hasError) {
                return const Center(
                  child: Icon(Icons.broken_image_outlined,
                      color: Colors.white54, size: 48),
                );
              }

              if (!snap.hasData) {
                return const Center(
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                );
              }

              // Pinch to zoom. The reason an engineer opens this at all is
              // usually to read something small - a meter reading, a crack,
              // a model number on a fitting.
              return InteractiveViewer(
                maxScale: 5,
                child: Center(child: Image.memory(snap.data!)),
              );
            },
          );
        },
      ),
    );
  }
}
