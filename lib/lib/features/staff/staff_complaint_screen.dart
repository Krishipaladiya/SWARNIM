import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/api_client.dart';
import '../../core/staff.dart';
import 'staff_update_sheet.dart';
import 'staff_widgets.dart';

/// One complaint, as the person doing the work sees it.
///
/// Carries everything the customer's version deliberately withholds: who they
/// are, their phone number, the internal notes, and the actions. The customer's
/// screen answers "what is happening"; this one answers "what do I do".
class StaffComplaintScreen extends ConsumerWidget {
  const StaffComplaintScreen({super.key, required this.complaintId});

  final String complaintId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(staffComplaintProvider(complaintId));

    return detail.when(
      loading: () => SwarnimScreen(
        title: 'Complaint',
        leading: _Back(onTap: () => context.pop()),
        child: StaffAsyncBody.loading(),
      ),
      error: (e, _) => SwarnimScreen(
        title: 'Complaint',
        leading: _Back(onTap: () => context.pop()),
        child: StaffAsyncBody.error(e, () => ref.invalidate(staffComplaintProvider(complaintId))),
      ),
      data: (d) => SwarnimScreen(
        title: d.row.number,
        subtitle: d.row.where,
        leading: _Back(onTap: () => context.pop()),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- what and where -------------------------------------------
            SwarnimCard(
              accent: d.row.isOverdue ? SwarnimColors.statusOpen : SwarnimColors.gold,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      WorkStatusPill(d.row.status),
                      const Spacer(),
                      if (d.row.isOverdue) const OverdueFlag(),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(d.row.title, style: SwarnimTheme.cardTitle),
                  const SizedBox(height: 4),
                  Text(
                    [
                      d.row.category,
                      if (d.row.location != null && d.row.location!.isNotEmpty) d.row.location!,
                      'Raised ${DateFormat('d MMM, HH:mm').format(d.row.raisedAt.toLocal())}',
                    ].join(' · '),
                    style: SwarnimTheme.cardMeta,
                  ),
                  if (d.row.slaDueAt != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Due ${DateFormat('d MMM, HH:mm').format(d.row.slaDueAt!.toLocal())}',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: d.row.isOverdue
                            ? SwarnimColors.statusOpen
                            : SwarnimColors.metaOnLight,
                      ),
                    ),
                  ],
                  if (d.reopenCount > 0) ...[
                    const SizedBox(height: 8),
                    // Worth shouting about: a reopened job means the last visit
                    // did not fix it, and whoever picks it up should know before
                    // they repeat the same work.
                    Row(
                      children: [
                        const Icon(Icons.replay, size: 14, color: SwarnimColors.statusOpen),
                        const SizedBox(width: 5),
                        Text(
                          'Reopened ${d.reopenCount} time${d.reopenCount == 1 ? "" : "s"}',
                          style: GoogleFonts.poppins(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: SwarnimColors.statusOpen,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // --- who ------------------------------------------------------
            SwarnimCard(
              accent: SwarnimColors.navyMid,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Customer', style: SwarnimTheme.cardTitle),
                  const SizedBox(height: 6),
                  _Row('Name', d.row.customerName),
                  _Row('Unit', d.row.unitLabel),
                  _Row('Prefers', d.slotLabel),
                  if (d.customerMobile != null) _Row('Mobile', d.customerMobile!),
                ],
              ),
            ),

            _Row('Assigned to', d.row.assignedStaff ?? d.row.assignedTeam ?? 'Nobody yet'),

            if (d.description != null && d.description!.isNotEmpty) ...[
              const FieldLabel('What was reported', topGap: 16),
              Text(d.description!,
                  style: GoogleFonts.poppins(
                      fontSize: 13, height: 1.5, color: SwarnimColors.inkOnLight)),
            ],

            if (d.attachmentCount > 0) ...[
              const FieldLabel('Customer photos', topGap: 16),
              Text('${d.attachmentCount} attached · open the complaint in Admin Central to review',
                  style: SwarnimTheme.cardMeta),
            ],

            // --- actions --------------------------------------------------
            const FieldLabel('Actions', topGap: 20),
            _Actions(detail: d, complaintId: complaintId),

            // --- history --------------------------------------------------
            const FieldLabel('History', topGap: 22),
            if (d.timeline.isEmpty)
              Text('Nothing recorded yet.', style: SwarnimTheme.cardMeta)
            else
              _Timeline(events: d.timeline),

            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }
}

class _Actions extends ConsumerStatefulWidget {
  const _Actions({required this.detail, required this.complaintId});

  final StaffComplaintDetail detail;
  final String complaintId;

  @override
  ConsumerState<_Actions> createState() => _ActionsState();
}

class _ActionsState extends ConsumerState<_Actions> {
  bool _busy = false;

  Future<void> _run(Future<String> Function() action) async {
    setState(() => _busy = true);
    try {
      final message = await action();
      ref.invalidate(staffComplaintProvider(widget.complaintId));
      ref.invalidate(staffQueueProvider);
      ref.invalidate(staffCountsProvider);
      if (mounted && message.isNotEmpty) _say(message);
    } on ApiException catch (e) {
      if (mounted) _say(e.message, bad: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _say(String message, {bool bad = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: GoogleFonts.poppins(fontSize: 12.5)),
      backgroundColor: bad ? SwarnimColors.statusOpen : SwarnimColors.navy,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.detail;
    final repo = ref.read(staffRepositoryProvider);
    final closed = d.row.status == WorkStatus.closed || d.row.status == WorkStatus.cancelled;

    if (closed) {
      return StaffAsyncBody.empty(
          'This complaint is closed', 'Nothing further to do here.');
    }

    // Waiting on the customer's code is a state with exactly one sensible
    // action, so the screen collapses to it rather than offering the full set.
    if (d.row.status == WorkStatus.awaitingConfirmation) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: SwarnimColors.goldSoft.withValues(alpha: 0.14),
              border: const Border(left: BorderSide(color: SwarnimColors.goldSoft, width: 3)),
              borderRadius: BorderRadius.circular(SwarnimRadius.control),
            ),
            child: Text(
              'A code is on the customer\'s app. Ask them to read it out, then enter it '
              'to close this complaint.',
              style: GoogleFonts.poppins(
                  fontSize: 12, height: 1.4, color: SwarnimColors.inkOnLight),
            ),
          ),
          PrimaryButton(
            label: 'Enter the customer\'s code',
            icon: Icons.password,
            busy: _busy,
            onPressed: () => context.push('/staff/complaints/${widget.complaintId}/close'),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (d.row.isUnclaimed) ...[
          PrimaryButton(
            label: 'Pick this up',
            icon: Icons.pan_tool_alt_outlined,
            busy: _busy,
            onPressed: _busy ? null : () => _run(() => repo.claim(widget.complaintId)),
          ),
          const SizedBox(height: 10),
        ],

        SecondaryButton(
          label: 'Add a work update',
          icon: Icons.edit_note_outlined,
          onPressed: _busy
              ? null
              : () async {
                  final changed = await showStaffUpdateSheet(
                    context,
                    complaintId: widget.complaintId,
                    nextStatuses: d.nextStatuses,
                  );
                  if (changed == true) {
                    ref.invalidate(staffComplaintProvider(widget.complaintId));
                    ref.invalidate(staffQueueProvider);
                  }
                },
        ),
        const SizedBox(height: 10),

        SecondaryButton(
          label: 'Assign to someone',
          icon: Icons.person_add_alt,
          onPressed: _busy ? null : () => _assign(),
        ),
        const SizedBox(height: 10),

        // Only offered once the work is actually claimed done. Requesting a
        // customer's code for a job still in progress trains them to hand it
        // over on request, which is exactly what the control exists to prevent.
        SecondaryButton(
          label: 'Work finished - ask for the customer\'s code',
          icon: Icons.verified_outlined,
          onPressed: _busy || d.row.status != WorkStatus.workDone
              ? null
              : () => context.push('/staff/complaints/${widget.complaintId}/finish'),
        ),
        if (d.row.status != WorkStatus.workDone)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Move the complaint to "Work done" first.',
              style: GoogleFonts.poppins(fontSize: 11, color: SwarnimColors.metaOnLight),
            ),
          ),
      ],
    );
  }

  Future<void> _assign() async {
    final people = await ref.read(staffRepositoryProvider).assignees().catchError(
          (Object _) => <Assignee>[],
        );

    if (!mounted) return;

    if (people.isEmpty) {
      _say('No one is available to assign to.', bad: true);
      return;
    }

    final chosen = await showModalBottomSheet<Assignee>(
      context: context,
      backgroundColor: Colors.white,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
              child: Text('Assign to', style: SwarnimTheme.cardTitle),
            ),
            for (final p in people)
              ListTile(
                leading: InitialsAvatar(_initials(p.name), size: 34),
                title: Text(p.name,
                    style: GoogleFonts.poppins(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        color: SwarnimColors.inkOnLight)),
                subtitle: p.designation == null
                    ? null
                    : Text(p.designation!, style: SwarnimTheme.cardMeta),
                onTap: () => Navigator.pop(context, p),
              ),
          ],
        ),
      ),
    );

    if (chosen == null) return;
    await _run(() => ref.read(staffRepositoryProvider).assign(
          widget.complaintId,
          staffId: chosen.id,
        ));
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first).toUpperCase();
  }
}

/// History with the internal entries marked. Staff see everything; the marker
/// is what stops someone writing a note for a colleague into the customer's view
/// by accident.
class _Timeline extends StatelessWidget {
  const _Timeline({required this.events});

  final List<StaffEvent> events;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < events.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 22,
                  child: Column(
                    children: [
                      Container(
                        width: i == events.length - 1 ? 12 : 9,
                        height: i == events.length - 1 ? 12 : 9,
                        margin: const EdgeInsets.only(top: 4),
                        decoration: BoxDecoration(
                          color: i == events.length - 1
                              ? SwarnimColors.gold
                              : SwarnimColors.borderLight,
                          shape: BoxShape.circle,
                        ),
                      ),
                      if (i != events.length - 1)
                        Expanded(child: Container(width: 1, color: SwarnimColors.borderLight)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: i == events.length - 1 ? 0 : 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(events[i].status.label,
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: SwarnimColors.inkOnLight,
                                  )),
                            ),
                            if (!events[i].visibleToCustomer) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  border: Border.all(color: SwarnimColors.borderLight),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                                child: Text('INTERNAL',
                                    style: GoogleFonts.poppins(
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.w700,
                                      color: SwarnimColors.metaOnLight,
                                    )),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${DateFormat('d MMM, HH:mm').format(events[i].at.toLocal())} · ${events[i].by}',
                          style: GoogleFonts.poppins(
                              fontSize: 11.5, color: SwarnimColors.metaOnLight),
                        ),
                        if (events[i].note != null && events[i].note!.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Text(events[i].note!,
                              style: GoogleFonts.poppins(
                                  fontSize: 12.5,
                                  height: 1.45,
                                  color: SwarnimColors.inkOnLight)),
                        ],
                        if (events[i].partsUsed != null && events[i].partsUsed!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text('Parts: ${events[i].partsUsed}',
                              style: GoogleFonts.poppins(
                                  fontSize: 11.5,
                                  fontStyle: FontStyle.italic,
                                  color: SwarnimColors.metaOnLight)),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
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
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: SwarnimColors.inkOnLight,
                ),
              ),
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
