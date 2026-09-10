import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/staff.dart';

/// Status as staff see it: eleven states, not the customer's four.
///
/// Colour carries meaning here rather than decoration - an engineer scanning a
/// queue on a phone in daylight reads the colour before the word.
class WorkStatusPill extends StatelessWidget {
  const WorkStatusPill(this.status, {super.key});

  final WorkStatus status;

  static (Color bg, Color fg) colours(WorkStatus s) => switch (s) {
        WorkStatus.newComplaint || WorkStatus.reopened => (SwarnimColors.statusOpen, Colors.white),
        WorkStatus.assigned || WorkStatus.acknowledged => (SwarnimColors.navyMid, SwarnimColors.gold),
        WorkStatus.onSite || WorkStatus.inProgress => (SwarnimColors.gold, SwarnimColors.navy),
        WorkStatus.partsAwaited => (SwarnimColors.goldSoft, Colors.white),
        WorkStatus.workDone || WorkStatus.awaitingConfirmation => (SwarnimColors.navy, SwarnimColors.gold),
        WorkStatus.closed || WorkStatus.cancelled => (SwarnimColors.statusResolvedBg, SwarnimColors.metaOnLight),
      };

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = colours(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(3)),
      child: Text(
        status.label.toUpperCase(),
        style: GoogleFonts.poppins(fontSize: 9.5, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

/// Small red flag on anything past its SLA. Deliberately loud: an overdue job
/// that looks like every other job will keep being treated like every other job.
class OverdueFlag extends StatelessWidget {
  const OverdueFlag({super.key});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.schedule, size: 13, color: SwarnimColors.statusOpen),
          const SizedBox(width: 3),
          Text('OVERDUE',
              style: GoogleFonts.poppins(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: SwarnimColors.statusOpen,
              )),
        ],
      );
}

/// One row in any staff list. Number and unit lead, because that is what an
/// engineer matches against the job in their hand.
class StaffComplaintTile extends StatelessWidget {
  const StaffComplaintTile({super.key, required this.row, this.onTap});

  final StaffComplaintRow row;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        gradient: SwarnimColors.cardGradient,
        borderRadius: BorderRadius.circular(SwarnimRadius.control),
        border: Border(
          left: BorderSide(
            color: row.isOverdue ? SwarnimColors.statusOpen : SwarnimColors.gold,
            width: 4,
          ),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(row.number,
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: SwarnimColors.metaOnLight,
                        )),
                    const Spacer(),
                    if (row.isOverdue) ...[const OverdueFlag(), const SizedBox(width: 8)],
                    WorkStatusPill(row.status),
                  ],
                ),
                const SizedBox(height: 6),
                Text(row.title, style: SwarnimTheme.cardTitle),
                const SizedBox(height: 3),
                Text(
                  [
                    row.where,
                    if (row.location != null && row.location!.isNotEmpty) row.location!,
                    row.customerName,
                  ].where((s) => s.isNotEmpty).join(' · '),
                  style: SwarnimTheme.cardMeta,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      row.isUnclaimed ? Icons.person_add_alt_outlined : Icons.person_outline,
                      size: 14,
                      color: row.isUnclaimed ? SwarnimColors.statusOpen : SwarnimColors.metaOnLight,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        row.assignedStaff ?? row.assignedTeam ?? 'Nobody has picked this up',
                        style: GoogleFonts.poppins(
                          fontSize: 11.5,
                          fontWeight: row.isUnclaimed ? FontWeight.w600 : FontWeight.w400,
                          color: row.isUnclaimed
                              ? SwarnimColors.statusOpen
                              : SwarnimColors.metaOnLight,
                        ),
                      ),
                    ),
                    Text(_due(row), style: SwarnimTheme.cardMeta),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _due(StaffComplaintRow row) {
    if (row.slaDueAt == null) return DateFormat('d MMM').format(row.raisedAt);

    final diff = row.slaDueAt!.difference(DateTime.now().toUtc());
    if (diff.isNegative) {
      final late = -diff.inHours;
      return late < 24 ? '${late}h late' : '${(late / 24).floor()}d late';
    }
    return diff.inHours < 24 ? 'due in ${diff.inHours}h' : 'due ${DateFormat('d MMM').format(row.slaDueAt!)}';
  }
}

/// Empty, error and loading states, written once. Three screens showing three
/// different spinners is how an app starts feeling stitched together.
class StaffAsyncBody extends StatelessWidget {
  const StaffAsyncBody({
    super.key,
    required this.child,
  });

  final Widget child;

  static Widget loading() => const Padding(
        padding: EdgeInsets.only(top: 72),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );

  static Widget error(Object e, VoidCallback onRetry) => Padding(
        padding: const EdgeInsets.only(top: 56),
        child: Column(
          children: [
            Text('Could not load',
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: SwarnimColors.inkOnLight,
                )),
            const SizedBox(height: 8),
            Text(e.toString(),
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(fontSize: 12.5, color: SwarnimColors.metaOnLight)),
            const SizedBox(height: 20),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      );

  static Widget empty(String title, String detail) => Container(
        padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 16),
        decoration: BoxDecoration(
          gradient: SwarnimColors.cardGradient,
          borderRadius: BorderRadius.circular(SwarnimRadius.control),
          border: Border.all(color: SwarnimColors.borderLight),
        ),
        child: Column(
          children: [
            const Icon(Icons.inbox_outlined, size: 30, color: SwarnimColors.borderLight),
            const SizedBox(height: 10),
            Text(title,
                style: GoogleFonts.poppins(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: SwarnimColors.inkOnLight,
                )),
            const SizedBox(height: 4),
            Text(detail,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(fontSize: 12, color: SwarnimColors.metaOnLight)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) => child;
}

/// Filled navy action button. The customer app only ever needed the pale
/// secondary button; staff screens have a clear primary action per screen.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.busy = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: enabled ? SwarnimColors.buttonPrimary : SwarnimColors.borderLight,
        borderRadius: BorderRadius.circular(SwarnimRadius.control),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(SwarnimRadius.control),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
                  )
                else if (icon != null)
                  Icon(icon, size: 18, color: SwarnimColors.buttonPrimaryText),
                if (busy || icon != null) const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    style: GoogleFonts.poppins(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: SwarnimColors.buttonPrimaryText,
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
