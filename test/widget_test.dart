import 'package:flutter_test/flutter_test.dart';
import 'package:painter/main.dart';

void main() {
  testWidgets('launches directly to the canvas', (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(const PainterApp());

    expect(find.bySemanticsLabel('Canvas'), findsOneWidget);
    semantics.dispose();
  });
}
