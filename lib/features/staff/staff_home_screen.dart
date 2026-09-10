import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/auth.dart';
import '../../core/leads.dart';
import '../../core/staff.dart';
import 'staff_widgets.dart';

/// The site team's home. Deliberately nothing like the customer's.
///
/// A resident opens the app to ask "what is happening about my flat". An
/// engineer opens it to ask "what do I have to do today, and what is late".
/// Same app, opposite questions - so this screen leads with counts and a work
/// list, and carries no construction progress, no project imagery, no unit card.
class StaffHomeScreen extends ConsumerWidget {
  const StaffHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final name = auth is SignedIn ? auth.displayName : '';
    final counts = ref.watch(staffCountsProvider);
    final queue = ref.watch(staffQueueProvider);

    return SwarnimScreen(
      eyebrow: _greeting(),
      title: name.isEmpty ? 'Site team' : name,
      subtitle: 'Swarnim Connect · Site team',
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(staffCountsProvider);
          ref.invalidate(staffQueueProvider);
          ref.invalidate(leadCountsProvider);
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            counts.when(
              loading: () => const SizedBox(height: 84),
              error: (_, _) => const SizedBox.shrink(),
              data: (c) => Row(
                children: [
                  Expanded(
                    child: _Cue(
                      value: c.mine,
                      label: 'On me',
                      onTap: () => _openQueue(context, ref, QueueScope.mine),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Cue(
                      value: c.overdue,
                      label: 'Overdue',
                      alarming: c.overdue > 0,
                      onTap: () => _openQueue(context, ref, QueueScope.myTeams),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Cue(
                      value: c.unclaimed,
                      label: 'Unclaimed',
                      onTap: () => _openQueue(context, ref, QueueScope.unassigned),
                    ),
                  ),
                ],
              ),
            ),

            // Leads get one line rather than three more tiles: for most of the
            // site team complaints are the job and leads are the sideline, and
            // the screen should say so.
            const _LeadsStrip(),

            const FieldLabel('Your team\'s work', topGap: 24),

            queue.when(
              loading: StaffAsyncBody.loading,
              error: (e, _) => StaffAsyncBody.error(e, () => ref.invalidate(staffQueueProvider)),
              data: (page) => page.items.isEmpty
                  ? StaffAsyncBody.empty(
                      'Nothing open',
                      'No complaints are waiting on your team right now.')
                  : Column(
                      children: [
                        // A home screen is a summary, not the queue. Five is
                        // enough to see whether today is bad; the rest is one
                        // tap away on the tab that exists for it.
                        for (final row in page.items.take(5))
                          StaffComplaintTile(
                            row: row,
                            onTap: () => context.push('/staff/complaints/${row.id}'),
                          ),
                        if (page.total > 5)
                          TextButton(
                            onPressed: () => _openQueue(context, ref, QueueScope.myTeams),
                            child: Text('See all ${page.total}',
                                style: GoogleFonts.poppins(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: SwarnimColors.navy,
                                )),
                          ),
                      ],
                    ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  static void _openQueue(BuildContext context, WidgetRef ref, QueueScope scope) {
    ref.read(queueFilterProvider.notifier).setScope(scope);
    ref.read(queueFilterProvider.notifier).setOpenOnly(true);
    StatefulNavigationShell.of(context).goBranch(1);
  }

  static String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }
}

/// A Business Central-style cue tile, scaled to a phone. The number is the
/// content; the label is the caption.
class _Cue extends StatelessWidget {
  const _Cue({
    required this.value,
    required this.label,
    required this.onTap,
    this.alarming = false,
  });

  final int value;
  final String label;
  final VoidCallback onTap;
  final bool alarming;

  @override
  Widget build(BuildContext context) {
    final accent = alarming ? SwarnimColors.statusOpen : SwarnimColors.gold;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SwarnimRadius.control),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: BoxDecoration(
            gradient: SwarnimColors.cardGradient,
            borderRadius: BorderRadius.circular(SwarnimRadius.control),
            border: Border(top: BorderSide(color: accent, width: 3)),
          ),
          child: Column(
            children: [
              Text('$value',
                  style: GoogleFonts.poppins(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                    color: alarming ? SwarnimColors.statusOpen : SwarnimColors.inkOnLight,
                  )),
              const SizedBox(height: 2),
              Text(label.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: SwarnimColors.metaOnLight,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

/// A single line of lead numbers, tappable through to the Leads tab.
class _LeadsStrip extends ConsumerWidget {
  const _LeadsStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(leadCountsProvider);

    return counts.when(
      // Silent on failure. A site engineer without lead permissions still uses
      // this screen for complaints, and an error banner about a feature they do
      // not have is noise.
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (c) {
        if (c.open == 0 && c.dueToday == 0 && c.overdue == 0) return const SizedBox.shrink();

        final urgent = c.overdue > 0;

        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => StatefulNavigationShell.of(context).goBranch(2),
              borderRadius: BorderRadius.circular(SwarnimRadius.control),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  gradient: SwarnimColors.cardGradient,
                  borderRadius: BorderRadius.circular(SwarnimRadius.control),
                  border: Border(
                    left: BorderSide(
                      color: urgent ? SwarnimColors.statusOpen : SwarnimColors.goldSoft,
                      width: 4,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.handshake_outlined,
                        size: 18,
                        color: urgent ? SwarnimColors.statusOpen : SwarnimColors.metaOnLight),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Leads', style: SwarnimTheme.cardTitle),
                          const SizedBox(height: 2),
                          Text(
                            [
                              if (c.dueToday > 0) '${c.dueToday} due today',
                              if (c.overdue > 0) '${c.overdue} overdue',
                              '${c.open} open',
                            ].join(' · '),
                            style: GoogleFonts.poppins(
                              fontSize: 11.5,
                              fontWeight: urgent ? FontWeight.w600 : FontWeight.w400,
                              color: urgent
                                  ? SwarnimColors.statusOpen
                                  : SwarnimColors.metaOnLight,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, size: 20, color: SwarnimColors.metaOnLight),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
