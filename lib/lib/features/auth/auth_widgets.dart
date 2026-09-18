import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme.dart';

/// The two controls the sign-in screens share.
///
/// Extracted from login_screen rather than copied into the set-password
/// screen: they are the app's only dark-ground form controls, and a second
/// copy is a second thing to keep in step with the mockup.

class DarkField extends StatelessWidget {
  const DarkField({
    super.key,
    required this.controller,
    required this.hint,
    this.obscure = false,
    this.suffix,
    this.validator,
    this.onSubmitted,
    this.autofillHints,
    this.inputFormatters,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final Widget? suffix;
  final String? Function(String?)? validator;
  final void Function(String)? onSubmitted;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      validator: validator,
      onFieldSubmitted: onSubmitted,
      autofillHints: autofillHints,
      inputFormatters: inputFormatters,
      keyboardType: keyboardType,
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

class ErrorBanner extends StatelessWidget {
  const ErrorBanner(this.message, {super.key});

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



/// Upper-cases as you type, but leaves an email address alone.
///
/// One field takes a unit ID (SWH-A-0101, always upper case on the letter) and
/// a member of staff's email or mobile. Upper-casing everything would show
/// somebody their own email address shouted back at them, so the rule is: the
/// moment the text contains an "@", stop.
///
/// Applied as a formatter rather than TextCapitalization.characters, because
/// that only hints to the keyboard - a paste, a hardware keyboard or a
/// password manager fill all bypass it.
class UpperCaseUnitIdFormatter extends TextInputFormatter {
  const UpperCaseUnitIdFormatter();

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.contains('@')) return newValue;

    final upper = newValue.text.toUpperCase();
    if (upper == newValue.text) return newValue;

    // Selection is carried over unchanged: upper-casing never changes the
    // length, so the caret stays where the user left it.
    return newValue.copyWith(text: upper);
  }
}
