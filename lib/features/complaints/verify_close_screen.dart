import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/api_client.dart';
import '../../core/complaints.dart';

/// Screen 05 — the customer's side of the closure control.
///
/// NOTE ON THE DESIGN. The approved mockup shows the customer *typing* a code
/// into four boxes, which implies they received it by SMS. The flow the client
/// actually described is the opposite: the engineer requests a code, it reaches
/// the customer, and the customer **reads it out** for the engineer to enter.
/// This screen implements the described flow — it *shows* the code — because
/// that is the control that was agreed. Raised for confirmation.
class VerifyCloseScreen extends ConsumerStatefulWidget {
  const VerifyCloseScreen({super.key, required this.complaintId});

  final String complaintId;

  @override
  ConsumerState<VerifyCloseScreen> createState() => _VerifyCloseScreenState();
}

class _VerifyCloseScreenState extends ConsumerState<VerifyCloseScreen> {
  ClosureCode? _code;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });

    try {
      final code = await ref.read(complaintRepositoryProvider).pendingClosureCode(widget.complaintId);
      if (mounted) setState(() { _code = code; _loading = false; });
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    }
  }

  Future<void> _reject() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => const _RejectDialog(),
    );

    if (reason == null || !mounted) return;

    setState(() => _busy = true);

    try {
      await ref.read(complaintRepositoryProvider).rejectClosure(widget.complaintId, reason);
      ref.invalidate(myComplaintsProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reported. The site team will come back to it.')),
      );
      context.pop();
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _busy = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SwarnimScreen(
      title: 'Verify & Close',
      subtitle: _code == null ? null : '${_code!.complaintTitle} • ${_code!.complaintNumber}',
      leading: _BackButton(onTap: () => context.pop()),
      child: _loading
          ? const Padding(
              padding: EdgeInsets.only(top: 72),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          : _code == null
              ? _NothingPending(error: _error, onRetry: _load)
              : _CodeBody(code: _code!, busy: _busy, onReject: _reject),
    );
  }
}

class _CodeBody extends StatelessWidget {
  const _CodeBody({required this.code, required this.busy, required this.onReject});

  final ClosureCode code;
  final bool busy;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final minutes = code.expiresAt.difference(DateTime.now()).inMinutes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwarnimCard(
          accent: SwarnimColors.goldSoft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Work marked complete', style: SwarnimTheme.cardTitle),
              const SizedBox(height: 4),
              Text(
                '${code.engineerName} has finished and is asking you to confirm.',
                style: SwarnimTheme.cardMeta,
              ),
              if (code.workSummary != null && code.workSummary!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('“${code.workSummary}”', style: SwarnimTheme.cardMeta),
              ],
            ],
          ),
        ),

        const FieldLabel('Read this code to the engineer', topGap: 8),

        // The whole control in one widget: the customer holds the code, so
        // nothing closes without them.
        Container(
          padding: const EdgeInsets.symmetric(vertical: 22),
          decoration: BoxDecoration(
            color: SwarnimColors.navy,
            borderRadius: BorderRadius.circular(SwarnimRadius.control),
            border: Border.all(color: SwarnimColors.gold, width: 1.5),
          ),
          child: Column(
            children: [
              Text(
                code.code.split('').join('  '),
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 44,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 6,
                  color: SwarnimColors.gold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                minutes <= 0 ? 'Expired — ask for a new code' : 'Expires in $minutes minute(s)',
                style: GoogleFonts.poppins(
                    fontSize: 11.5, color: SwarnimColors.metaOnDark),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: SwarnimColors.goldSoft.withValues(alpha: 0.14),
            border: const Border(
                left: BorderSide(color: SwarnimColors.goldSoft, width: 3)),
            borderRadius: BorderRadius.circular(SwarnimRadius.control),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, size: 18, color: SwarnimColors.goldSoft),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Only share this code if the work is actually finished. '
                  'Giving it to the engineer closes your complaint.',
                  style: GoogleFonts.poppins(
                      fontSize: 12, height: 1.45, color: SwarnimColors.inkOnLight),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),
        SecondaryButton(
          label: busy ? 'Reporting…' : 'The work is not done',
          icon: Icons.report_gmailerrorred_outlined,
          onPressed: busy ? null : onReject,
        ),
        const SizedBox(height: 10),
        Text(
          'Reporting this reopens the complaint and the site team will return.',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(fontSize: 11.5, color: SwarnimColors.metaOnLight),
        ),
      ],
    );
  }
}

class _NothingPending extends StatelessWidget {
  const _NothingPending({this.error, required this.onRetry});

  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 56),
      child: Column(
        children: [
          const Icon(Icons.verified_outlined, size: 44, color: SwarnimColors.borderLight),
          const SizedBox(height: 14),
          Text(
            error ?? 'Nothing to confirm right now',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: SwarnimColors.inkOnLight,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'A code appears here once the engineer marks the work complete.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 12.5, color: SwarnimColors.metaOnLight),
          ),
          const SizedBox(height: 20),
          SecondaryButton(label: 'Check again', onPressed: onRetry),
        ],
      ),
    );
  }
}

class _RejectDialog extends StatefulWidget {
  const _RejectDialog();

  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      title: Text('What is still wrong?', style: SwarnimTheme.cardTitle),
      content: TextField(
        controller: _controller,
        maxLines: 3,
        maxLength: 300,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'The tap still drips…'),
        style: GoogleFonts.poppins(fontSize: 13, color: SwarnimColors.inkOnLight),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel',
              style: GoogleFonts.poppins(color: SwarnimColors.metaOnLight)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: Text('Report',
              style: GoogleFonts.poppins(
                  color: SwarnimColors.statusOpen, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
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
