import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/api_client.dart';
import '../../core/documents.dart';

/// The customer's paperwork, on live data.
///
/// Grouped by category rather than listed flat, because "where is my
/// agreement" is the question this screen exists to answer and a single
/// chronological list makes it a scrolling exercise. Anything needing an
/// acknowledgement is pulled to the top regardless of category - it is the one
/// thing here that is a task rather than a reference.
class DocumentsScreen extends ConsumerWidget {
  const DocumentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final documents = ref.watch(documentsProvider);

    return SwarnimScreen(
      title: 'Documents',
      subtitle: documents.maybeWhen(
        data: (d) => d.isEmpty ? 'Nothing yet' : '${d.length} document${d.length == 1 ? "" : "s"}',
        orElse: () => null,
      ),
      child: documents.when(
        loading: () => const Padding(
          padding: EdgeInsets.only(top: 72),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        error: (e, _) => Padding(
          padding: const EdgeInsets.only(top: 56),
          child: Column(
            children: [
              Text('Could not load your documents',
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
                onPressed: () => ref.invalidate(documentsProvider),
              ),
            ],
          ),
        ),
        data: (docs) {
          if (docs.isEmpty) return const _Empty();

          final toSign = docs.where((d) => d.needsAcknowledgement).toList();

          final byCategory = <String, List<CustomerDocument>>{};
          for (final d in docs) {
            byCategory.putIfAbsent(d.category, () => []).add(d);
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(documentsProvider),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (toSign.isNotEmpty) ...[
                  const FieldLabel('Needs your confirmation'),
                  for (final d in toSign) _DocumentCard(document: d, highlight: true),
                  const SizedBox(height: 8),
                ],

                for (final entry in byCategory.entries) ...[
                  FieldLabel('${entry.key} (${entry.value.length})', topGap: 12),
                  for (final d in entry.value) _DocumentCard(document: d),
                ],

                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DocumentCard extends ConsumerStatefulWidget {
  const _DocumentCard({required this.document, this.highlight = false});

  final CustomerDocument document;
  final bool highlight;

  @override
  ConsumerState<_DocumentCard> createState() => _DocumentCardState();
}

class _DocumentCardState extends ConsumerState<_DocumentCard> {
  bool _busy = false;

  Future<void> _open() async {
    setState(() => _busy = true);
    try {
      final file = await ref.read(documentRepositoryProvider).download(widget.document);
      final result = await OpenFilex.open(file.path);

      // A phone with no PDF reader is a real situation on a cheap handset, and
      // "nothing happened" is the worst possible answer.
      if (result.type != ResultType.done && mounted) {
        // Names the kind, because "no app can open that" is unactionable
        // while "install a spreadsheet app" is something a person can do.
        final what = switch (widget.document.kind) {
          DocumentKind.pdf => 'a PDF reader',
          DocumentKind.word => 'an app that opens Word documents',
          DocumentKind.sheet => 'an app that opens spreadsheets',
          DocumentKind.slides => 'an app that opens presentations',
          _ => 'an app that opens this kind of file',
        };
        _say('This phone has no $what installed.', bad: true);
      }
    } on ApiException catch (e) {
      if (mounted) _say(e.message, bad: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _acknowledge() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text('Confirm you have read this?', style: SwarnimTheme.cardTitle),
        content: Text(
          'This records the date and time against your unit. Open and read the '
          'document first if you have not already.',
          style: SwarnimTheme.cardMeta,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Not yet',
                style: GoogleFonts.poppins(color: SwarnimColors.metaOnLight)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('I have read it',
                style: GoogleFonts.poppins(
                    color: SwarnimColors.navy, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      final message = await ref.read(documentRepositoryProvider).acknowledge(widget.document.id);
      ref.invalidate(documentsProvider);
      if (mounted) _say(message.isEmpty ? 'Recorded.' : message);
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
    final d = widget.document;

    return SwarnimCard(
      accent: widget.highlight ? SwarnimColors.goldSoft : SwarnimColors.gold,
      onTap: _busy ? null : _open,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(switch (d.kind) {
                DocumentKind.pdf => Icons.picture_as_pdf_outlined,
                DocumentKind.word => Icons.description_outlined,
                DocumentKind.sheet => Icons.table_chart_outlined,
                DocumentKind.slides => Icons.slideshow_outlined,
                DocumentKind.text => Icons.notes_outlined,
                DocumentKind.image => Icons.image_outlined,
              },
                  size: 20, color: SwarnimColors.metaOnLight),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.title, style: SwarnimTheme.cardTitle),
                    const SizedBox(height: 3),
                    Text(
                      [
                        d.scopeLabel,
                        d.sizeLabel,
                        if (d.issuedDate != null)
                          DateFormat('d MMM yyyy').format(d.issuedDate!),
                      ].join(' · '),
                      style: SwarnimTheme.cardMeta,
                    ),
                  ],
                ),
              ),
              if (_busy)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 1.8),
                )
              else
                const Icon(Icons.open_in_new, size: 17, color: SwarnimColors.metaOnLight),
            ],
          ),

          if (d.description != null && d.description!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(d.description!,
                style: GoogleFonts.poppins(
                    fontSize: 12.5, height: 1.45, color: SwarnimColors.inkOnLight)),
          ],

          if (d.requiresAcknowledgement) ...[
            const SizedBox(height: 10),
            if (d.acknowledgedAt case final ack?)
              Row(
                children: [
                  const Icon(Icons.check_circle_outline, size: 15, color: SwarnimColors.metaOnLight),
                  const SizedBox(width: 5),
                  Text('Confirmed ${DateFormat('d MMM yyyy').format(ack.toLocal())}',
                      style: SwarnimTheme.cardMeta),
                ],
              )
            else
              SecondaryButton(
                label: 'I have read this',
                icon: Icons.check,
                onPressed: _busy ? null : _acknowledge,
              ),
          ],
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 18),
        decoration: BoxDecoration(
          gradient: SwarnimColors.cardGradient,
          borderRadius: BorderRadius.circular(SwarnimRadius.control),
          border: Border.all(color: SwarnimColors.borderLight),
        ),
        child: Column(
          children: [
            const Icon(Icons.folder_open_outlined, size: 34, color: SwarnimColors.borderLight),
            const SizedBox(height: 12),
            Text('No documents yet',
                style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: SwarnimColors.inkOnLight)),
            const SizedBox(height: 6),
            Text(
              'Your agreement, receipts and plans will appear here as the site '
              'office adds them.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 12.5, height: 1.5, color: SwarnimColors.metaOnLight),
            ),
          ],
        ),
      ),
    );
  }
}
