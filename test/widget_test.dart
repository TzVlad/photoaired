import 'package:flutter_test/flutter_test.dart';
import 'package:photoaired/main.dart';

void main() {
  testWidgets('PhotoEditorApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const PhotoEditorApp());
    expect(find.byType(PhotoEditorApp), findsOneWidget);
  });
}
