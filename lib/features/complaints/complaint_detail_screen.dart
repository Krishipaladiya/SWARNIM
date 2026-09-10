import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/complaints.dart';

/// One complaint: what was reported, what has happened since, and the photos.
class ComplaintDetailScreen extends ConsumerWidget {
  const ComplaintDetailScreen({super.key, required this.complaintId});

  final String complaintId;

  static ComplaintPillStyle _styleFor(String label) => switch (label) {
        'In Progress' => ComplaintPillStyle.inProgress,
        'Awaiting Verification' => ComplaintPillStyle.awaitingVerification,
        'Resolved' => ComplaintPillStyle.resolved,
        _ => ComplaintPillStyle.open,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(complaintDetailProvider(complaintId));

    return detail.when(
      loading: () => const SwarnimScreen(
        title: 'Complaint',
        child: Padding(
          padding: EdgeInsets.only(top: 72),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      ),
      error: (e, _) => SwarnimScreen(
        title: 'Complaint',
        leading: _Back(onTap: () => context.pop()),
        child: Padding(
          padding: const EdgeInsets.only(top: 48),
          child: Column(
            children: [
              Text('Could not load this complaint',
                  style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: SwarnimColors.inkOnLight)),
              const SizedBox(height: 8),
              Text(e.toString(),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      fontSize: 12.5, color: SwarnimColors.metaOnLight)),
              const SizedBox(height: 20),
              SecondaryButton(
                label: 'Try again',
                onPressed: () => ref.invalidate(complaintDetailProvider(complaintId)),
              ),
            ],
          ),
        ),
      ),
      data: (d) => SwarnimScreen(
        title: d.summary.title,
        subtitle: [
          d.summary.number,
          if (d.summary.location != null && d.summary.location!.isNotEmpty) d.summary.location!,
        ].join(' • '),
        leading: _Back(onTap: () => context.pop()),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status first: it is the one thing the customer opened this to see.
            SwarnimCard(
              accent: d.summary.statusLabel == 'Awaiting Verification'
                  ? SwarnimColors.goldSoft
                  : SwarnimColors.gold,
              onTap: d.summary.statusLabel == 'Awaiting Verification'
                  ? () => context.push('/complaints/$complaintId/verify')
                  : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      StatusPill(d.summary.statusLabel, style: _styleFor(d.summary.statusLabel)),
                      Text(d.summary.category, style: SwarnimTheme.cardMeta),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Filed ${DateFormat('d MMM yyyy').format(d.summary.raisedAt)}'
                    '${d.assignedTo == null ? "" : " • ${d.assignedTo}"}',
                    style: SwarnimTheme.cardMeta,
                  ),
                  if (d.summary.statusLabel == 'Awaiting Verification') ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(Icons.touch_app_outlined,
                            size: 16, color: SwarnimColors.navy),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Tap to see the code the engineer needs',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: SwarnimColors.navy,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            if (d.description != null && d.description!.isNotEmpty) ...[
              const FieldLabel('What you reported', topGap: 8),
              Text(d.description!,
                  style: GoogleFonts.poppins(
                      fontSize: 13, height: 1.5, color: SwarnimColors.inkOnLight)),
            ],

            if (d.attachments.isNotEmpty) ...[
              FieldLabel('Photos & video (${d.attachments.length})', topGap: 20),
              _Gallery(attachments: d.attachments),
            ],

            const FieldLabel('Progress', topGap: 20),
            if (d.timeline.isEmpty)
              Text('Nothing recorded yet.', style: SwarnimTheme.cardMeta)
            else
              _Timeline(events: d.timeline),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// Vertical timeline: gold dot per entry, line between, newest at the bottom.
class _Timeline extends StatelessWidget {
  const _Timeline({required this.events});

  final List<ComplaintEvent> events;

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
                        Expanded(
                          child: Container(width: 1, color: SwarnimColors.borderLight),
                        ),
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
                        Text(events[i].title,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: SwarnimColors.inkOnLight,
                            )),
                        const SizedBox(height: 2),
                        Text(
                          '${DateFormat('d MMM, HH:mm').format(events[i].at)} • ${events[i].by}',
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

class _Gallery extends StatelessWidget {
  const _Gallery({required this.attachments});

  final List<ComplaintAttachment> attachments;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: attachments.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final a = attachments[i];

          return ClipRRect(
            borderRadius: BorderRadius.circular(SwarnimRadius.control),
            child: SizedBox(
              width: 96,
              child: a.isVideo
                  // No inline player: a decoder package is not in the app yet,
                  // and a broken player is worse than an honest placeholder.
                  ? Container(
                      color: SwarnimColors.navyMid,
                      child: const Center(
                        child: Icon(Icons.play_circle_outline,
                            color: Colors.white70, size: 30),
                      ),
                    )
                  : AuthedImage(path: '/api/v1/files/${a.id}', fit: BoxFit.cover),
            ),
          );
        },
      ),
    );
  }
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
