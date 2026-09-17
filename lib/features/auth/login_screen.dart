import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme.dart';
import '../../core/api_client.dart';
import '../../core/auth.dart';
import '../brand/splash_screen.dart';
import '../projects/project_slider.dart';
import 'auth_widgets.dart';

/// Full-navy sign-in screen. Unlike the rest of the app there is no light body -
/// the mockup keeps login entirely on the dark ground.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _loginId = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _loginId.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(authControllerProvider.notifier).signIn(
            identifier: _loginId.text.trim(),
            password: _password.text,
          );
      // No navigation here - the router redirects on the auth state change,
      // and it is the redirect that decides which of the two apps you land in.
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SwarnimColors.navy,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _BrandMark(),
                const SizedBox(height: 20),

                // Labelled for the customer, who is almost everybody signing in
                // and always signs in with a unit ID.
                //
                // Staff type their work email into this same box and it still
                // works - the server decides what an identifier is and routes on
                // the answer. Naming both here made every resident read a second
                // option that was never theirs, so the label names the common
                // case and the rare one simply keeps working.
                Text('Unit ID', style: SwarnimTheme.fieldLabelDark),
                const SizedBox(height: 8),
                DarkField(
                  controller: _loginId,
                  hint: 'SWH-A-1203',
                  // No auto-capitalisation: it would upper-case the first letter
                  // of a staff email, and unit IDs are matched as typed.
                  autofillHints: const [AutofillHints.username],
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Enter the unit ID from your allotment letter'
                      : null,
                ),

                const SizedBox(height: 14),
                Text('Password', style: SwarnimTheme.fieldLabelDark),
                const SizedBox(height: 8),
                DarkField(
                  controller: _password,
                  hint: '••••••••',
                  obscure: _obscure,
                  autofillHints: const [AutofillHints.password],
                  onSubmitted: (_) => _submit(),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Enter your password' : null,
                  suffix: IconButton(
                    icon: Icon(
                      _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      size: 20,
                      color: SwarnimColors.placeholderOnDark,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),

                if (_error != null) ...[
                  const SizedBox(height: 8),
                  ErrorBanner(_error!),
                ],

                const SizedBox(height: 16),
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
                      : const Text('Sign In'),
                ),

                const SizedBox(height: 20),

                // The heading belongs to the slider, so it disappears with it
                // when the builder has uploaded no photographs.
                const ProjectSlider(
                  signedIn: false,
                  onDark: true,
                  heading: 'OUR PROJECTS',
                ),
                const SizedBox(height: 18),
                const _SupportFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The supplied lock-up, at the size the mockup reserved for it.
///
/// Replaces the placeholder circled "S" that stood in until the artwork
/// arrived. No caption underneath: the logo already says SWARNIM.
class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) => const Center(child: SwarnimLogo(width: 196));
}



class _SupportFooter extends StatelessWidget {
  const _SupportFooter();

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.poppins(
      fontSize: 10,
      height: 1.6,
      color: SwarnimColors.placeholderOnDark,
    );

    return Column(
      children: [
        const Divider(color: SwarnimColors.dividerDark, height: 1),
        const SizedBox(height: 14),

        // A real destination, not a phone number to read. Being locked out is
        // the one thing a customer can resolve without ringing anybody, and
        // this is the only route to it.
        TextButton(
          onPressed: () => context.push('/password-help'),
          child: Text(
            'Trouble signing in?',
            style: GoogleFonts.poppins(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: SwarnimColors.gold,
            ),
          ),
        ),

        const SizedBox(height: 2),
        Text('Site office: +91 9876 543 210 · support@swarnim.in',
            style: style, textAlign: TextAlign.center),
      ],
    );
  }
}
