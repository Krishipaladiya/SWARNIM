import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/api_client.dart';
import '../../core/staff.dart';
import 'staff_widgets.dart';

/// Proof of work, then the request for the customer's code.
///
/// The photo is not decoration. A closure that rests on the customer reading
/// out a code still needs something on the record showing the work was actually
/// done - otherwise "the customer confirmed it" is the only evidence, and that
/// is exactly the thing a rushed engineer can talk someone into. The server
/// enforces this; this screen exists so the engineer meets the requirement
/// before being refused rather than after.
class StaffFinishScreen extends ConsumerStatefulWidget {
  const StaffFinishScreen({super.key, required this.complaintId});

  final String complaintId;

  @override
  ConsumerState<StaffFinishScreen> createState() => _StaffFinishScreenState();
}

class _StaffFinishScreenState extends ConsumerState<StaffFinishScreen> {
  final _picker = ImagePicker();
  final _summary = TextEditingController();

  XFile? _photo;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _summary.dispose();
    super.dispose();
  }

  Future<void> _take({required bool fromCamera}) async {
    final shot = await _picker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      // Full-resolution phone photos are 8-12 MB and add nothing here; the
      // point is a recognisable picture of the finished work.
      maxWidth: 1920,
      imageQuality: 82,
    );

    if (shot != null && mounted) {
      setState(() {
        _photo = shot;
        _error = null;
      });
    }
  }

  Future<void> _submit() async {
    if (_photo == null) {
      setState(() => _error = 'Take a photo of the finished work first.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final repo = ref.read(staffRepositoryProvider);

      // Where the engineer is standing when they ask for the code. The server
      // compares it to the project's own position - an engineer phoning the
      // customer from home to ask for the code leaves a 40-kilometre gap on
      // the record. Refused up front rather than after the upload, so a denied
      // permission does not cost the customer a wasted code.
      final position = await _position();

      // Upload first: the file id is what the closure request is validated
      // against, so a failed upload must stop here rather than leaving a code
      // issued with no evidence behind it.
      final fileId = await repo.uploadPhoto(
        widget.complaintId,
        _photo!.path,
        caption: 'Work completed',
      );

      await repo.requestClosureCode(
        widget.complaintId,
        workSummary: _summary.text,
        proofFileId: fileId,
        latitude: position.latitude,
        longitude: position.longitude,
      );

      ref.invalidate(staffComplaintProvider(widget.complaintId));
      ref.invalidate(staffQueueProvider);

      if (!mounted) return;
      context.pushReplacement('/staff/complaints/${widget.complaintId}/close');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The engineer's current position, or a message explaining why not.
  ///
  /// Every failure is thrown as an [ApiException] so the screen has one error
  /// path: the person reading it does not care whether the service was off or
  /// the permission was denied, only what to do about it.
  Future<Position> _position() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const ApiException('Turn on location, then try again.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      throw const ApiException(
          'Location is blocked for this app. Allow it in Settings, then try again.');
    }

    if (permission == LocationPermission.denied) {
      throw const ApiException('Location is needed to confirm you are on site.');
    }

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          // A fix can take a while inside a concrete building. Better to wait
          // than to send a stale position from the last site visited.
          timeLimit: Duration(seconds: 20),
        ),
      );
    } on Exception {
      throw const ApiException(
          'Could not get a location fix. Step outside or near a window and try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(staffComplaintProvider(widget.complaintId));

    return SwarnimScreen(
      title: 'Finish the job',
      subtitle: detail.maybeWhen(data: (d) => d.row.number, orElse: () => null),
      leading: InkResponse(
        onTap: () => context.pop(),
        radius: 24,
        child: const SizedBox(
          width: 32,
          height: 40,
          child: Icon(Icons.arrow_back, size: 22, color: SwarnimColors.inkOnDark),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FieldLabel('Photo of the finished work'),

          if (_photo == null)
            UploadBox(
              onTap: () => _take(fromCamera: true),
              label: 'Take a photo of the finished work',
            )
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(SwarnimRadius.image),
              child: Stack(
                children: [
                  Image.file(File(_photo!.path),
                      height: 200, width: double.infinity, fit: BoxFit.cover),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Material(
                      color: SwarnimColors.navy.withValues(alpha: 0.75),
                      shape: const CircleBorder(),
                      child: InkResponse(
                        onTap: () => setState(() => _photo = null),
                        radius: 20,
                        child: const Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(Icons.close, size: 18, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          if (_photo == null) ...[
            const SizedBox(height: 8),
            SecondaryButton(
              label: 'Choose from gallery',
              icon: Icons.photo_library_outlined,
              onPressed: _busy ? null : () => _take(fromCamera: false),
            ),
          ],

          const FieldLabel('What did you do?', topGap: 20),
          TextField(
            controller: _summary,
            maxLines: 3,
            style: GoogleFonts.poppins(fontSize: 13.5, color: SwarnimColors.inkOnLight),
            decoration: InputDecoration(
              hintText: 'The customer sees this alongside the code',
              hintStyle: GoogleFonts.poppins(fontSize: 13, color: SwarnimColors.metaOnLight),
              filled: true,
              fillColor: Colors.white,
              isDense: true,
              contentPadding: const EdgeInsets.all(12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(SwarnimRadius.control),
                borderSide: const BorderSide(color: SwarnimColors.borderLight),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(SwarnimRadius.control),
                borderSide: const BorderSide(color: SwarnimColors.borderLight),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(SwarnimRadius.control),
                borderSide: const BorderSide(color: SwarnimColors.gold, width: 1.5),
              ),
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                style: GoogleFonts.poppins(fontSize: 12.5, color: SwarnimColors.statusOpen)),
          ],

          const SizedBox(height: 20),
          PrimaryButton(
            label: 'Send the code to the customer',
            icon: Icons.send_outlined,
            busy: _busy,
            onPressed: _busy ? null : _submit,
          ),

          const SizedBox(height: 14),
          Text(
            'The code goes to the customer\'s app, not yours. Ask them to read it out.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
                fontSize: 11.5, height: 1.4, color: SwarnimColors.metaOnLight),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
