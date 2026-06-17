import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('multi-cursor', () {
    test('replaceSelection inserts at 3 carets on 3 different lines', () {
      final CodeLineEditingController controller =
          CodeLineEditingController.fromText('aaa\nbbb\nccc');
      controller.selection = const CodeLineSelection.collapsed(index: 0, offset: 0);
      controller.addSelection(const CodeLineSelection.collapsed(index: 1, offset: 0));
      controller.addSelection(const CodeLineSelection.collapsed(index: 2, offset: 0));
      expect(controller.selections.length, 3);

      controller.replaceSelection('X');

      expect(controller.text, 'Xaaa\nXbbb\nXccc');
      expect(controller.selections.length, 3);
      // every caret advanced past the inserted 'X'
      expect(controller.selections.every((s) => s.extentOffset == 1), isTrue);
    });

    test('replaceSelection inserts at 2 carets on the same line (running delta)', () {
      final CodeLineEditingController controller =
          CodeLineEditingController.fromText('abcdef');
      controller.selection = const CodeLineSelection.collapsed(index: 0, offset: 1);
      controller.addSelection(const CodeLineSelection.collapsed(index: 0, offset: 4));
      expect(controller.selections.length, 2);

      controller.replaceSelection('X');

      // insert after original offset 1 and after original offset 4
      expect(controller.text, 'aXbcdXef');
      expect(controller.selections.length, 2);
    });

    test('deleteBackward removes one char per caret, offsets stay aligned', () {
      final CodeLineEditingController controller =
          CodeLineEditingController.fromText('aaa\nbbb\nccc');
      controller.selection = const CodeLineSelection.collapsed(index: 0, offset: 3);
      controller.addSelection(const CodeLineSelection.collapsed(index: 1, offset: 3));
      controller.addSelection(const CodeLineSelection.collapsed(index: 2, offset: 3));

      controller.deleteBackward();

      expect(controller.text, 'aa\nbb\ncc');
      expect(controller.selections.length, 3);
      expect(controller.selections.every((s) => s.extentOffset == 2), isTrue);
    });

    test('applyNewLine splits at each caret', () {
      final CodeLineEditingController controller =
          CodeLineEditingController.fromText('ab\ncd');
      controller.selection = const CodeLineSelection.collapsed(index: 0, offset: 1);
      controller.addSelection(const CodeLineSelection.collapsed(index: 1, offset: 1));

      controller.applyNewLine();

      expect(controller.text, 'a\nb\nc\nd');
      expect(controller.selections.length, 2);
    });

    test('a single undo reverts the whole multi-caret edit and restores the caret set', () {
      final CodeLineEditingController controller =
          CodeLineEditingController.fromText('aaa\nbbb');
      controller.selection = const CodeLineSelection.collapsed(index: 0, offset: 0);
      controller.addSelection(const CodeLineSelection.collapsed(index: 1, offset: 0));
      final String preText = controller.text;
      final int preCount = controller.selections.length;

      controller.replaceSelection('X');
      expect(controller.text, 'Xaaa\nXbbb');
      expect(controller.selections.length, 2);

      controller.undo();

      expect(controller.text, preText);
      expect(controller.selections.length, preCount);
    });

    test('carets that collapse onto the same position merge to one', () {
      final CodeLineEditingController controller =
          CodeLineEditingController.fromText('abc');
      controller.selection = const CodeLineSelection.collapsed(index: 0, offset: 1);
      controller.addSelection(const CodeLineSelection.collapsed(index: 0, offset: 2));
      expect(controller.selections.length, 2);

      controller.deleteBackward();

      // 'a' and 'b' deleted; both carets land at (0,0) and merge
      expect(controller.text, 'c');
      expect(controller.selections.length, 1);
    });

    test('clearSecondarySelections and set selection both collapse to the primary', () {
      final CodeLineEditingController controller =
          CodeLineEditingController.fromText('abc');
      controller.selection = const CodeLineSelection.collapsed(index: 0, offset: 0);
      controller.addSelection(const CodeLineSelection.collapsed(index: 0, offset: 1));
      expect(controller.selections.length, 2);

      controller.clearSecondarySelections();
      expect(controller.selections.length, 1);

      controller.addSelection(const CodeLineSelection.collapsed(index: 0, offset: 2));
      expect(controller.selections.length, 2);
      // assigning the selection collapses the caret set
      controller.selection = const CodeLineSelection.collapsed(index: 0, offset: 0);
      expect(controller.selections.length, 1);
    });

    test('addSelectionFromNextOccurrence selects the word then adds the next match', () {
      final CodeLineEditingController controller =
          CodeLineEditingController.fromText('foo bar foo');

      // collapsed caret inside the first "foo" -> selects the word
      controller.selection = const CodeLineSelection.collapsed(index: 0, offset: 1);
      controller.addSelectionFromNextOccurrence();
      expect(controller.selections.length, 1);
      expect(controller.selection.isCollapsed, isFalse);
      expect(controller.selectedText, 'foo');

      // second invocation adds a caret at the next "foo" (offset 8..11)
      controller.addSelectionFromNextOccurrence();
      expect(controller.selections.length, 2);
      expect(controller.selection.baseOffset, 8);
      expect(controller.selection.extentOffset, 11);
    });

    test('moveCursor moves every caret independently', () {
      final CodeLineEditingController controller =
          CodeLineEditingController.fromText('aaa\nbbb');
      controller.selection = const CodeLineSelection.collapsed(index: 0, offset: 0);
      controller.addSelection(const CodeLineSelection.collapsed(index: 1, offset: 0));

      controller.moveCursor(AxisDirection.right);

      expect(controller.selections.length, 2);
      expect(controller.selections.every((s) => s.extentOffset == 1), isTrue);
    });
  });

  group('multi-cursor input wiring', () {
    test('new caret shortcuts are defined and Ctrl/Cmd+D is rebound off lineDelete', () {
      expect(kCodeShortcutIntents[CodeShortcutType.addCaretNextOccurrence],
          isA<CodeShortcutAddCaretNextOccurrenceIntent>());
      final Intent? above = kCodeShortcutIntents[CodeShortcutType.addCaretAbove];
      expect(above, isA<CodeShortcutAddCaretIntent>());
      expect((above as CodeShortcutAddCaretIntent).above, isTrue);
      final Intent? below = kCodeShortcutIntents[CodeShortcutType.addCaretBelow];
      expect(below, isA<CodeShortcutAddCaretIntent>());
      expect((below as CodeShortcutAddCaretIntent).above, isFalse);

      const DefaultCodeShortcutsActivatorsBuilder builder =
          DefaultCodeShortcutsActivatorsBuilder();
      final List<ShortcutActivator>? nextOcc =
          builder.build(CodeShortcutType.addCaretNextOccurrence);
      expect((nextOcc!.first as SingleActivator).trigger, LogicalKeyboardKey.keyD);
      final SingleActivator belowAct =
          builder.build(CodeShortcutType.addCaretBelow)!.first as SingleActivator;
      expect(belowAct.trigger, LogicalKeyboardKey.arrowDown);
      expect(belowAct.alt, isTrue);
      final SingleActivator lineDelete =
          builder.build(CodeShortcutType.lineDelete)!.first as SingleActivator;
      expect(lineDelete.trigger, LogicalKeyboardKey.keyK);
    });

  });
}
