import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

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
                ],
              ),
            ),

            const SizedBox(height: 8),
            SecondaryButton(
              label: 'Change password',
              icon: Icons.lock_outline,
              onPressed: () => context.push('/change-password'),
            ),
            const SizedBox(height: 8),
            SecondaryButton(
              label: 'Log Out',
              icon: Icons.logout,
              onPressed: () => _confirmSignOut(context, ref),
            ),

            const SizedBox(height: 8),

            // Last, and visually quietest of the three.
            //
            // It is here because the App Store requires an app that creates
            // accounts to offer a way to delete one. It is at the bottom
            // because it is the one action on this screen nobody should reach
            // by accident.
            SecondaryButton(
              label: 'Delete account',
              icon: Icons.delete_outline,
              onPressed: () => _requestDeletion(context, d),
            ),

            const SizedBox(height: 20),
            const BuiltByCredit(),
            const SizedBox(height: 6),
            Text(
              'Swarnim Connect · v1.0.0',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 11, color: SwarnimColors.metaOnLight),
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
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  /// Where a deletion request goes. One address, named in the app so the
  /// resident can see who they are writing to before their mail app opens.
  static const _supportEmail = 'support@cloudverve.in';

  /// Asks the office to delete the account, by opening the resident's own mail
  /// app with the message already written.
  ///
  /// WHY THE MAIL APP RATHER THAN A SERVER CALL
  ///
  /// The office closes the account by hand, so this exists to tell them which
  /// account, and to leave the resident holding a copy of what they asked for -
  /// a sent item is a record they own, which a silent API call is not. It also
  /// means the app needs no mail server of its own.
  ///
  /// The unit details go in the SUBJECT as well as the body. Support mailboxes
  /// are triaged from the subject line, and "Delete my account" on its own
  /// names neither the flat nor the project it belongs to.
  Future<void> _requestDeletion(BuildContext context, UnitDashboard d) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        // Square, like every other dialog in this app.
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text('Delete your account?', style: SwarnimTheme.cardTitle),
        content: Text(
          'This opens your email app with a request to the site office, '
          'already filled in. Send it and the office will close your '
          'Swarnim Connect account.\n\n'
          'You will lose access to this app. The records of your flat - the '
          'allotment, the complaint history and the documents - are kept by '
          'Swarnim Group as the developer of the property.',
          style: GoogleFonts.poppins(
            fontSize: 13,
            height: 1.5,
            color: SwarnimColors.inkOnLight,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel',
                style: GoogleFonts.poppins(color: SwarnimColors.metaOnLight)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Continue',
                style: GoogleFonts.poppins(
                    color: SwarnimColors.statusOpen,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final floor = d.floorNumber == null ? '' : 'Floor: ${d.floorNumber}\n';

    final subject = 'Delete my Swarnim Connect account - '
        '${d.projectName}, ${d.buildingName}, Unit ${d.unitNumber}';

    final body = 'Please delete my Swarnim Connect account.\n\n'
        'Name: ${d.customerName}\n'
        'Login ID: ${d.loginId}\n'
        'Project: ${d.projectName}\n'
        'Building: ${d.buildingName}\n'
        '$floor'
        'Unit: ${d.unitNumber}\n\n'
        'I understand I will lose access to the app.\n';

    // Built with Uri(...) rather than by pasting a string together. A subject
    // line carrying a project name has spaces and commas in it, and a hand
    // written mailto: link drops everything after the first unescaped one -
    // which would reach the office naming no flat at all.
    final mail = Uri(
      scheme: 'mailto',
      path: _supportEmail,
      queryParameters: {'subject': subject, 'body': body},
    );

    final opened = await launchUrl(mail, mode: LaunchMode.externalApplication);
    if (opened || !context.mounted) return;

    // No mail app configured, which happens often enough on a work phone.
    // Give them the address rather than a dead end.
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text('No email app found', style: SwarnimTheme.cardTitle),
        content: SelectableText(
          'Email $_supportEmail from any device, and include your login ID '
          '${d.loginId} and unit ${d.unitNumber}.',
          style: GoogleFonts.poppins(
            fontSize: 13,
            height: 1.5,
            color: SwarnimColors.inkOnLight,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    // Signing out means re-entering a username and password - a unit id from
    // the allotment letter for a resident, a mobile number for staff - which
    // the customer may not have to hand. Worth one confirmation.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text('Log out?', style: SwarnimTheme.cardTitle),
        content: Text(
          'You will need your username and password to sign in again.',
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
                    color: SwarnimColors.statusOpen,
                    fontWeight: FontWeight.w600)),
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
