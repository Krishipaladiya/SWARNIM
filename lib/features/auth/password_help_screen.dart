import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme.dart';
import '../../core/api_client.dart';

/// "Trouble signing in?" - the customer asks for a new password for their unit.
///
/// There is no self-service password *change* anywhere in this app, by design:
/// passwords are issued by the site office. This screen is the one thing a
/// locked-out customer can do alone, which is why it is reachable from the
/// login screen rather than from behind it.
class PasswordHelpScreen extends ConsumerStatefulWidget {
  const PasswordHelpScreen({super.key});

  @override
  ConsumerState<PasswordHelpScreen> createState() => _PasswordHelpScreenState();
}

class _PasswordHelpScreenState extends ConsumerState<PasswordHelpScreen> {
  final _unit = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _busy = false;
  String? _error;

  /// The acknowledgement, once sent. Set means the form is replaced by it.
  String? _sent;
  String _siteOffice = '';

  @override
  void dispose() {
    _unit.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final response = await ref.read(dioProvider).post(
        '/api/v1/public/password-reset',
        data: {'loginId': _unit.text.trim()},
      );

      final data = response.data as Map<String, dynamic>;

      if (mounted) {
        setState(() {
          // The server says the same thing whether the unit exists or not, so
          // the app has nothing to interpret - it just shows the sentence.
          _sent = data['message'] as String? ?? '';
          _siteOffice = data['siteOfficeNumber'] as String? ?? '';
        });
      }
    } on DioException catch (e) {
      if (mounted) setState(() => _error = ApiException.from(e).message);
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
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: InkResponse(
                  onTap: () => context.pop(),
                  radius: 24,
                  child: const SizedBox(
                    width: 40,
                    height: 40,
                    child: Icon(Icons.arrow_back, color: SwarnimColors.inkOnDark, size: 22),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              Text(
                _sent == null ? 'Trouble signing in?' : 'Request sent',
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: SwarnimColors.inkOnDark,
                ),
              ),
              const SizedBox(height: 8),

              if (_sent == null) ...[
                Text(
                  'Enter your unit ID and we will send a new password to the mobile '
                  'number registered against your flat.',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    height: 1.55,
                    color: SwarnimColors.metaOnDark,
                  ),
                ),
                const SizedBox(height: 28),

                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Unit ID', style: SwarnimTheme.fieldLabelDark),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _unit,
                        textCapitalization: TextCapitalization.characters,
                        autofocus: true,
                        onFieldSubmitted: (_) => _submit(),
                        style: GoogleFonts.poppins(fontSize: 15, color: SwarnimColors.inkOnDark),
                        cursorColor: SwarnimColors.gold,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Enter the unit ID from your allotment letter'
                            : null,
                        decoration: InputDecoration(
                          // The app theme fills inputs for the light body; this
                          // screen is navy, so it opts out the same way the
                          // login fields do.
                          filled: false,
                          hintText: 'SWH-A-1203',
                          hintStyle: GoogleFonts.poppins(
                              fontSize: 15, color: SwarnimColors.placeholderOnDark),
                          enabledBorder: const UnderlineInputBorder(
                            borderSide: BorderSide(color: SwarnimColors.inputUnderline),
                          ),
                          focusedBorder: const UnderlineInputBorder(
                            borderSide: BorderSide(color: SwarnimColors.gold, width: 1.5),
                          ),
                          errorStyle: GoogleFonts.poppins(fontSize: 11.5),
                        ),
                      ),

                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!,
                            style: GoogleFonts.poppins(
                                fontSize: 12.5, color: SwarnimColors.goldHover)),
                      ],

                      const SizedBox(height: 24),
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
                            : const Text('Send me a new password'),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),
                _Note(
                  'The password goes only to the mobile number recorded when your '
                  'flat was allotted. If that number has changed, the site office '
                  'has to update it before this will reach you.',
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: SwarnimColors.navyMid,
                    borderRadius: BorderRadius.circular(SwarnimRadius.control),
                    border: const Border(left: BorderSide(color: SwarnimColors.gold, width: 3)),
                  ),
                  child: Text(
                    _sent!,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      height: 1.6,
                      color: SwarnimColors.inkOnDark,
                    ),
                  ),
                ),

                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => context.pop(),
                  child: const Text('Back to sign in'),
                ),

                const SizedBox(height: 24),
                _Note(
                  'Nothing arrived? The site office can read the new password out '
                  'to you.${_siteOffice.isEmpty ? "" : "\n\nSite office: $_siteOffice"}',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: SwarnimColors.dividerDark),
          borderRadius: BorderRadius.circular(SwarnimRadius.control),
        ),
        child: Text(
          text,
          style: GoogleFonts.poppins(
            fontSize: 12,
            height: 1.55,
            color: SwarnimColors.metaOnDark,
          ),
        ),
      );
}
