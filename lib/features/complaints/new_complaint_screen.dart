import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/api_client.dart';
import '../../core/complaints.dart';

/// Screen 03 of the mockup, wired to the API.
class NewComplaintScreen extends ConsumerStatefulWidget {
  const NewComplaintScreen({super.key});

  @override
  ConsumerState<NewComplaintScreen> createState() => _NewComplaintScreenState();
}

class _NewComplaintScreenState extends ConsumerState<NewComplaintScreen> {
  static const _priorities = [(1, 'Low'), (2, 'Medium'), (3, 'High')];
  static const _maxAttachments = 8;

  final _location = TextEditingController();
  final _description = TextEditingController();
  final _picker = ImagePicker();

  int? _categoryId;
  int _priority = 2;
  final List<PendingAttachment> _attachments = [];

  bool _busy = false;
  String? _error;
  String? _progress;

  @override
  void dispose() {
    _location.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _addMedia() async {
    if (_attachments.length >= _maxAttachments) return;

    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            _sheetTile(context, Icons.photo_camera_outlined, 'Take a photo', 'camera'),
            _sheetTile(context, Icons.videocam_outlined, 'Record a video', 'video'),
            _sheetTile(context, Icons.photo_library_outlined, 'Choose from gallery', 'gallery'),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (choice == null || !mounted) return;

    try {
      final XFile? picked = switch (choice) {
        // Resized on the device: a modern phone camera produces 8-12 MB files,
        // and uploading that over a site connection is slow for no benefit.
        'camera' => await _picker.pickImage(
            source: ImageSource.camera,
            maxWidth: 1920,
            imageQuality: 82,
          ),
        'gallery' => await _picker.pickMedia(maxWidth: 1920, imageQuality: 82),
        'video' => await _picker.pickVideo(
            source: ImageSource.camera,
            maxDuration: const Duration(seconds: 60),
          ),
        _ => null,
      };

      if (picked == null || !mounted) return;

      final path = picked.path.toLowerCase();
      final isVideo = choice == 'video' ||
          path.endsWith('.mp4') ||
          path.endsWith('.mov') ||
          path.endsWith('.3gp');

      setState(() {
        _attachments.add(PendingAttachment(file: File(picked.path), isVideo: isVideo));
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not open the camera or gallery.');
    }
  }

  Widget _sheetTile(BuildContext context, IconData icon, String label, String value) => ListTile(
        leading: Icon(icon, color: SwarnimColors.navy),
        title: Text(label, style: SwarnimTheme.cardTitle),
        onTap: () => Navigator.pop(context, value),
      );

  Future<void> _submit() async {
    if (_categoryId == null) {
      setState(() => _error = 'Choose a category.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _progress = _attachments.isEmpty ? null : 'Uploading 0 of ${_attachments.length}…';
    });

    try {
      final result = await ref.read(complaintRepositoryProvider).create(
            categoryId: _categoryId!,
            location: _location.text.trim().isEmpty ? null : _location.text.trim(),
            description: _description.text.trim().isEmpty ? null : _description.text.trim(),
            priority: _priority,
            attachments: _attachments,
            onProgress: (done, total) {
              if (mounted) setState(() => _progress = 'Uploading $done of $total…');
            },
          );

      // The list is stale the moment a complaint is filed.
      ref.invalidate(myComplaintsProvider);

      if (!mounted) return;

      final message = result.failures.isEmpty
          ? 'Complaint ${result.complaint.number} filed.'
          : 'Complaint ${result.complaint.number} filed, but '
              '${result.failures.length} attachment(s) could not be uploaded.';

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      context.pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() { _busy = false; _progress = null; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(complaintCategoriesProvider);

    return SwarnimScreen(
      title: 'New Complaint',
      subtitle: 'SWH-A-1203',
      leading: _BackButton(onTap: () => context.pop()),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FieldLabel('Category'),
          categories.when(
            loading: () => const _FieldPlaceholder('Loading categories…'),
            error: (_, _) => const _FieldPlaceholder('Categories unavailable'),
            data: (items) => DropdownButtonFormField<int>(
              initialValue: _categoryId,
              hint: const Text('Choose a category'),
              items: [
                for (final c in items)
                  DropdownMenuItem(value: c.id, child: Text(c.name)),
              ],
              onChanged: _busy ? null : (v) => setState(() => _categoryId = v),
              style: GoogleFonts.poppins(fontSize: 13, color: SwarnimColors.inkOnLight),
              dropdownColor: Colors.white,
            ),
          ),

          const FieldLabel('Location', topGap: 16),
          TextField(
            controller: _location,
            enabled: !_busy,
            decoration: const InputDecoration(hintText: 'Kitchen'),
            style: GoogleFonts.poppins(fontSize: 13, color: SwarnimColors.inkOnLight),
          ),

          const FieldLabel('Description', topGap: 16),
          TextField(
            controller: _description,
            enabled: !_busy,
            maxLines: 4,
            maxLength: 2000,
            decoration: const InputDecoration(hintText: 'Describe the issue...'),
            style: GoogleFonts.poppins(fontSize: 13, color: SwarnimColors.inkOnLight),
          ),

          FieldLabel('Evidence  (${_attachments.length}/$_maxAttachments)'),
          _MediaPicker(
            attachments: _attachments,
            enabled: !_busy && _attachments.length < _maxAttachments,
            onAdd: _addMedia,
            onRemove: (i) => setState(() => _attachments.removeAt(i)),
          ),

          const FieldLabel('Priority', topGap: 16),
          Row(
            children: [
              for (final (value, label) in _priorities) ...[
                Expanded(
                  child: SecondaryButton(
                    label: label,
                    selected: _priority == value,
                    onPressed: _busy ? null : () => setState(() => _priority = value),
                  ),
                ),
                if (value != 3) const SizedBox(width: 8),
              ],
            ],
          ),

          if (_error != null) ...[
            const SizedBox(height: 16),
            _ErrorBanner(_error!),
          ],

          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: SwarnimColors.buttonPrimaryText),
                      ),
                      const SizedBox(width: 10),
                      Text(_progress ?? 'Submitting…'),
                    ],
                  )
                : const Text('Submit Complaint'),
          ),
        ],
      ),
    );
  }
}

class _MediaPicker extends StatelessWidget {
  const _MediaPicker({
    required this.attachments,
    required this.enabled,
    required this.onAdd,
    required this.onRemove,
  });

  final List<PendingAttachment> attachments;
  final bool enabled;
  final VoidCallback onAdd;
  final void Function(int index) onRemove;

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) {
      return UploadBox(onTap: enabled ? onAdd : null);
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < attachments.length; i++)
          _Thumb(attachment: attachments[i], onRemove: () => onRemove(i)),
        if (enabled)
          InkWell(
            onTap: onAdd,
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                border: Border.all(color: SwarnimColors.borderLight),
                borderRadius: BorderRadius.circular(SwarnimRadius.control),
                gradient: SwarnimColors.cardGradient,
              ),
              child: const Icon(Icons.add, color: SwarnimColors.metaOnLight),
            ),
          ),
      ],
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.attachment, required this.onRemove});

  final PendingAttachment attachment;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 76,
      height: 76,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(SwarnimRadius.control),
            child: attachment.isVideo
                // No thumbnail for video without a decoder package - a labelled
                // tile is clearer than a broken image box.
                ? Container(
                    color: SwarnimColors.navyMid,
                    child: const Center(
                      child: Icon(Icons.videocam, color: Colors.white70, size: 26),
                    ),
                  )
                : Image.file(attachment.file, fit: BoxFit.cover),
          ),
          Positioned(
            top: -6,
            right: -6,
            child: IconButton(
              iconSize: 18,
              icon: const CircleAvatar(
                radius: 11,
                backgroundColor: Colors.black54,
                child: Icon(Icons.close, size: 13, color: Colors.white),
              ),
              onPressed: onRemove,
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldPlaceholder extends StatelessWidget {
  const _FieldPlaceholder(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        height: 44,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: SwarnimColors.borderLight),
          borderRadius: BorderRadius.circular(SwarnimRadius.control),
        ),
        child: Text(text,
            style: GoogleFonts.poppins(fontSize: 13, color: SwarnimColors.metaOnLight)),
      );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: SwarnimColors.statusOpen.withValues(alpha: 0.08),
          border: const Border(
              left: BorderSide(color: SwarnimColors.statusOpen, width: 3)),
          borderRadius: BorderRadius.circular(SwarnimRadius.control),
        ),
        child: Text(message,
            style: GoogleFonts.poppins(fontSize: 12, color: SwarnimColors.inkOnLight)),
      );
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkResponse(
        onTap: onTap,
        radius: 24,
        child: const SizedBox(
          width: 32,
          height: 40,
          child: Icon(Icons.arrow_back, size: 22, color: SwarnimColors.inkOnDark),
        ),
      );
}
