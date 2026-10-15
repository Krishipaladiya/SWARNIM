import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/api_client.dart';
import '../../core/staff.dart';
import 'staff_widgets.dart';

/// Records what happened on site. Returns true when something was saved.
Future<bool?> showStaffUpdateSheet(
  BuildContext context, {
  required String complaintId,
}) =>
    showSwarnimSheet<bool>(
      context,
      builder: (_) => _UpdateSheet(complaintId: complaintId),
    );

class _UpdateSheet extends ConsumerStatefulWidget {
  const _UpdateSheet({required this.complaintId});

  final String complaintId;

  @override
  ConsumerState<_UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends ConsumerState<_UpdateSheet> {
  final _note = TextEditingController();
  final _parts = TextEditingController();

  /// Off by default, and that default is load-bearing. Notes get written for
  /// colleagues - "tenant was hostile", "quote is inflated" - and a box that
  /// starts ticked publishes them to the customer the first time someone is in
  /// a hurry. Sharing is the deliberate act, not the accident.
  bool _visible = false;

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    _parts.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    // No status is sent any more, so an update with nothing written in it
    // would record nothing at all - the server refuses it, and this says so
    // without a round trip.
    if (_note.text.trim().isEmpty && _parts.text.trim().isEmpty) {
      setState(() => _error = 'Write what you found, or what you used.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(staffRepositoryProvider).addUpdate(
            widget.complaintId,
            note: _note.text,
            partsUsed: _parts.text,
            visibleToCustomer: _visible,
          );
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Keyboard and gesture-bar insets come from showSwarnimSheet.
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Work update', style: SwarnimTheme.cardTitle),
              const SizedBox(height: 16),

              // No status picker.
              //
              // Picking a job up now starts it, and finishing it happens on
              // the closure screen - so by the time anyone opens this sheet
              // the status is already In progress and there is nothing left
              // to choose. What is worth recording here is what was found
              // and what was used.

              Text('NOTE', style: SwarnimTheme.fieldLabel),
              const SizedBox(height: 8),
              _Field(controller: _note, hint: 'What did you find or do?', lines: 3),

              const SizedBox(height: 16),
              Text('PARTS USED', style: SwarnimTheme.fieldLabel),
              const SizedBox(height: 8),
              _Field(controller: _parts, hint: 'e.g. Mixer cartridge x1', lines: 1),

              const SizedBox(height: 16),
              InkWell(
                onTap: () => setState(() => _visible = !_visible),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Checkbox(
                        value: _visible,
                        onChanged: (v) => setState(() => _visible = v ?? false),
                        activeColor: SwarnimColors.navy,
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Show this to the customer',
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: SwarnimColors.inkOnLight,
                                )),
                            Text(
                              _visible
                                  ? 'They will see this note in their app.'
                                  : 'Internal only - the customer will not see this.',
                              style: GoogleFonts.poppins(
                                  fontSize: 11.5, color: SwarnimColors.metaOnLight),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: SwarnimColors.statusOpen)),
              ],

              const SizedBox(height: 20),
              PrimaryButton(
                label: 'Save update',
                icon: Icons.check,
                busy: _busy,
                onPressed: _busy ? null : _save,
              ),
            ],
          ),
        ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.controller, required this.hint, required this.lines});

  final TextEditingController controller;
  final String hint;
  final int lines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: lines,
      style: GoogleFonts.poppins(fontSize: 13.5, color: SwarnimColors.inkOnLight),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.poppins(fontSize: 13, color: SwarnimColors.metaOnLight),
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
    );
  }
}
