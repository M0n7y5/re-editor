import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

/// VSCode parity: with multiple carets active, editing/moving must not chase the
/// primary caret around the document (the viewport stayed put while typing).
/// Adding a caret (Ctrl+D / select-all-occurrences) must still reveal it.
///
/// These mount a real [CodeEditor] in a short viewport over a tall buffer so
/// any focus-scroll moves [CodeScrollController.verticalScroller] measurably.
/// Highlighting is left off (no `codeTheme`) to keep the test pure-Dart, and
/// the editor is never focused so the cursor-blink timer can't stall settle.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String longSource(int lines) =>
      List<String>.generate(lines, (int i) => 'line $i value;').join('\n');

  Future<CodeScrollController> pumpEditor(
    WidgetTester tester,
    CodeLineEditingController controller,
  ) async {
    final CodeScrollController scrollController = CodeScrollController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            height: 200,
            child: CodeEditor(
              controller: controller,
              scrollController: scrollController,
              style: const CodeEditorStyle(fontSize: 13, fontFamily: 'monospace'),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return scrollController;
  }

  group('multi-caret focus scroll', () {
    testWidgets('single caret far below the viewport is scrolled into view', (WidgetTester tester) async {
      final CodeLineEditingController controller =
          CodeLineEditingController.fromText(longSource(200));
      addTearDown(controller.dispose);
      final CodeScrollController sc = await pumpEditor(tester, controller);
      expect(sc.verticalScroller.offset, 0);

      controller.selection = const CodeLineSelection.collapsed(index: 150, offset: 0);
      controller.makeCursorVisible();
      await tester.pumpAndSettle();

      // Baseline: with a single caret the viewport still follows it.
      expect(sc.verticalScroller.offset, greaterThan(0));
    });

    testWidgets('multi-caret makeCursorVisible does not chase the primary caret', (WidgetTester tester) async {
      final CodeLineEditingController controller =
          CodeLineEditingController.fromText(longSource(200));
      addTearDown(controller.dispose);
      final CodeScrollController sc = await pumpEditor(tester, controller);

      // Two carets: an extra at the top, primary far below the viewport.
      controller.selection = const CodeLineSelection.collapsed(index: 0, offset: 0);
      controller.addSelection(const CodeLineSelection.collapsed(index: 150, offset: 0));
      expect(controller.selections.length, 2);
      // Drain the reveal-on-add scroll, then put the viewport back at the top.
      await tester.pumpAndSettle();
      sc.verticalScroller.jumpTo(0);
      await tester.pump();
      expect(sc.verticalScroller.offset, 0);

      controller.makeCursorVisible();
      await tester.pumpAndSettle();

      // Suppressed: the viewport did not jump to the far-below primary caret.
      expect(sc.verticalScroller.offset, 0);
    });

    testWidgets('adding a caret still reveals it (Ctrl+D parity)', (WidgetTester tester) async {
      final CodeLineEditingController controller =
          CodeLineEditingController.fromText(longSource(200));
      addTearDown(controller.dispose);
      final CodeScrollController sc = await pumpEditor(tester, controller);
      expect(sc.verticalScroller.offset, 0);

      controller.selection = const CodeLineSelection.collapsed(index: 0, offset: 0);
      controller.addSelection(const CodeLineSelection.collapsed(index: 150, offset: 0));
      await tester.pumpAndSettle();

      // _revealPrimaryCaret bypasses the multi-caret suppression on purpose.
      expect(sc.verticalScroller.offset, greaterThan(0));
    });

    testWidgets('typing at multiple carets does not scroll the viewport', (WidgetTester tester) async {
      final CodeLineEditingController controller =
          CodeLineEditingController.fromText(longSource(200));
      addTearDown(controller.dispose);
      final CodeScrollController sc = await pumpEditor(tester, controller);

      // Primary caret far below the viewport, an extra at the top.
      controller.selection = const CodeLineSelection.collapsed(index: 150, offset: 0);
      controller.addSelection(const CodeLineSelection.collapsed(index: 0, offset: 0));
      expect(controller.selections.length, 2);
      await tester.pumpAndSettle();
      sc.verticalScroller.jumpTo(0);
      await tester.pump();
      expect(sc.verticalScroller.offset, 0);

      // The real typing path: a multi-caret insert routes through _forEachCaret,
      // whose post-loop makeCursorVisible() is now suppressed.
      controller.replaceSelection('x');
      await tester.pumpAndSettle();

      // The edit landed at both carets, but the viewport stayed at the top.
      expect(controller.text.startsWith('xline 0 value;'), isTrue);
      expect(controller.text.contains('xline 150 value;'), isTrue);
      expect(sc.verticalScroller.offset, 0);
    });
  });
}
