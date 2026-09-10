import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/auth.dart';
import '../../core/staff.dart';

/// The site team's profile. Short by design - a staff account has no unit, no
/// maintenance cover and no documents, so the customer's version of this screen
/// would be mostly empty rows.
class StaffAccountScreen extends ConsumerWidget {
  const StaffAccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final name = auth is SignedIn ? auth.displayName : '';
    final counts = ref.watch(staffCountsProvider);

    return SwarnimScreen(
      title: 'My Profile',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: InitialsAvatar(_initials(name))),
          const SizedBox(height: 16),
          Text(
            name.isEmpty ? 'Site team' : name,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: SwarnimColors.inkOnLight,
            ),
          ),
          const SizedBox(height: 4),
          Text('Swarnim site team',
              textAlign: TextAlign.center, style: SwarnimTheme.cardMeta),
          const SizedBox(height: 24),

          counts.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
            data: (c) => SwarnimCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Your workload', style: SwarnimTheme.cardTitle),
                  const SizedBox(height: 6),
                  _Row('Open on you', '${c.mine}'),
                  _Row('Overdue in your team', '${c.overdue}'),
                  _Row('Waiting to be picked up', '${c.unclaimed}'),
                ],
              ),
            ),
          ),

          const SizedBox(height: 8),
          SecondaryButton(
            label: 'Log Out',
            icon: Icons.logout,
            onPressed: () => _confirmSignOut(context, ref),
          ),

          const SizedBox(height: 20),
          Text(
            'Swarnim Connect · v1.0.0',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 11, color: SwarnimColors.metaOnLight),
          ),
        ],
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first).toUpperCase();
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text('Log out?', style: SwarnimTheme.cardTitle),
        content: Text('You will need your work email and password to sign in again.',
            style: SwarnimTheme.cardMeta),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel',
                style: GoogleFonts.poppins(color: SwarnimColors.metaOnLight)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Log out',
                style: GoogleFonts.poppins(
                    color: SwarnimColors.statusOpen, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      await ref.read(authControllerProvider.notifier).signOut();
    }
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
            Text(value,
                style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: SwarnimColors.inkOnLight,
                )),
          ],
        ),
      );
}
