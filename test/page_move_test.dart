import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

/// PageUp / PageDown move the caret by one viewport of rows and keep its
/// column; with Shift they extend the selection. The editor is 200 px tall
/// with a 13 px font, so the viewport holds a known number of rows, read
/// from the first move rather than assumed, and the second move must agree.
///
/// The platform is forced to linux before the first editor builds (re_editor
/// caches the flag; the android default drops the desktop bindings) and
/// cleared inside the body, before the leak check.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String source(int lines) =>
      List<String>.generate(lines, (int i) => i == 5 ? 'x' : 'line $i value;')
          .join('\n');

  late CodeLineEditingController controller;
  late CodeScrollController scrollController;

  Future<void> pumpEditor(WidgetTester tester) async {
    controller = CodeLineEditingController.fromText(source(200));
    scrollController = CodeScrollController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            height: 200,
            child: CodeEditor(
              controller: controller,
              scrollController: scrollController,
              autofocus: true,
              style: const CodeEditorStyle(fontSize: 13, fontFamily: 'monospace'),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  void editorTest(
    String description,
    Future<void> Function(WidgetTester tester) body,
  ) {
    testWidgets(description, (WidgetTester tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        await pumpEditor(tester);
        await body(tester);
      } finally {
        FocusManager.instance.primaryFocus?.unfocus();
        // A scroll starts the scrollbar's fade-out timer.
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        controller.dispose();
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  editorTest('PageDown moves by a viewport of rows and keeps the column',
      (WidgetTester tester) async {
    controller.selection =
        const CodeLineSelection.collapsed(index: 0, offset: 7);

    controller.moveCursorToPageDown();
    await tester.pump();
    final int rows = controller.selection.extentIndex;
    expect(rows, greaterThan(5), reason: '200 px holds more than 5 rows');
    expect(rows, lessThan(20));
    expect(controller.selection.extentOffset, 7,
        reason: "line 5 is 'x'; the column is the start row's, not its");
    expect(scrollController.verticalScroller.offset, greaterThan(0),
        reason: 'the viewport scrolled with the caret');

    controller.moveCursorToPageDown();
    await tester.pump();
    expect(controller.selection.extentIndex, 2 * rows);
    expect(controller.selection.extentOffset, 7);

    controller.moveCursorToPageUp();
    await tester.pump();
    expect(controller.selection.extentIndex, rows);
  });

  editorTest('PageUp near the top stops on the first row, column kept', (
    WidgetTester tester,
  ) async {
    controller.selection =
        const CodeLineSelection.collapsed(index: 3, offset: 4);

    controller.moveCursorToPageUp();
    await tester.pump();

    expect(controller.selection,
        const CodeLineSelection.collapsed(index: 0, offset: 4));
  });

  editorTest('PageDown through the keyboard moves the caret', (
    WidgetTester tester,
  ) async {
    controller.selection =
        const CodeLineSelection.collapsed(index: 2, offset: 3);

    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pump();

    expect(controller.selection.isCollapsed, isTrue);
    expect(controller.selection.extentIndex, greaterThan(7));
    expect(controller.selection.extentOffset, 3);
  });

  editorTest('Shift+PageDown through the keyboard extends the selection', (
    WidgetTester tester,
  ) async {
    controller.selection =
        const CodeLineSelection.collapsed(index: 2, offset: 3);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(controller.selection.baseIndex, 2);
    expect(controller.selection.baseOffset, 3);
    expect(controller.selection.extentIndex, greaterThan(7));
    expect(controller.selection.extentOffset, 3);
  });
}
