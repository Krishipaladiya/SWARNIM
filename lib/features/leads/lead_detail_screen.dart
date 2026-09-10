import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/api_client.dart';
import '../../core/leads.dart';
import '../staff/staff_widgets.dart';
import 'leads_screen.dart';

/// One enquiry, and every conversation had with them.
class LeadDetailScreen extends ConsumerWidget {
  const LeadDetailScreen({super.key, required this.leadId});

  final String leadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(leadDetailProvider(leadId));

    return detail.when(
      loading: () => SwarnimScreen(
        title: 'Lead',
        leading: _Back(onTap: () => context.pop()),
        child: StaffAsyncBody.loading(),
      ),
      error: (e, _) => SwarnimScreen(
        title: 'Lead',
        leading: _Back(onTap: () => context.pop()),
        child: StaffAsyncBody.error(e, () => ref.invalidate(leadDetailProvider(leadId))),
      ),
      data: (d) => SwarnimScreen(
        title: d.lead.fullName,
        subtitle: '${d.lead.number}${d.lead.city == null ? "" : " · ${d.lead.city}"}',
        leading: _Back(onTap: () => context.pop()),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwarnimCard(
              accent: d.lead.isOverdue ? SwarnimColors.statusOpen : SwarnimColors.gold,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      LeadStatusPill(d.lead.status),
                      const Spacer(),
                      Text(d.lead.mobile,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: SwarnimColors.inkOnLight,
                          )),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _Row('Interested in', d.lead.unitType ?? '—'),
                  if (d.budgetMax != null)
                    _Row('Budget', 'up to ${NumberFormat.decimalPattern('en_IN').format(d.budgetMax)}'),
                  _Row('Owner', d.lead.owner ?? 'Unassigned'),
                  _Row(
                    'Next follow-up',
                    d.lead.nextFollowUpOn == null
                        ? 'Not set'
                        : DateFormat('d MMM yyyy').format(d.lead.nextFollowUpOn!),
                  ),
                ],
              ),
            ),

            if (d.notes != null && d.notes!.isNotEmpty) ...[
              const FieldLabel('Notes', topGap: 8),
              Text(d.notes!,
                  style: GoogleFonts.poppins(
                      fontSize: 13, height: 1.5, color: SwarnimColors.inkOnLight)),
            ],

            if (d.lead.status == LeadStatus.lost && d.lostReason != null) ...[
              const FieldLabel('Why it was lost', topGap: 16),
              Text(d.lostReason!,
                  style: GoogleFonts.poppins(
                      fontSize: 13, height: 1.5, color: SwarnimColors.inkOnLight)),
            ],

            if (d.lead.isOpen) ...[
              const SizedBox(height: 20),
              PrimaryButton(
                label: 'Record a conversation',
                icon: Icons.add_comment_outlined,
                onPressed: () async {
                  final saved = await showFollowUpSheet(context, leadId: leadId, current: d.lead.status);
                  if (saved == true) {
                    ref.invalidate(leadDetailProvider(leadId));
                    ref.invalidate(leadsProvider);
                    ref.invalidate(leadCountsProvider);
                  }
                },
              ),
            ],

            FieldLabel('Conversations (${d.followUps.length})', topGap: 22),
            if (d.followUps.isEmpty)
              Text('Nothing recorded yet.', style: SwarnimTheme.cardMeta)
            else
              for (final f in d.followUps) _FollowUpCard(followUp: f),

            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }
}

/// One exchange. The customer's words get their own block and their own colour
/// so they read as a quotation rather than as more of the salesperson's note.
class _FollowUpCard extends StatelessWidget {
  const _FollowUpCard({required this.followUp});

  final LeadFollowUp followUp;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: SwarnimColors.cardGradient,
        borderRadius: BorderRadius.circular(SwarnimRadius.control),
        border: Border.all(color: SwarnimColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_icon(followUp.channel), size: 15, color: SwarnimColors.metaOnLight),
              const SizedBox(width: 6),
              Text(followUp.channel.label,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: SwarnimColors.inkOnLight,
                  )),
              const Spacer(),
              if (followUp.statusAfter != null) LeadStatusPill(followUp.statusAfter!),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            '${DateFormat('d MMM, HH:mm').format(followUp.contactedAt.toLocal())} · ${followUp.by}',
            style: GoogleFonts.poppins(fontSize: 11, color: SwarnimColors.metaOnLight),
          ),

          if (followUp.staffNote != null && followUp.staffNote!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('WE SAID', style: SwarnimTheme.fieldLabel),
            const SizedBox(height: 3),
            Text(followUp.staffNote!,
                style: GoogleFonts.poppins(
                    fontSize: 12.5, height: 1.45, color: SwarnimColors.inkOnLight)),
          ],

          if (followUp.customerAnswer != null && followUp.customerAnswer!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              decoration: BoxDecoration(
                color: SwarnimColors.goldSoft.withValues(alpha: 0.12),
                border: const Border(left: BorderSide(color: SwarnimColors.goldSoft, width: 3)),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('THEY SAID', style: SwarnimTheme.fieldLabel),
                  const SizedBox(height: 3),
                  Text(followUp.customerAnswer!,
                      style: GoogleFonts.poppins(
                          fontSize: 12.5, height: 1.45, color: SwarnimColors.inkOnLight)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  static IconData _icon(FollowUpChannel c) => switch (c) {
        FollowUpChannel.call => Icons.phone_outlined,
        FollowUpChannel.whatsApp => Icons.chat_outlined,
        FollowUpChannel.siteVisit => Icons.location_on_outlined,
        FollowUpChannel.meeting => Icons.groups_outlined,
        FollowUpChannel.email => Icons.mail_outline,
        FollowUpChannel.note => Icons.sticky_note_2_outlined,
      };
}

// ------------------------------------------------------------ follow-up sheet

Future<bool?> showFollowUpSheet(
  BuildContext context, {
  required String leadId,
  required LeadStatus current,
}) =>
    showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      builder: (_) => _FollowUpSheet(leadId: leadId, current: current),
    );

class _FollowUpSheet extends ConsumerStatefulWidget {
  const _FollowUpSheet({required this.leadId, required this.current});

  final String leadId;
  final LeadStatus current;

  @override
  ConsumerState<_FollowUpSheet> createState() => _FollowUpSheetState();
}

class _FollowUpSheetState extends ConsumerState<_FollowUpSheet> {
  final _staffNote = TextEditingController();
  final _customerAnswer = TextEditingController();
  final _lostReason = TextEditingController();

  FollowUpChannel _channel = FollowUpChannel.call;
  LeadStatus? _statusAfter;
  DateTime? _nextFollowUp;

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _staffNote.dispose();
    _customerAnswer.dispose();
    _lostReason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(leadRepositoryProvider).addFollowUp(
            widget.leadId,
            channel: _channel,
            staffNote: _staffNote.text,
            customerAnswer: _customerAnswer.text,
            statusAfter: _statusAfter,
            nextFollowUpOn: _nextFollowUp,
            lostReason: _lostReason.text,
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
    final closing = _statusAfter == LeadStatus.lost;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Record a conversation', style: SwarnimTheme.cardTitle),
              const SizedBox(height: 16),

              Text('HOW', style: SwarnimTheme.fieldLabel),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in FollowUpChannel.values)
                    _Choice(
                      label: c.label,
                      selected: _channel == c,
                      onTap: () => setState(() => _channel = c),
                    ),
                ],
              ),

              const SizedBox(height: 18),
              Text('WHAT WE SAID', style: SwarnimTheme.fieldLabel),
              const SizedBox(height: 8),
              _Sheet(controller: _staffNote, hint: 'What did you offer or explain?'),

              const SizedBox(height: 16),
              Text('WHAT THEY SAID', style: SwarnimTheme.fieldLabel),
              const SizedBox(height: 4),
              Text(
                'Their words, not a summary - this is what the office reads back.',
                style: GoogleFonts.poppins(fontSize: 11, color: SwarnimColors.metaOnLight),
              ),
              const SizedBox(height: 8),
              _Sheet(controller: _customerAnswer, hint: 'How did they answer?'),

              const SizedBox(height: 18),
              Text('MOVE TO', style: SwarnimTheme.fieldLabel),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in LeadStatus.values)
                    if (s != widget.current)
                      _Choice(
                        label: s.label,
                        selected: _statusAfter == s,
                        onTap: () => setState(() => _statusAfter = _statusAfter == s ? null : s),
                      ),
                ],
              ),

              if (closing) ...[
                const SizedBox(height: 16),
                Text('WHY WAS IT LOST?', style: SwarnimTheme.fieldLabel),
                const SizedBox(height: 8),
                _Sheet(controller: _lostReason, hint: 'Price, location, bought elsewhere…', lines: 2),
              ],

              if (_statusAfter?.isOpen ?? true) ...[
                const SizedBox(height: 18),
                Text('CALL BACK ON', style: SwarnimTheme.fieldLabel),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _nextFollowUp ?? DateTime.now().add(const Duration(days: 3)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) setState(() => _nextFollowUp = picked);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                    decoration: BoxDecoration(
                      border: Border.all(color: SwarnimColors.borderLight),
                      borderRadius: BorderRadius.circular(SwarnimRadius.control),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.event_outlined, size: 18, color: SwarnimColors.metaOnLight),
                        const SizedBox(width: 10),
                        Text(
                          _nextFollowUp == null
                              ? 'Keep the current date'
                              : DateFormat('EEEE, d MMM yyyy').format(_nextFollowUp!),
                          style: GoogleFonts.poppins(
                              fontSize: 13.5, color: SwarnimColors.inkOnLight),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style: GoogleFonts.poppins(fontSize: 12, color: SwarnimColors.statusOpen)),
              ],

              const SizedBox(height: 20),
              PrimaryButton(
                label: 'Save',
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

class _Sheet extends StatelessWidget {
  const _Sheet({required this.controller, required this.hint, this.lines = 3});

  final TextEditingController controller;
  final String hint;
  final int lines;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        maxLines: lines,
        style: GoogleFonts.poppins(fontSize: 13.5, color: SwarnimColors.inkOnLight),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.poppins(fontSize: 13, color: SwarnimColors.metaOnLight),
          isDense: true,
          contentPadding: const EdgeInsets.all(12),
          border: _b(SwarnimColors.borderLight),
          enabledBorder: _b(SwarnimColors.borderLight),
          focusedBorder: _b(SwarnimColors.gold, 1.5),
        ),
      );

  static OutlineInputBorder _b(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(SwarnimRadius.control),
        borderSide: BorderSide(color: c, width: w),
      );
}

class _Choice extends StatelessWidget {
  const _Choice({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? SwarnimColors.navy : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? SwarnimColors.navy : SwarnimColors.borderLight),
          ),
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? SwarnimColors.inkOnDark : SwarnimColors.metaOnLight,
            ),
          ),
        ),
      );
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: SwarnimTheme.cardMeta),
            Flexible(
              child: Text(value,
                  textAlign: TextAlign.right,
                  style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: SwarnimColors.inkOnLight,
                  )),
            ),
          ],
        ),
      );
}

class _Back extends StatelessWidget {
  const _Back({required this.onTap});

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
