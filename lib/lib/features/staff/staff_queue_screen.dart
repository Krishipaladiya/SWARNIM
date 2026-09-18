import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/staff.dart';
import 'staff_widgets.dart';

/// The work queue: every complaint the engineer is allowed to see, filtered.
///
/// The four scopes are the four questions actually asked on site - what is mine,
/// what is my team's, what has nobody taken, and (for supervisors) everything.
/// The server decides which of those return anything; a site engineer asking for
/// "All" simply gets their own team's work back, which is the correct answer
/// rather than an error.
class StaffQueueScreen extends ConsumerStatefulWidget {
  const StaffQueueScreen({super.key});

  @override
  ConsumerState<StaffQueueScreen> createState() => _StaffQueueScreenState();
}

class _StaffQueueScreenState extends ConsumerState<StaffQueueScreen> {
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _search.text = ref.read(queueFilterProvider).search;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  /// Typing a complaint number should not fire a request per keystroke.
  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) ref.read(queueFilterProvider.notifier).setSearch(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(queueFilterProvider);
    final queue = ref.watch(staffQueueProvider);

    return SwarnimScreen(
      title: 'Work Queue',
      subtitle: queue.maybeWhen(
        data: (p) => '${p.total} complaint${p.total == 1 ? "" : "s"}',
        orElse: () => 'Loading',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _search,
            onChanged: _onSearchChanged,
            style: GoogleFonts.poppins(fontSize: 13.5, color: SwarnimColors.inkOnLight),
            decoration: InputDecoration(
              hintText: 'Number, unit, or customer',
              hintStyle: GoogleFonts.poppins(fontSize: 13, color: SwarnimColors.metaOnLight),
              prefixIcon: const Icon(Icons.search, size: 20, color: SwarnimColors.metaOnLight),
              suffixIcon: filter.search.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      color: SwarnimColors.metaOnLight,
                      onPressed: () {
                        _search.clear();
                        ref.read(queueFilterProvider.notifier).setSearch('');
                      },
                    ),
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
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

          const SizedBox(height: 12),

          SwarnimScrollRow(
            children: [
                for (final scope in QueueScope.values) ...[
                  _Chip(
                    label: scope.label,
                    selected: filter.scope == scope,
                    onTap: () => ref.read(queueFilterProvider.notifier).setScope(scope),
                  ),
                  const SizedBox(width: 8),
                ],
                Container(width: 1, color: SwarnimColors.dividerLight),
                const SizedBox(width: 8),
                _Chip(
                  label: filter.openOnly ? 'Open' : 'Closed',
                  selected: true,
                  icon: Icons.swap_horiz,
                  onTap: () =>
                      ref.read(queueFilterProvider.notifier).setOpenOnly(!filter.openOnly),
                ),
            ],
          ),

          const SizedBox(height: 16),

          queue.when(
            loading: StaffAsyncBody.loading,
            error: (e, _) => StaffAsyncBody.error(e, () => ref.invalidate(staffQueueProvider)),
            data: (page) => page.items.isEmpty
                ? StaffAsyncBody.empty(
                    'Nothing here',
                    filter.search.isEmpty
                        ? 'No complaints match this filter.'
                        : 'Nothing matches "${filter.search}".')
                : Column(
                    children: [
                      for (final row in page.items)
                        StaffComplaintTile(
                          row: row,
                          onTap: () => context.push('/staff/complaints/${row.id}'),
                        ),
                      if (page.pageCount > 1)
                        Padding(
                          padding: const EdgeInsets.only(top: 4, bottom: 12),
                          child: Text(
                            'Showing the first ${page.items.length} of ${page.total}. '
                            'Narrow the search to see the rest.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                                fontSize: 11.5, color: SwarnimColors.metaOnLight),
                          ),
                        ),
                    ],
                  ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Material(
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
              color: selected ? SwarnimColors.navy : SwarnimColors.borderLight,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: selected ? SwarnimColors.gold : SwarnimColors.metaOnLight),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? SwarnimColors.inkOnDark : SwarnimColors.metaOnLight,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
