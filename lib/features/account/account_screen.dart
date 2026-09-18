import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/auth.dart';
import '../../core/unit.dart';

/// Screen 06 of the mockup — on live data.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(dashboardProvider);

    return SwarnimScreen(
      // Pull down to reload. No refresh button: the gesture is
      // the affordance every phone user already has.
      onRefresh: () async {
        ref.invalidate(dashboardProvider);
      },
      title: 'My Profile',
      child: dashboard.when(
        loading: () => const Padding(
          padding: EdgeInsets.only(top: 72),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        error: (e, _) => Padding(
          padding: const EdgeInsets.only(top: 48),
          child: Column(
            children: [
              Text('Could not load your profile',
                  style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: SwarnimColors.inkOnLight)),
              const SizedBox(height: 20),
              SecondaryButton(
                label: 'Try again',
                onPressed: () => ref.invalidate(dashboardProvider),
              ),
              const SizedBox(height: 8),
              SecondaryButton(
                label: 'Log Out',
                onPressed: () => _confirmSignOut(context, ref),
              ),
            ],
          ),
        ),
        data: (d) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: InitialsAvatar(_initials(d.customerName))),
            const SizedBox(height: 16),
            Text(
              d.customerName,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: SwarnimColors.inkOnLight,
              ),
            ),
            const SizedBox(height: 4),
            Text('${d.unitLabel} • Owner',
                textAlign: TextAlign.center, style: SwarnimTheme.cardMeta),
            const SizedBox(height: 24),

            SwarnimCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Your unit', style: SwarnimTheme.cardTitle),
                  const SizedBox(height: 6),
                  _Row('Project', d.projectName),
                  _Row('Building', d.buildingName),
                  if (d.floorNumber != null) _Row('Floor', '${d.floorNumber}'),
                  _Row('Unit', d.unitNumber),
                  if (d.unitType != null && d.unitType!.isNotEmpty) _Row('Type', d.unitType!),
                ],
              ),
            ),

            SwarnimCard(
              accent: d.isUnderMaintenance ? SwarnimColors.gold : SwarnimColors.statusOpen,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Maintenance cover', style: SwarnimTheme.cardTitle),
                  const SizedBox(height: 6),
                  Text(
                    d.maintenanceEndsOn == null
                        ? 'Not recorded. Contact the site office.'
                        : d.isUnderMaintenance
                            ? 'Covered until ${DateFormat('d MMM yyyy').format(d.maintenanceEndsOn!)}'
                                '${d.maintenanceDaysRemaining == null ? "" : " (${d.maintenanceDaysRemaining} days left)"}'
                            : 'Ended on ${DateFormat('d MMM yyyy').format(d.maintenanceEndsOn!)}',
                    style: SwarnimTheme.cardMeta,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),
            // Above "Request a new password" deliberately: changing a password
            // you know is the ordinary case, and asking the office to issue one
            // is the fallback for having lost it.
            SecondaryButton(
              label: 'Change password',
              icon: Icons.lock_outline,
              onPressed: () => context.push('/change-password'),
            ),
            const SizedBox(height: 8),
            SecondaryButton(
              label: 'Request a new password',
              icon: Icons.key_outlined,
              onPressed: () => _requestPassword(context),
            ),
            const SizedBox(height: 8),
            SecondaryButton(
              label: 'Log Out',
              icon: Icons.logout,
              onPressed: () => _confirmSignOut(context, ref),
            ),

            const SizedBox(height: 20),
            const BuiltByCredit(),
            const SizedBox(height: 6),
            Text(
              'Swarnim Connect · v1.0.0',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 11, color: SwarnimColors.metaOnLight),
            ),
          ],
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first).toUpperCase();
  }

  /// The fallback for a customer who cannot use "Change password" because they
  /// no longer know the current one. Only the office can help there: it holds
  /// the issued password and can reissue. Until the SMS gateway exists this
  /// explains the process rather than pretending to do it.
  void _requestPassword(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text('Need a new password?', style: SwarnimTheme.cardTitle),
        content: Text(
          'Call the site office and ask for a new password for your unit. '
          'They will issue one and send it to your registered mobile number.\n\n'
          'Site office: +91 9876 543 210',
          style: SwarnimTheme.cardMeta,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close',
                style: GoogleFonts.poppins(color: SwarnimColors.navy)),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    // Signing out means re-entering a unit ID and password printed on a letter
    // the customer may not have to hand - worth one confirmation.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text('Log out?', style: SwarnimTheme.cardTitle),
        content: Text(
          'You will need your unit ID and password to sign in again.',
          style: SwarnimTheme.cardMeta,
        ),
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
