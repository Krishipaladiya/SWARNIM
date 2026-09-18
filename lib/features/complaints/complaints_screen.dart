import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/complaints.dart';

/// Screen 04 of the mockup, backed by the API.
class ComplaintsScreen extends ConsumerWidget {
  const ComplaintsScreen({super.key});

  static ComplaintPillStyle _styleFor(String label) => switch (label) {
        'In Progress' => ComplaintPillStyle.inProgress,
        'Awaiting Verification' => ComplaintPillStyle.awaitingVerification,
        'Resolved' => ComplaintPillStyle.resolved,
        _ => ComplaintPillStyle.open,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final complaints = ref.watch(myComplaintsProvider);

    return Stack(
      children: [
        SwarnimScreen(
          // Pull down to reload. No refresh button: the gesture is the
          // affordance every phone user already has.
          onRefresh: () async => ref.invalidate(myComplaintsProvider),
          title: 'My Complaints',
          subtitle: complaints.maybeWhen(
            data: (list) =>
                '${list.length} total • ${list.where((c) => c.isOpen).length} open',
            orElse: () => null,
          ),
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 96),
          child: complaints.when(
            loading: () => const Padding(
              padding: EdgeInsets.only(top: 64),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (e, _) => _Message(
              title: 'Could not load your complaints',
              body: e.toString(),
              onRetry: () => ref.invalidate(myComplaintsProvider),
            ),
            data: (list) => list.isEmpty
                ? const _Message(
                    title: 'No complaints yet',
                    body: 'Anything not right in your flat? File it here and the '
                        'site team will pick it up.',
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final c in list)
                        SwarnimCard(
                          onTap: () => context.push(
                            c.statusLabel == 'Awaiting Verification'
                                ? '/complaints/${c.id}/verify'
                                : '/complaints/${c.id}',
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(c.title, style: SwarnimTheme.cardTitle),
                              const SizedBox(height: 4),
                              Text(
                                [
                                  if (c.location != null && c.location!.isNotEmpty) c.location!,
                                  c.number,
                                  DateFormat('d MMM').format(c.raisedAt),
                                ].join(' • '),
                                style: SwarnimTheme.cardMeta,
                              ),
                              const SizedBox(height: 8),
                              StatusPill(c.statusLabel, style: _styleFor(c.statusLabel)),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          bottom: 20,
          child: FilledButton.icon(
            onPressed: () => context.push('/complaints/new'),
            icon: const Icon(Icons.add, size: 20),
            label: const Text('File New Complaint'),
          ),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.title, required this.body, this.onRetry});

  final String title;
  final String body;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 56),
      child: Column(
        children: [
          Text(title,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: SwarnimColors.inkOnLight,
              )),
          const SizedBox(height: 8),
          Text(body,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 12.5, color: SwarnimColors.metaOnLight)),
          if (onRetry != null) ...[
            const SizedBox(height: 20),
            SecondaryButton(label: 'Try again', onPressed: onRetry),
          ],
        ],
      ),
    );
  }
}
