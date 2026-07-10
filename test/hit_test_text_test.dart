import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const TextStyle editorTextStyle = TextStyle(
    fontSize: 13,
    fontFamily: 'monospace',
    height: 1.4,
  );

  Future<void> pumpEditor(
    WidgetTester tester,
    CodeLineEditingController controller,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              height: 200,
              child: CodeEditor(
                controller: controller,
                autofocus: false,
                style: const CodeEditorStyle(
                  fontSize: 13,
                  fontFamily: 'monospace',
                  fontHeight: 1.4,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('returns null when the controller is unattached', () {
    final CodeLineEditingController controller =
        CodeLineEditingController.fromText('hello world');
    addTearDown(controller.dispose);

    expect(controller.hitTestText(Offset.zero), isNull);
  });

  testWidgets('maps a mounted first-line text hit to line index zero', (
    WidgetTester tester,
  ) async {
    const String firstLine = 'hello world';
    final CodeLineEditingController controller =
        CodeLineEditingController.fromText('$firstLine\nsecond line');
    addTearDown(controller.dispose);
    await pumpEditor(tester, controller);

    final TextPainter painter = TextPainter(
      text: const TextSpan(text: firstLine, style: editorTextStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    addTearDown(painter.dispose);
    final Offset editorTopLeft = tester.getTopLeft(find.byType(CodeEditor));
    final Offset firstLineTextCenter =
        editorTopLeft + Offset(5 + painter.width / 2, 5 + painter.height / 2);

    expect(
      controller.hitTestText(firstLineTextCenter),
      isA<CodeLinePosition>().having(
        (CodeLinePosition position) => position.index,
        'index',
        0,
      ),
    );
  });

  testWidgets('returns null for a global point outside the editor rect', (
    WidgetTester tester,
  ) async {
    final CodeLineEditingController controller =
        CodeLineEditingController.fromText('hello world\nsecond line');
    addTearDown(controller.dispose);
    await pumpEditor(tester, controller);

    final Rect editorRect = tester.getRect(find.byType(CodeEditor));
    final Offset outside = editorRect.topLeft - const Offset(1, 1);

    expect(controller.hitTestText(outside), isNull);
  });
}
