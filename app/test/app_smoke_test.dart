import 'package:flutter_test/flutter_test.dart';
import 'package:noteapp/main.dart';

void main() {
  testWidgets('placeholder app shows the foundation message', (tester) async {
    await tester.pumpWidget(const NoteAppPlaceholder());
    expect(find.text(NoteAppPlaceholder.message), findsOneWidget);
  });
}
