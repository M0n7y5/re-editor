import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

/// Whole-word matching, find in selection and `$n` group expansion in
/// replace. The search runs in an isolate, so each case waits for a result
/// rather than a duration.
void main() {
  /// Waits for the isolate's answer: `searching` is only raised by the
  /// toggles, so a fresh controller is settled once it holds a result.
  Future<void> settled(CodeFindController controller) async {
    for (int i = 0; i < 100; i++) {
      final CodeFindValue? value = controller.value;
      if (value != null && !value.searching && value.result != null) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('the search never answered');
  }

  Future<CodeFindController> search(
    CodeLineEditingController editing,
    CodeFindOption option,
  ) async {
    final CodeFindController controller = CodeFindController(
      editing,
      CodeFindValue(option: option, replaceMode: false),
    );
    await settled(controller);
    return controller;
  }

  List<(int, int, int)> spans(CodeFindController controller) =>
      <(int, int, int)>[
        for (final CodeLineSelection s
            in controller.allMatchSelections ?? const <CodeLineSelection>[])
          (s.startIndex, s.startOffset, s.endOffset),
      ];

  test('whole word skips a match inside a longer word', () async {
    final CodeLineEditingController editing =
        CodeLineEditingController.fromText('foo foobar barfoo foo.bar');
    final CodeFindController controller = await search(
      editing,
      const CodeFindOption(
        pattern: 'foo',
        caseSensitive: true,
        regex: false,
        wholeWord: true,
      ),
    );
    // Columns of the standalone `foo`s: 0 and 18.
    expect(spans(controller), <(int, int, int)>[(0, 0, 3), (0, 18, 21)]);
    controller.close();
    editing.dispose();
  });

  test('whole word applies to a regex pattern too', () async {
    final CodeLineEditingController editing =
        CodeLineEditingController.fromText('id1 xid2 id3x id4');
    final CodeFindController controller = await search(
      editing,
      const CodeFindOption(
        pattern: r'id\d',
        caseSensitive: true,
        regex: true,
        wholeWord: true,
      ),
    );
    expect(spans(controller), <(int, int, int)>[(0, 0, 3), (0, 14, 17)]);
    controller.close();
    editing.dispose();
  });

  test('find in selection keeps only matches inside the range', () async {
    final CodeLineEditingController editing =
        CodeLineEditingController.fromText('a\na\na\na');
    final CodeFindController controller = await search(
      editing,
      const CodeFindOption(
        pattern: 'a',
        caseSensitive: false,
        regex: false,
        range: CodeLineSelection(
          baseIndex: 1,
          baseOffset: 0,
          extentIndex: 2,
          extentOffset: 1,
        ),
      ),
    );
    expect(spans(controller), <(int, int, int)>[(1, 0, 1), (2, 0, 1)]);
    controller.close();
    editing.dispose();
  });

  test(
    'toggleInSelection captures the selection and clears on repeat',
    () async {
      final CodeLineEditingController editing =
          CodeLineEditingController.fromText('a\na\na\na');
      editing.selection = const CodeLineSelection(
        baseIndex: 2,
        baseOffset: 0,
        extentIndex: 3,
        extentOffset: 1,
      );
      final CodeFindController controller = await search(
        editing,
        const CodeFindOption(pattern: 'a', caseSensitive: false, regex: false),
      );
      expect(spans(controller).length, 4);

      controller.toggleInSelection();
      await settled(controller);
      expect(controller.value!.option.inSelection, isTrue);
      expect(spans(controller), <(int, int, int)>[(2, 0, 1), (3, 0, 1)]);

      controller.toggleInSelection();
      await settled(controller);
      expect(controller.value!.option.inSelection, isFalse);
      expect(spans(controller).length, 4);
      controller.close();
      editing.dispose();
    },
  );

  test(
    'replace all expands groups under regex and in the range only',
    () async {
      final CodeLineEditingController editing =
          CodeLineEditingController.fromText('x1\nx2\nx3');
      final CodeFindController controller = await search(
        editing,
        const CodeFindOption(
          pattern: r'x(\d)',
          caseSensitive: true,
          regex: true,
          range: CodeLineSelection(
            baseIndex: 1,
            baseOffset: 0,
            extentIndex: 2,
            extentOffset: 2,
          ),
        ),
      );
      controller.replaceInputController.text = r'y$1$$';
      controller.replaceAllMatches();

      expect(editing.text, 'x1\ny2\$\ny3\$');
      controller.close();
      editing.dispose();
    },
  );

  test(r'replace one expands groups; without regex `$1` is literal', () async {
    final CodeLineEditingController editing =
        CodeLineEditingController.fromText('ab ab');
    final CodeFindController regex = await search(
      editing,
      const CodeFindOption(pattern: '(a)(b)', caseSensitive: true, regex: true),
    );
    regex.replaceInputController.text = r'$2$1';
    regex.replaceMatch();
    expect(editing.text, 'ba ab');
    regex.close();

    final CodeFindController literal = await search(
      editing,
      const CodeFindOption(pattern: 'ab', caseSensitive: true, regex: false),
    );
    literal.replaceInputController.text = r'$1';
    literal.replaceMatch();
    expect(editing.text, r'ba $1');
    literal.close();
    editing.dispose();
  });

  test('expandMatchGroups drops a group the pattern lacks', () {
    final Match m = RegExp('(a)').firstMatch('a')!;
    expect(expandMatchGroups(r'<$0|$1|$2>', m), '<a|a|>');
  });
}
