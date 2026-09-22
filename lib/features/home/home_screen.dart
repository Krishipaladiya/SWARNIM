import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/complaints.dart';
import '../../core/unit.dart';
import '../projects/project_slider.dart';

/// Customer home, screen 02 of the mockup — on live data.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static ComplaintPillStyle _styleFor(String label) => switch (label) {
        'In Progress' => ComplaintPillStyle.inProgress,
        'Awaiting Verification' => ComplaintPillStyle.awaitingVerification,
        'Resolved' => ComplaintPillStyle.resolved,
        _ => ComplaintPillStyle.open,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(dashboardProvider);

    return dashboard.when(
      loading: () => const SwarnimScreen(
        title: 'Your Unit',
        child: Padding(
          padding: EdgeInsets.only(top: 72),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      ),
      error: (e, _) => SwarnimScreen(
        title: 'Your Unit',
        child: _ErrorBody(message: e.toString(), onRetry: () => ref.invalidate(dashboardProvider)),
      ),
      data: (d) => SwarnimScreen(
        eyebrow: 'Your Unit',
        title: d.unitLabel,
        subtitle: d.locationLine,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(dashboardProvider);
            ref.invalidate(myComplaintsProvider);
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (d.progressPercent > 0) ...[
                const FieldLabel('Construction Progress'),
                _Progress(percent: d.progressPercent, note: d.progressNote),
                const SizedBox(height: 16),
              ],

              FieldLabel('Active Complaints${d.activeComplaints.isEmpty ? "" : " (${d.activeComplaints.length})"}'),

              if (d.activeComplaints.isEmpty)
                _Empty(underMaintenance: d.isUnderMaintenance)
              else
                for (final c in d.activeComplaints)
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
                            'Filed ${_ago(c.raisedAt)}',
                          ].join(' • '),
                          style: SwarnimTheme.cardMeta,
                        ),
                        const SizedBox(height: 8),
                        StatusPill(c.statusLabel, style: _styleFor(c.statusLabel)),
                      ],
                    ),
                  ),

              const FieldLabel('Quick Actions', topGap: 12),
              Row(
                children: [
                  Expanded(
                    child: SecondaryButton(
                      label: 'File Complaint',
                      icon: Icons.edit_note_outlined,
                      // Always available. This used to be disabled outside
                      // the builder's maintenance window, because the server
                      // refused the complaint anyway. Maintenance cover has
                      // been withdrawn from the product and that server rule
                      // went with it, so there is nothing left to gate on.
                      onPressed: () => context.push('/complaints/new'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SecondaryButton(
                      label: 'Documents',
                      icon: Icons.folder_outlined,
                      onPressed: () => context.go('/documents'),
                    ),
                  ),
                ],
              ),


              const SizedBox(height: 20),
              const _ProjectSlide(),
            ],
          ),
        ),
      ),
    );
  }

  static String _ago(DateTime when) {
    final days = DateTime.now().difference(when).inDays;
    if (days == 0) return 'today';
    if (days == 1) return 'yesterday';
    if (days < 30) return '$days days ago';
    return DateFormat('d MMM').format(when);
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.percent, this.note});

  final int percent;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: SwarnimColors.cardGradient,
        borderRadius: BorderRadius.circular(SwarnimRadius.control),
        border: const Border(left: BorderSide(color: SwarnimColors.gold, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(note ?? 'Under construction', style: SwarnimTheme.cardTitle),
              Text('$percent%',
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: SwarnimColors.navy,
                  )),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: percent / 100,
              minHeight: 6,
              backgroundColor: SwarnimColors.borderLight,
              valueColor: const AlwaysStoppedAnimation(SwarnimColors.gold),
            ),
          ),
        ],
      ),
    );
  }
}



class _Empty extends StatelessWidget {
  const _Empty({required this.underMaintenance});

  final bool underMaintenance;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
      decoration: BoxDecoration(
        gradient: SwarnimColors.cardGradient,
        borderRadius: BorderRadius.circular(SwarnimRadius.control),
        border: Border.all(color: SwarnimColors.borderLight),
      ),
      child: Column(
        children: [
          const Icon(Icons.check_circle_outline, size: 30, color: SwarnimColors.borderLight),
          const SizedBox(height: 10),
          Text('Nothing open right now',
              style: GoogleFonts.poppins(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: SwarnimColors.inkOnLight,
              )),
          const SizedBox(height: 4),
          Text(
            underMaintenance
                ? 'Anything not right in your flat? File it and the site team will pick it up.'
                : 'Your maintenance cover has ended.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 12, color: SwarnimColors.metaOnLight),
          ),
        ],
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 56),
      child: Column(
        children: [
          Text('Could not load your unit',
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: SwarnimColors.inkOnLight,
              )),
          const SizedBox(height: 8),
          Text(message,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 12.5, color: SwarnimColors.metaOnLight)),
          const SizedBox(height: 20),
          SecondaryButton(label: 'Try again', onPressed: onRetry),
        ],
      ),
    );
  }
}

class _ProjectSlide extends StatelessWidget {
  const _ProjectSlide();

  @override
  Widget build(BuildContext context) {
    // The curated slider, maintained in Admin Central under "App slider" -
    // not project photographs. Those document buildings; this is whatever the
    // office wants residents to see when they open the app, and while the two
    // shared a source neither could change without moving the other.
    //
    // Heading and divider are handed to the slider rather than drawn here: it
    // renders nothing when there are no slides, and a heading left outside it
    // showed a label over an empty gap.
    return const ProjectSlider(
      signedIn: true,
      curated: true,
      heading: 'FROM SWARNIM',
      leadIn: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Divider(color: SwarnimColors.dividerLight, height: 1),
          SizedBox(height: 20),
        ],
      ),
    );
  }
}
