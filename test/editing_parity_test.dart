import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

void main() {
  final TestWidgetsFlutterBinding binding = TestWidgetsFlutterBinding.ensureInitialized();

  // Capture clipboard writes so multi-caret copy/cut can be asserted without a
  // real platform clipboard.
  String? clipboardText;
  setUp(() {
    clipboardText = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform,
        (MethodCall call) async {
      if (call.method == 'Clipboard.setData') {
        clipboardText = (call.arguments as Map)['text'] as String?;
      }
      if (call.method == 'Clipboard.getData') {
        return <String, Object?>{'text': clipboardText};
      }
      return null;
    });
  });
  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('deleteForward smart pair', () {
    test('deletes both symbols when the caret sits between a closure pair', () {
      final CodeLineEditingController controller = CodeLineEditingController(
        codeLines: CodeLines.of(const [CodeLine('abc{}')]),
      );
      controller.selection = const CodeLineSelection.collapsed(index: 0, offset: 4);
      controller.deleteForward();
      expect(controller.codeLines, CodeLines.of(const [CodeLine('abc')]));
      expect(controller.selection, const CodeLineSelection.collapsed(index: 0, offset: 3));
    });

    test('deletes a single character when not between a pair', () {
      final CodeLineEditingController controller = CodeLineEditingController(
        codeLines: CodeLines.of(const [CodeLine('ab')]),
      );
      controller.selection = const CodeLineSelection.collapsed(index: 0, offset: 1);
      controller.deleteForward();
      expect(controller.codeLines, CodeLines.of(const [CodeLine('a')]));
      expect(controller.selection, const CodeLineSelection.collapsed(index: 0, offset: 1));
    });
  });

  group('duplicate selection lines', () {
    test('down duplicates below and moves the caret onto the lower copy', () {
      final CodeLineEditingController controller = CodeLineEditingController(
        codeLines: CodeLines.of(const [CodeLine('a'), CodeLine('b')]),
      );
      controller.selection = const CodeLineSelection.collapsed(index: 0, offset: 0);
      controller.duplicateSelectionLinesDown();
      expect(controller.codeLines,
          CodeLines.of(const [CodeLine('a'), CodeLine('a'), CodeLine('b')]));
      expect(controller.selection, const CodeLineSelection.collapsed(index: 1, offset: 0));
    });

    test('up duplicates below but keeps the caret on the upper copy', () {
      final CodeLineEditingController controller = CodeLineEditingController(
        codeLines: CodeLines.of(const [CodeLine('a'), CodeLine('b')]),
      );
      controller.selection = const CodeLineSelection.collapsed(index: 0, offset: 0);
      controller.duplicateSelectionLinesUp();
      expect(controller.codeLines,
          CodeLines.of(const [CodeLine('a'), CodeLine('a'), CodeLine('b')]));
      expect(controller.selection, const CodeLineSelection.collapsed(index: 0, offset: 0));
    });

    test('a single undo reverts the duplication', () {
      final CodeLineEditingController controller = CodeLineEditingController(
        codeLines: CodeLines.of(const [CodeLine('a'), CodeLine('b')]),
      );
      controller.selection = const CodeLineSelection.collapsed(index: 0, offset: 0);
      controller.duplicateSelectionLinesDown();
      controller.undo();
      expect(controller.codeLines, CodeLines.of(const [CodeLine('a'), CodeLine('b')]));
    });
  });

  group('selectAllOccurrences', () {
    test('selects every occurrence of the word under a collapsed caret', () {
      final CodeLineEditingController controller =
          CodeLineEditingController.fromText('foo bar foo');
      controller.selection = const CodeLineSelection.collapsed(index: 0, offset: 1);
      controller.selectAllOccurrences();
      expect(controller.selections.length, 2);
      final Set<(int, int, int, int)> ranges = controller.selections
          .map((CodeLineSelection s) =>
              (s.startIndex, s.startOffset, s.endIndex, s.endOffset))
          .toSet();
      expect(ranges, <(int, int, int, int)>{(0, 0, 0, 3), (0, 8, 0, 11)});
    });

    test('is a no-op when the caret is not adjacent to a word', () {
      final CodeLineEditingController controller = CodeLineEditingController(
        codeLines: CodeLines.of(const [CodeLine('a  b')]),
      );
      controller.selection = const CodeLineSelection.collapsed(index: 0, offset: 2);
      controller.selectAllOccurrences();
      expect(controller.selections.length, 1);
      expect(controller.selection, const CodeLineSelection.collapsed(index: 0, offset: 2));
    });
  });

  group('multi-caret cut', () {
    test('cuts every ranged caret and a single undo restores them', () async {
      final CodeLineEditingController controller =
          CodeLineEditingController.fromText('foo bar foo');
      controller.selection = const CodeLineSelection.collapsed(index: 0, offset: 1);
      controller.selectAllOccurrences();
      expect(controller.selections.length, 2);
      controller.cut();
      expect(controller.codeLines, CodeLines.of(const [CodeLine(' bar ')]));
      await pumpEventQueue();
      expect(clipboardText, 'foo\nfoo');
      controller.undo();
      expect(controller.codeLines, CodeLines.of(const [CodeLine('foo bar foo')]));
    });
  });

  group('findMatchingBracketHighlights', () {
    test('matches the bracket adjacent to the caret with its partner', () {
      final List<CodeLineSelection> result = findMatchingBracketHighlights(
        CodeLines.of(const [CodeLine('(a[b]c)')]),
        const CodeLineSelection.collapsed(index: 0, offset: 1),
      );
      expect(result.length, 2);
      final Set<(int, int)> ranges = result
          .map((CodeLineSelection s) => (s.startOffset, s.endOffset))
          .toSet();
      expect(ranges, <(int, int)>{(0, 1), (6, 7)});
    });

    test('returns nothing when the caret is not adjacent to a bracket', () {
      final List<CodeLineSelection> result = findMatchingBracketHighlights(
        CodeLines.of(const [CodeLine('abc')]),
        const CodeLineSelection.collapsed(index: 0, offset: 1),
      );
      expect(result, isEmpty);
    });

    test('returns nothing for an unbalanced bracket', () {
      final List<CodeLineSelection> result = findMatchingBracketHighlights(
        CodeLines.of(const [CodeLine('(a')]),
        const CodeLineSelection.collapsed(index: 0, offset: 1),
      );
      expect(result, isEmpty);
    });
  });
}
