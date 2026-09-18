import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/leads.dart';
import '../staff/staff_widgets.dart';

/// The salesperson's list of people to ring.
///
/// Defaults to **Due** rather than to everything: a pipeline list that opens on
/// two hundred names is a list nobody works. The first thing on screen should be
/// the handful of calls owed today.
class LeadsScreen extends ConsumerStatefulWidget {
  const LeadsScreen({super.key});

  @override
  ConsumerState<LeadsScreen> createState() => _LeadsScreenState();
}

class _LeadsScreenState extends ConsumerState<LeadsScreen> {
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _search.text = ref.read(leadFilterProvider).search;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) ref.read(leadFilterProvider.notifier).setSearch(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(leadFilterProvider);
    final leads = ref.watch(leadsProvider);

    return SwarnimScreen(
      // Pull down to reload. No refresh button: the gesture is
      // the affordance every phone user already has.
      onRefresh: () async {
        ref.invalidate(leadsProvider);
      },
      title: 'Leads',
      subtitle: leads.maybeWhen(
        data: (p) => '${p.total} ${p.total == 1 ? "person" : "people"}',
        orElse: () => 'Loading',
      ),
      trailing: InkResponse(
        onTap: () => context.push('/staff/leads/new'),
        radius: 24,
        child: const SizedBox(
          width: 36,
          height: 40,
          child: Icon(Icons.person_add_alt_1, size: 22, color: SwarnimColors.gold),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _search,
            onChanged: _onSearchChanged,
            style: GoogleFonts.poppins(fontSize: 13.5, color: SwarnimColors.inkOnLight),
            decoration: InputDecoration(
              hintText: 'Name, mobile or lead number',
              hintStyle: GoogleFonts.poppins(fontSize: 13, color: SwarnimColors.metaOnLight),
              prefixIcon: const Icon(Icons.search, size: 20, color: SwarnimColors.metaOnLight),
              suffixIcon: filter.search.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      color: SwarnimColors.metaOnLight,
                      onPressed: () {
                        _search.clear();
                        ref.read(leadFilterProvider.notifier).setSearch('');
                      },
                    ),
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              border: _border(SwarnimColors.borderLight),
              enabledBorder: _border(SwarnimColors.borderLight),
              focusedBorder: _border(SwarnimColors.gold, 1.5),
            ),
          ),

          const SizedBox(height: 12),
          Row(
            children: [
              for (final (scope, label) in const [
                (LeadScope.due, 'Due'),
                (LeadScope.mine, 'Mine'),
                (LeadScope.all, 'Everyone'),
              ]) ...[
                _Chip(
                  label: label,
                  selected: filter.scope == scope,
                  onTap: () => ref.read(leadFilterProvider.notifier).setScope(scope),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),

          const SizedBox(height: 16),

          leads.when(
            loading: StaffAsyncBody.loading,
            error: (e, _) => StaffAsyncBody.error(e, () => ref.invalidate(leadsProvider)),
            data: (page) => page.items.isEmpty
                ? StaffAsyncBody.empty(
                    filter.scope == LeadScope.due ? 'Nothing due' : 'No leads',
                    filter.search.isNotEmpty
                        ? 'Nothing matches "${filter.search}".'
                        : filter.scope == LeadScope.due
                            ? 'No follow-ups are owed today. Tap + to add an enquiry.'
                            : 'Tap + to add the first enquiry.')
                : Column(
                    children: [
                      for (final lead in page.items)
                        LeadTile(
                          lead: lead,
                          onTap: () => context.push('/staff/leads/${lead.id}'),
                        ),
                    ],
                  ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  static OutlineInputBorder _border(Color colour, [double width = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(SwarnimRadius.control),
        borderSide: BorderSide(color: colour, width: width),
      );
}

/// One person in the list. Mobile is shown because the next action is almost
/// always to ring them.
class LeadTile extends StatelessWidget {
  const LeadTile({super.key, required this.lead, this.onTap});

  final Lead lead;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = lead.isOverdue
        ? SwarnimColors.statusOpen
        : lead.status == LeadStatus.won
            ? SwarnimColors.goldSoft
            : SwarnimColors.gold;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        gradient: SwarnimColors.cardGradient,
        borderRadius: BorderRadius.circular(SwarnimRadius.control),
        border: Border(left: BorderSide(color: accent, width: 4)),
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
                    Text(lead.number,
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: SwarnimColors.metaOnLight,
                        )),
                    const Spacer(),
                    LeadStatusPill(lead.status),
                  ],
                ),
                const SizedBox(height: 6),
                Text(lead.fullName, style: SwarnimTheme.cardTitle),
                const SizedBox(height: 3),
                Text(
                  [
                    lead.mobile,
                    if (lead.unitType != null) lead.unitType!,
                    if (lead.city != null) lead.city!,
                  ].join(' · '),
                  style: SwarnimTheme.cardMeta,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      lead.isOverdue ? Icons.error_outline : Icons.event_outlined,
                      size: 14,
                      color: lead.isOverdue ? SwarnimColors.statusOpen : SwarnimColors.metaOnLight,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        _due(lead),
                        style: GoogleFonts.poppins(
                          fontSize: 11.5,
                          fontWeight: lead.isOverdue ? FontWeight.w600 : FontWeight.w400,
                          color: lead.isOverdue
                              ? SwarnimColors.statusOpen
                              : SwarnimColors.metaOnLight,
                        ),
                      ),
                    ),
                    if (lead.followUpCount > 0)
                      Text('${lead.followUpCount} note${lead.followUpCount == 1 ? "" : "s"}',
                          style: SwarnimTheme.cardMeta),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _due(Lead lead) {
    if (!lead.isOpen) return lead.status == LeadStatus.won ? 'Booked' : 'Closed';
    if (lead.nextFollowUpOn == null) return 'No follow-up set';
    if (lead.isDueToday) return 'Due today';

    final days = DateTime.now().difference(lead.nextFollowUpOn!).inDays;
    if (lead.isOverdue) return '$days day${days == 1 ? "" : "s"} overdue';
    return 'Due ${DateFormat('d MMM').format(lead.nextFollowUpOn!)}';
  }
}

class LeadStatusPill extends StatelessWidget {
  const LeadStatusPill(this.status, {super.key});

  final LeadStatus status;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      LeadStatus.newLead => (SwarnimColors.statusOpen, Colors.white),
      LeadStatus.won => (SwarnimColors.navy, SwarnimColors.gold),
      LeadStatus.lost => (SwarnimColors.statusResolvedBg, SwarnimColors.metaOnLight),
      LeadStatus.negotiating || LeadStatus.visitPlanned || LeadStatus.visited =>
        (SwarnimColors.gold, SwarnimColors.navy),
      _ => (SwarnimColors.navyMid, SwarnimColors.gold),
    };

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

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? SwarnimColors.navy : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: selected ? SwarnimColors.navy : SwarnimColors.borderLight),
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
        ),
      );
}
