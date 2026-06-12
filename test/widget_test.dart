import 'package:flutter_test/flutter_test.dart';
import 'package:quran_vocab/main.dart';

void main() {
  testWidgets('App loads', (WidgetTester tester) async {
    await tester.pumpWidget(const QuranApp());
    expect(find.byType(QuranApp), findsOneWidget);
  });
}