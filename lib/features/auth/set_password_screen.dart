import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme.dart';
import '../../core/api_client.dart';
import '../../core/auth.dart';
import '../brand/splash_screen.dart';
import 'auth_widgets.dart';

/// Choose your own password - the second half of the entry flow.
///
/// The site office issues one generated password and hands it over on the
/// allotment letter. The customer signs in with it once and lands here, and
/// the router will not let them past until they have replaced it. Until they
/// do, the password on their account is one that was printed on a letter and
/// can be read off a list in the portal.
///
/// Deliberately NOT skippable, and with no back arrow. A "remind me later" on
/// this screen is a "never" for almost everybody, and the one thing it is for
/// is ending the period where the office and the customer know the same
/// password.
class SetPasswordScreen extends ConsumerStatefulWidget {
  /// [forced] is the router's gate: the customer is still on the password the
  /// site office issued and cannot reach the app until it is replaced. The
  /// same screen with [forced] false is a customer choosing to change a
  /// password that is already their own, reached from My Profile - so it gets
  /// a way back and drops the letter wording, which would make no sense.
  const SetPasswordScreen({super.key, this.forced = true});

  final bool forced;

  @override
  ConsumerState<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends ConsumerState<SetPasswordScreen> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(authControllerProvider.notifier).setPassword(
            currentPassword: _current.text,
            newPassword: _next.text,
          );
      // The forced screen needs no navigation: clearing the flag changes the
      // auth state, and the redirect that was holding the session here stops
      // holding it. Nothing was holding the voluntary screen, so it has to
      // leave under its own steam.
      if (!widget.forced && mounted) {
        final auth = ref.read(authControllerProvider);
        context.go(auth is SignedIn && auth.isStaff ? '/staff/account' : '/account');
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final forced = widget.forced;

    return Scaffold(
      backgroundColor: SwarnimColors.navy,
      appBar: forced
          ? null
          : AppBar(
              backgroundColor: SwarnimColors.navy,
              elevation: 0,
              foregroundColor: SwarnimColors.inkOnDark,
            ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (forced) ...[
                  const Center(child: SwarnimLogo(width: 196)),
                  const SizedBox(height: 24),
                ],

                Text(
                  forced ? 'Choose your password' : 'Change your password',
                  style: GoogleFonts.poppins(
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                    color: SwarnimColors.inkOnDark,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  forced
                      ? 'The password on your allotment letter was created for '
                          'you and is known to the site office. Set one only '
                          'you know.'
                      : 'You will be signed back in with the new password. Any '
                          'other device stays signed out.',
                  style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    height: 1.5,
                    color: SwarnimColors.placeholderOnDark,
                  ),
                ),
                const SizedBox(height: 24),

                Text(forced ? 'Password from your letter' : 'Current password',
                    style: SwarnimTheme.fieldLabelDark),
                const SizedBox(height: 8),
                DarkField(
                  controller: _current,
                  hint: '••••••••',
                  obscure: _obscure,
                  autofillHints: const [AutofillHints.password],
                  validator: (v) => (v == null || v.isEmpty)
                      ? (forced
                          ? 'Enter the password you just signed in with'
                          : 'Enter your current password')
                      : null,
                ),

                const SizedBox(height: 16),
                Text('New password', style: SwarnimTheme.fieldLabelDark),
                const SizedBox(height: 8),
                DarkField(
                  controller: _next,
                  hint: 'At least 8 characters',
                  obscure: _obscure,
                  autofillHints: const [AutofillHints.newPassword],
                  // Matches the server's rule exactly. A client that asked for
                  // less would let somebody type a password the API then
                  // refuses, which reads as the app being broken.
                  validator: (v) => (v == null || v.length < 8)
                      ? 'Use at least 8 characters'
                      : null,
                  suffix: IconButton(
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 20,
                      color: SwarnimColors.placeholderOnDark,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),

                const SizedBox(height: 16),
                Text('Confirm new password', style: SwarnimTheme.fieldLabelDark),
                const SizedBox(height: 8),
                DarkField(
                  controller: _confirm,
                  hint: 'Type it again',
                  obscure: _obscure,
                  onSubmitted: (_) => _submit(),
                  // Checked here rather than on the server: a mistyped
                  // confirmation is not a failed request, and a round trip to
                  // be told you typed two different things is a round trip
                  // wasted on a slow connection.
                  validator: (v) =>
                      v != _next.text ? 'The two passwords do not match' : null,
                ),

                if (_error != null) ...[
                  const SizedBox(height: 12),
                  ErrorBanner(_error!),
                ],

                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: SwarnimColors.buttonPrimaryText,
                          ),
                        )
                      : Text(forced ? 'Save and continue' : 'Save new password'),
                ),

                if (forced) ...[
                const SizedBox(height: 18),
                Text(
                  'Forgotten the letter? Sign out and ask the site office for a '
                  'new password.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 11.5,
                    height: 1.5,
                    color: SwarnimColors.placeholderOnDark,
                  ),
                ),
                const SizedBox(height: 6),

                // The one way off this screen, and it does not skip anything:
                // signing out leaves the password unchanged and the flag set,
                // so the screen is waiting again next time.
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => ref.read(authControllerProvider.notifier).signOut(),
                  child: Text(
                    'Sign out',
                    style: GoogleFonts.poppins(
                      fontSize: 12.5,
                      color: SwarnimColors.gold,
                    ),
                  ),
                ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
