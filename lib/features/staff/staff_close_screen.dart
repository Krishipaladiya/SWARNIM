import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/api_client.dart';
import '../../core/staff.dart';
import 'staff_widgets.dart';

/// The engineer's half of the closure control.
///
/// The code is never shown here and never sent to this device - it goes to the
/// customer's app, and the only way it reaches this screen is the customer
/// reading it out. That asymmetry is the entire control: if the engineer's app
/// could display the code, a closure would prove nothing.
class StaffCloseScreen extends ConsumerStatefulWidget {
  const StaffCloseScreen({super.key, required this.complaintId});

  final String complaintId;

  @override
  ConsumerState<StaffCloseScreen> createState() => _StaffCloseScreenState();
}

class _StaffCloseScreenState extends ConsumerState<StaffCloseScreen> {
  final _code = TextEditingController();

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    final code = _code.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Ask the customer to read out the code.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final message =
          await ref.read(staffRepositoryProvider).closeWithCode(widget.complaintId, code);

      ref.invalidate(staffComplaintProvider(widget.complaintId));
      ref.invalidate(staffQueueProvider);
      ref.invalidate(staffCountsProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message.isEmpty ? 'Complaint closed.' : message,
            style: GoogleFonts.poppins(fontSize: 12.5)),
        backgroundColor: SwarnimColors.navy,
        behavior: SnackBarBehavior.floating,
      ));
      context.pop();
    } on ApiException catch (e) {
      // The server counts attempts and says how many are left. Surfacing its
      // wording verbatim keeps the app from having to track that itself.
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(staffRepositoryProvider).requestClosureCode(widget.complaintId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('A fresh code is on the customer\'s app.',
            style: GoogleFonts.poppins(fontSize: 12.5)),
        backgroundColor: SwarnimColors.navy,
        behavior: SnackBarBehavior.floating,
      ));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(staffComplaintProvider(widget.complaintId));

    return SwarnimScreen(
      title: 'Close complaint',
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
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: SwarnimColors.cardGradient,
              borderRadius: BorderRadius.circular(SwarnimRadius.control),
              border: const Border(left: BorderSide(color: SwarnimColors.gold, width: 4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ask the customer', style: SwarnimTheme.cardTitle),
                const SizedBox(height: 6),
                Text(
                  'A code is showing on their Swarnim Connect app. Ask them to read it '
                  'out, then type it below. They can also refuse, which sends the '
                  'complaint back to you.',
                  style: GoogleFonts.poppins(
                      fontSize: 12.5, height: 1.5, color: SwarnimColors.inkOnLight),
                ),
              ],
            ),
          ),

          const FieldLabel('Code from the customer', topGap: 24),
          TextField(
            controller: _code,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            autofocus: true,
            style: GoogleFonts.poppins(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: 10,
              color: SwarnimColors.inkOnLight,
            ),
            decoration: InputDecoration(
              hintText: '••••',
              hintStyle: GoogleFonts.poppins(
                fontSize: 26,
                letterSpacing: 10,
                color: SwarnimColors.borderLight,
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
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
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 12.5, color: SwarnimColors.statusOpen)),
          ],

          const SizedBox(height: 20),
          PrimaryButton(
            label: 'Close complaint',
            icon: Icons.check_circle_outline,
            busy: _busy,
            onPressed: _busy ? null : _close,
          ),
          const SizedBox(height: 10),
          SecondaryButton(
            label: 'Send a fresh code',
            icon: Icons.refresh,
            onPressed: _busy ? null : _resend,
          ),

          const SizedBox(height: 24),
          Text(
            'If the customer is not there, a supervisor can close it without a code. '
            'That is recorded separately and reviewed.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
                fontSize: 11.5, height: 1.4, color: SwarnimColors.metaOnLight),
          ),
        ],
      ),
    );
  }
}
