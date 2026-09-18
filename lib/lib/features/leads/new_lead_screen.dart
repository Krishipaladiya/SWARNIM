import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/api_client.dart';
import '../../core/leads.dart';
import '../staff/staff_widgets.dart';

/// Capturing an enquiry, usually while the person is still standing there.
///
/// Two fields are mandatory and the rest are not, deliberately: a salesperson
/// mid-conversation will abandon a form that demands a budget and an email
/// before it will save a name and a number. Everything else can be filled in
/// from the follow-up screen afterwards.
class NewLeadScreen extends ConsumerStatefulWidget {
  const NewLeadScreen({super.key});

  @override
  ConsumerState<NewLeadScreen> createState() => _NewLeadScreenState();
}

class _NewLeadScreenState extends ConsumerState<NewLeadScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _mobile = TextEditingController();
  final _city = TextEditingController();
  final _budget = TextEditingController();
  final _notes = TextEditingController();

  String? _unitType;
  String? _source;
  DateTime _followUp = DateTime.now().add(const Duration(days: 1));

  Timer? _dupCheck;
  Lead? _duplicate;

  bool _busy = false;
  String? _error;

  static const _unitTypes = ['1BHK', '2BHK', '3BHK', '4BHK', 'Shop', 'Office'];
  static const _sources = {
    'WALK_IN': 'Walk-in',
    'REFERRAL': 'Referral',
    'HOARDING': 'Hoarding',
    'NEWSPAPER': 'Newspaper',
    'WEBSITE': 'Website',
    'FACEBOOK': 'Facebook',
    'INSTAGRAM': 'Instagram',
    'PROPERTY_PORTAL': 'Property portal',
    'BROKER': 'Broker',
    'OTHER': 'Other',
  };

  @override
  void dispose() {
    _dupCheck?.cancel();
    _name.dispose();
    _mobile.dispose();
    _city.dispose();
    _budget.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// Warns rather than blocks. Two people genuinely do share a phone, and a
  /// salesperson who cannot save the lead in front of them will write it on
  /// paper instead.
  void _onMobileChanged(String value) {
    _dupCheck?.cancel();
    if (value.trim().length < 10) {
      if (_duplicate != null) setState(() => _duplicate = null);
      return;
    }

    _dupCheck = Timer(const Duration(milliseconds: 500), () async {
      final match = await ref.read(leadRepositoryProvider).findByMobile(value.trim());
      if (mounted) setState(() => _duplicate = match);
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final message = await ref.read(leadRepositoryProvider).create(
            fullName: _name.text,
            mobile: _mobile.text,
            city: _city.text,
            source: _source,
            unitType: _unitType,
            budgetMax: num.tryParse(_budget.text.replaceAll(',', '').trim()),
            nextFollowUpOn: _followUp,
            notes: _notes.text,
          );

      ref.invalidate(leadsProvider);
      ref.invalidate(leadCountsProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message, style: GoogleFonts.poppins(fontSize: 12.5)),
        backgroundColor: SwarnimColors.navy,
        behavior: SnackBarBehavior.floating,
      ));
      context.pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SwarnimScreen(
      title: 'New lead',
      subtitle: 'Name and mobile are enough to start',
      leading: InkResponse(
        onTap: () => context.pop(),
        radius: 24,
        child: const SizedBox(
          width: 32,
          height: 40,
          child: Icon(Icons.arrow_back, size: 22, color: SwarnimColors.inkOnDark),
        ),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const FieldLabel('Name'),
            _Field(
              controller: _name,
              hint: 'Who walked in?',
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter their name' : null,
            ),

            const FieldLabel('Mobile', topGap: 16),
            _Field(
              controller: _mobile,
              hint: '10-digit number',
              keyboardType: TextInputType.phone,
              onChanged: _onMobileChanged,
              validator: (v) =>
                  (v == null || v.trim().length < 10) ? 'Enter a number you can call back on' : null,
            ),

            if (_duplicate case final dup?) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: SwarnimColors.goldSoft.withValues(alpha: 0.14),
                  border: const Border(
                      left: BorderSide(color: SwarnimColors.goldSoft, width: 3)),
                  borderRadius: BorderRadius.circular(SwarnimRadius.control),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Already on file',
                        style: GoogleFonts.poppins(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: SwarnimColors.inkOnLight,
                        )),
                    const SizedBox(height: 2),
                    Text(
                      '${dup.number} · ${dup.fullName}'
                      '${dup.owner == null ? "" : " · ${dup.owner}"}',
                      style: SwarnimTheme.cardMeta,
                    ),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: () => context.pushReplacement('/staff/leads/${dup.id}'),
                      child: Text('Open that lead instead',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: SwarnimColors.navy,
                            decoration: TextDecoration.underline,
                          )),
                    ),
                  ],
                ),
              ),
            ],

            const FieldLabel('Interested in', topGap: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in _unitTypes)
                  _Choice(
                    label: t,
                    selected: _unitType == t,
                    onTap: () => setState(() => _unitType = _unitType == t ? null : t),
                  ),
              ],
            ),

            const FieldLabel('How did they hear about us?', topGap: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in _sources.entries)
                  _Choice(
                    label: entry.value,
                    selected: _source == entry.key,
                    onTap: () =>
                        setState(() => _source = _source == entry.key ? null : entry.key),
                  ),
              ],
            ),

            const FieldLabel('City', topGap: 16),
            _Field(controller: _city, hint: 'Where do they live now?'),

            const FieldLabel('Budget (up to)', topGap: 16),
            _Field(controller: _budget, hint: 'e.g. 7500000', keyboardType: TextInputType.number),

            const FieldLabel('Call them back on', topGap: 16),
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _followUp,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) setState(() => _followUp = picked);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: SwarnimColors.borderLight),
                  borderRadius: BorderRadius.circular(SwarnimRadius.control),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.event_outlined, size: 18, color: SwarnimColors.metaOnLight),
                    const SizedBox(width: 10),
                    Text(DateFormat('EEEE, d MMM yyyy').format(_followUp),
                        style: GoogleFonts.poppins(
                            fontSize: 13.5, color: SwarnimColors.inkOnLight)),
                  ],
                ),
              ),
            ),

            const FieldLabel('Notes', topGap: 16),
            _Field(controller: _notes, hint: 'Anything worth remembering', lines: 3),

            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!,
                  style: GoogleFonts.poppins(fontSize: 12.5, color: SwarnimColors.statusOpen)),
            ],

            const SizedBox(height: 22),
            PrimaryButton(
              label: 'Save lead',
              icon: Icons.check,
              busy: _busy,
              onPressed: _busy ? null : _save,
            ),
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    this.lines = 1,
    this.keyboardType,
    this.validator,
    this.onChanged,
    this.autofocus = false,
    this.textCapitalization = TextCapitalization.none,
  });

  final TextEditingController controller;
  final String hint;
  final int lines;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        maxLines: lines,
        keyboardType: keyboardType,
        validator: validator,
        onChanged: onChanged,
        autofocus: autofocus,
        textCapitalization: textCapitalization,
        style: GoogleFonts.poppins(fontSize: 13.5, color: SwarnimColors.inkOnLight),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.poppins(fontSize: 13, color: SwarnimColors.metaOnLight),
          filled: true,
          fillColor: Colors.white,
          isDense: true,
          contentPadding: const EdgeInsets.all(12),
          errorStyle: GoogleFonts.poppins(fontSize: 11.5),
          border: _border(SwarnimColors.borderLight),
          enabledBorder: _border(SwarnimColors.borderLight),
          focusedBorder: _border(SwarnimColors.gold, 1.5),
        ),
      );

  static OutlineInputBorder _border(Color colour, [double width = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(SwarnimRadius.control),
        borderSide: BorderSide(color: colour, width: width),
      );
}

class _Choice extends StatelessWidget {
  const _Choice({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? SwarnimColors.navy : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? SwarnimColors.navy : SwarnimColors.borderLight),
          ),
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? SwarnimColors.inkOnDark : SwarnimColors.metaOnLight,
            ),
          ),
        ),
      );
}
