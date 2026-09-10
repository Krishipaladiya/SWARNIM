import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme.dart';
import '../../core/api_client.dart';
import '../../core/auth.dart';
import '../projects/project_slider.dart';

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

                Text('Unit ID or email', style: SwarnimTheme.fieldLabelDark),
                const SizedBox(height: 8),
                _DarkField(
                  controller: _loginId,
                  hint: 'SWH-A-1203  ·  name@swarnim.in',
                  // No auto-capitalisation: it would upper-case the first letter
                  // of an email address, and unit IDs are matched as typed.
                  autofillHints: const [AutofillHints.username],
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Enter the unit ID from your allotment letter, or your work email'
                      : null,
                ),

                const SizedBox(height: 14),
                Text('Password', style: SwarnimTheme.fieldLabelDark),
                const SizedBox(height: 8),
                _DarkField(
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
                  _ErrorBanner(_error!),
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
                Text('OUR PROJECTS', style: SwarnimTheme.fieldLabelDark, textAlign: TextAlign.center),
                const SizedBox(height: 10),
                const ProjectSlider(signedIn: false, onDark: true),
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

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    // Placeholder for the supplied logo (the mockup references a 130px image).
    // Drop the asset in and replace this with Image.asset to match exactly.
    return Column(
      children: [
        Container(
          width: 68,
          height: 68,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: SwarnimColors.gold, width: 1.5),
            shape: BoxShape.circle,
          ),
          child: Text(
            'S',
            style: GoogleFonts.poppins(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: SwarnimColors.gold,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'SWARNIM',
          style: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 5,
            color: SwarnimColors.inkOnDark,
          ),
        ),
      ],
    );
  }
}

/// Underlined field on the navy ground, per the mockup.
class _DarkField extends StatelessWidget {
  const _DarkField({
    required this.controller,
    required this.hint,
    this.obscure = false,
    this.suffix,
    this.validator,
    this.onSubmitted,
    this.autofillHints,
  });

  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final Widget? suffix;
  final String? Function(String?)? validator;
  final void Function(String)? onSubmitted;
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      validator: validator,
      onFieldSubmitted: onSubmitted,
      autofillHints: autofillHints,
      textInputAction:
          onSubmitted != null ? TextInputAction.done : TextInputAction.next,
      style: GoogleFonts.poppins(fontSize: 15, color: SwarnimColors.inkOnDark),
      cursorColor: SwarnimColors.gold,
      decoration: InputDecoration(
        filled: false,
        hintText: hint,
        hintStyle:
            GoogleFonts.poppins(fontSize: 15, color: SwarnimColors.placeholderOnDark),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        suffixIcon: suffix,
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: SwarnimColors.inputUnderline, width: 2),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: SwarnimColors.gold, width: 2),
        ),
        errorBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: SwarnimColors.statusOpen, width: 2),
        ),
        focusedErrorBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: SwarnimColors.statusOpen, width: 2),
        ),
        errorStyle: GoogleFonts.poppins(fontSize: 11, color: SwarnimColors.goldHover),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: SwarnimColors.statusOpen.withValues(alpha: 0.15),
        border: Border(left: BorderSide(color: SwarnimColors.statusOpen, width: 3)),
        borderRadius: BorderRadius.circular(SwarnimRadius.control),
      ),
      child: Text(
        message,
        style: GoogleFonts.poppins(fontSize: 12, color: SwarnimColors.inkOnDark),
      ),
    );
  }
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
