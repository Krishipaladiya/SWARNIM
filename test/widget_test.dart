import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:swarnim_connect/main.dart';

void main() {
  testWidgets('boots into the splash state without throwing', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: SwarnimConnectApp()));
    await tester.pump();
    expect(find.byType(SwarnimConnectApp), findsOneWidget);
  });
}
