import 'package:flutter_test/flutter_test.dart';
import 'package:project_t/main.dart';

void main() {
  testWidgets('5 tabs bottom navigation smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    // Check all 5 tab labels
    expect(find.text('홈'), findsWidgets);
    expect(find.text('게시판1'), findsWidgets);
    expect(find.text('게시판2'), findsWidgets);
    expect(find.text('게시판3'), findsWidgets);
    expect(find.text('개인설정'), findsWidgets);
  });
}
