import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';

/// Navy bottom bar from the mockup: four icons, the active one at full opacity
/// and the rest at 40%.
///
/// The mockup uses bitmap icons (home.png, report.png, approve.png, user.png).
/// Until those assets are supplied, these are the closest Material equivalents -
/// swapping them later is a one-line change per tab.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell, this.staff = false});

  final StatefulNavigationShell shell;

  /// Staff get three tabs, not four. They have no documents of their own, and
  /// "Complaints" reads wrong for a work queue - the labels are part of what
  /// makes the two experiences feel like different apps rather than one app
  /// with things hidden.
  final bool staff;

  static const _customerTabs = <({IconData icon, String label})>[
    (icon: Icons.home_outlined, label: 'Home'),
    (icon: Icons.assignment_outlined, label: 'Complaints'),
    (icon: Icons.folder_outlined, label: 'Documents'),
    (icon: Icons.person_outline, label: 'Profile'),
  ];

  static const _staffTabs = <({IconData icon, String label})>[
    (icon: Icons.dashboard_outlined, label: 'Today'),
    (icon: Icons.list_alt_outlined, label: 'Queue'),
    (icon: Icons.handshake_outlined, label: 'Leads'),
    (icon: Icons.person_outline, label: 'Profile'),
  ];

  List<({IconData icon, String label})> get _tabs => staff ? _staffTabs : _customerTabs;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: SwarnimColors.navy,
          border: Border(top: BorderSide(color: SwarnimColors.dividerDark)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                for (var i = 0; i < _tabs.length; i++)
                  _NavItem(
                    icon: _tabs[i].icon,
                    label: _tabs[i].label,
                    selected: shell.currentIndex == i,
                    // goBranch with initialLocation resets a tab to its root
                    // when you tap the tab you are already on - the behaviour
                    // people expect from every other app on their phone.
                    onTap: () => shell.goBranch(i, initialLocation: i == shell.currentIndex),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = SwarnimColors.inkOnDark.withValues(alpha: selected ? 1 : 0.4);

    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: InkResponse(
        onTap: onTap,
        radius: 32,
        // Hit target stays 48 tall even though the icon is 24.
        child: SizedBox(
          width: 64,
          height: 48,
          child: Icon(icon, size: 24, color: color),
        ),
      ),
    );
  }
}
