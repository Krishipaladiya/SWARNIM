import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';

/// Documents tab.
///
/// The approved mockup does not include this screen, but the bottom navigation
/// has four tabs and document storage is one of the two headline features. This
/// follows the established pattern until a design for it is supplied.
class DocumentsScreen extends StatelessWidget {
  const DocumentsScreen({super.key});

  static const _categories = <({String name, int count})>[
    (name: 'Agreements', count: 3),
    (name: 'Payment receipts', count: 9),
    (name: 'Approvals & NOC', count: 2),
    (name: 'Drawings & plans', count: 3),
    (name: 'Possession', count: 1),
  ];

  @override
  Widget build(BuildContext context) {
    return SwarnimScreen(
      title: 'Documents',
      subtitle: '18 documents • SWH-A-1203',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FieldLabel('Categories'),
          for (final c in _categories)
            SwarnimCard(
              onTap: () {},
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.name, style: SwarnimTheme.cardTitle),
                        const SizedBox(height: 4),
                        Text('${c.count} files', style: SwarnimTheme.cardMeta),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right,
                      size: 20, color: SwarnimColors.metaOnLight),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
