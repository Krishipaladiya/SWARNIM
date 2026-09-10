import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme.dart';
import '../../core/api_client.dart';
import '../../core/staff.dart';
import 'staff_widgets.dart';

/// Records what happened on site. Returns true when something was saved.
Future<bool?> showStaffUpdateSheet(
  BuildContext context, {
  required String complaintId,
  required List<WorkStatus> nextStatuses,
}) =>
    showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      builder: (_) => _UpdateSheet(complaintId: complaintId, nextStatuses: nextStatuses),
    );

class _UpdateSheet extends ConsumerStatefulWidget {
  const _UpdateSheet({required this.complaintId, required this.nextStatuses});

  final String complaintId;
  final List<WorkStatus> nextStatuses;

  @override
  ConsumerState<_UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends ConsumerState<_UpdateSheet> {
  final _note = TextEditingController();
  final _parts = TextEditingController();

  WorkStatus? _status;

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
    if (_status == null && _note.text.trim().isEmpty && _parts.text.trim().isEmpty) {
      setState(() => _error = 'Add a note or change the status.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(staffRepositoryProvider).addUpdate(
            widget.complaintId,
            status: _status,
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
    return Padding(
      // Keeps the note field above the keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Work update', style: SwarnimTheme.cardTitle),
              const SizedBox(height: 16),

              if (widget.nextStatuses.isNotEmpty) ...[
                Text('MOVE TO', style: SwarnimTheme.fieldLabel),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in widget.nextStatuses)
                      _StatusChip(
                        status: s,
                        selected: _status == s,
                        // Tapping the selected one clears it, so an update can
                        // be a note alone without leaving the sheet.
                        onTap: () => setState(() => _status = _status == s ? null : s),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
              ],

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
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.selected, required this.onTap});

  final WorkStatus status;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? SwarnimColors.navy : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? SwarnimColors.navy : SwarnimColors.borderLight),
        ),
        child: Text(
          status.label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? SwarnimColors.inkOnDark : SwarnimColors.metaOnLight,
          ),
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
