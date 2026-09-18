import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth.dart';
import '../features/account/account_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/password_help_screen.dart';
import '../features/auth/set_password_screen.dart';
import '../features/brand/splash_screen.dart';
import '../features/complaints/complaint_detail_screen.dart';
import '../features/complaints/complaints_screen.dart';
import '../features/complaints/new_complaint_screen.dart';
import '../features/complaints/verify_close_screen.dart';
import '../features/documents/documents_screen.dart';
import '../features/home/home_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/leads/lead_detail_screen.dart';
import '../features/leads/leads_screen.dart';
import '../features/leads/new_lead_screen.dart';
import '../features/staff/staff_account_screen.dart';
import '../features/staff/staff_close_screen.dart';
import '../features/staff/staff_complaint_screen.dart';
import '../features/staff/staff_finish_screen.dart';
import '../features/staff/staff_home_screen.dart';
import '../features/staff/staff_queue_screen.dart';

/// Bridges Riverpod state into go_router, which wants a [Listenable].
class _AuthListenable extends ChangeNotifier {
  _AuthListenable(Ref ref) {
    ref.listen(authControllerProvider, (_, _) => notifyListeners());

    // The launch film also decides when the app may move on, so the router has
    // to be told when it ends - otherwise redirect never re-runs and the splash
    // stays up after auth has long since resolved.
    ref.listen(splashDoneProvider, (_, _) => notifyListeners());
  }
}

final _rootKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final listenable = _AuthListenable(ref);
  ref.onDispose(listenable.dispose);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/splash',
    refreshListenable: listenable,

    // Redirection lives in ONE place. Scattering auth checks across screens is
    // how a screen eventually ships without one.
    //
    // It also decides which of the two apps you are in. Customer routes and
    // staff routes are separate trees under separate prefixes rather than one
    // tree with conditional widgets: a staff member landing on /home would then
    // be a rendering bug, whereas here it is a redirect that cannot happen.
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final location = state.matchedLocation;

      // Hold the launch screen until the film has had its turn, even when the
      // session resolved instantly. Auth and the film run in parallel, so this
      // costs nothing on a slow connection and is the whole point on a fast one.
      if (!ref.read(splashDoneProvider)) {
        return location == '/splash' ? null : '/splash';
      }

      return switch (auth) {
        AuthUnknown() => location == '/splash' ? null : '/splash',
        // The password-help page is reachable while signed out, because being
        // locked out is precisely when it is needed.
        SignedOut() =>
          (location == '/login' || location == '/password-help') ? null : '/login',
        // Password first, for both apps.
        //
        // Placed ABOVE the two app branches on purpose: a session that still
        // owes a password change goes to one screen and nowhere else, so there
        // is no route - deep link, restored tab, back gesture - that reaches
        // the app around it. The office-issued password is known to whoever
        // issued it, and this is the only thing standing between that and a
        // customer's records.
        // Either gate lands on the same screen, which asks for whatever is
        // missing: a password, the customer's details, or both in one submit.
        //
        // profileRequired matters on its own, not just alongside a password
        // change: the server refuses every customer endpoint until the flat
        // has a holder, so a session without one would otherwise reach a home
        // screen that could only render errors.
        SignedIn(mustChangePassword: true) =>
          location == '/set-password' ? null : '/set-password',
        SignedIn(profileRequired: true) =>
          location == '/set-password' ? null : '/set-password',

        SignedIn(isStaff: true) =>
          location.startsWith('/staff') ? null : '/staff/home',
        SignedIn() =>
          (location == '/login' || location == '/splash' || location == '/set-password'
              || location.startsWith('/staff'))
              ? '/home'
              : null,
      };
    },

    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/password-help', builder: (_, _) => const PasswordHelpScreen()),

      // Outside both shells: it has no bottom navigation, because there is
      // nowhere else to go from it until the password is set.
      GoRoute(path: '/set-password', builder: (_, _) => const SetPasswordScreen()),

      // The same screen, chosen rather than imposed - reached from My Profile
      // by a customer whose password is already their own. Outside the shell
      // for the same reason as the gate: changing a password signs every
      // session out, so there is no tab to come back to mid-flow.
      // Two paths, one screen. The redirect above sends a staff session back
      // to /staff/* and a customer session away from it, so a single shared
      // path would be bounced for whichever half did not own the prefix.
      GoRoute(
          path: '/change-password',
          builder: (_, _) => const SetPasswordScreen(forced: false)),
      GoRoute(
          path: '/staff/change-password',
          builder: (_, _) => const SetPasswordScreen(forced: false)),

      // ------------------------------------------------------------ customer
      //
      // StatefulShellRoute keeps each tab's navigation stack alive, so moving
      // between tabs does not reset scroll position or lose a half-filled form.
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/complaints',
              builder: (_, _) => const ComplaintsScreen(),
              routes: [
                // Nested, so both keep the bottom navigation visible and the
                // back gesture returns to the list rather than the home tab.
                GoRoute(
                    path: 'new', builder: (_, _) => const NewComplaintScreen()),
                GoRoute(
                    path: ':id',
                    builder: (_, state) =>
                        ComplaintDetailScreen(complaintId: state.pathParameters['id']!)),
                GoRoute(
                    path: ':id/verify',
                    builder: (_, state) =>
                        VerifyCloseScreen(complaintId: state.pathParameters['id']!)),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/documents', builder: (_, _) => const DocumentsScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/account', builder: (_, _) => const AccountScreen()),
          ]),
        ],
      ),

      // --------------------------------------------------------------- staff
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell, staff: true),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/staff/home', builder: (_, _) => const StaffHomeScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/staff/queue',
              builder: (_, _) => const StaffQueueScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/staff/leads', builder: (_, _) => const LeadsScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/staff/account', builder: (_, _) => const StaffAccountScreen()),
          ]),
        ],
      ),

      // Pushed over the staff shell rather than nested in a branch: a complaint
      // is reached from the home tab and the queue tab alike, and nesting it
      // under one of them would make the back gesture lie about where you came
      // from.
      // Pushed over the staff shell for the same reason as a complaint: a lead
      // is opened from the Today tab and the Leads tab alike.
      GoRoute(
        path: '/staff/leads/new',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const NewLeadScreen(),
      ),
      GoRoute(
        path: '/staff/leads/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, state) => LeadDetailScreen(leadId: state.pathParameters['id']!),
      ),

      GoRoute(
        path: '/staff/complaints/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, state) =>
            StaffComplaintScreen(complaintId: state.pathParameters['id']!),
        routes: [
          GoRoute(
            path: 'finish',
            parentNavigatorKey: _rootKey,
            builder: (_, state) =>
                StaffFinishScreen(complaintId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: 'close',
            parentNavigatorKey: _rootKey,
            builder: (_, state) =>
                StaffCloseScreen(complaintId: state.pathParameters['id']!),
          ),
        ],
      ),
    ],
  );
});
