import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

/// The semantic overlay ([CodeSemanticOverlayController]) is the editor's
/// second span source: where it covers a line, its style replaces the
/// tree-sitter style for exactly those code units, and the grammar layer fills
/// everything else with its own nodes split as needed.
///
/// These tests drive the real pipeline — a real `CodeEditor` over real Dart
/// source, so the grammar layer produces real nodes — and read the merged
/// result off the paragraphs the render object laid out. `_ParagraphImpl.span`
/// is the exact [TextSpan] that was painted, so its children are the merged
/// runs, colour included.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Deliberately garish and unrelated to any real palette: every assertion
  // below names a colour, and none of them may be confusable with another.
  const Color typeColor = Color(0xFF00FF00);
  const Color functionColor = Color(0xFF0000FF);
  const Color parameterColor = Color(0xFFFF0000);
  const Color memberColor = Color(0xFFFF00FF);
  const CodeHighlightTheme theme = CodeHighlightTheme(
    theme: <String, TextStyle>{
      'type': TextStyle(color: typeColor),
      'function': TextStyle(color: functionColor),
      'parameter': TextStyle(color: parameterColor),
      'enumMember': TextStyle(color: memberColor),
    },
  );

  /// Two byte-identical body lines, which is what the aliasing test needs, and
  /// enough grammar variety that a run boundary means something.
  const String twinSource = 'class A {\n'
      '  int run(int alpha) => alpha;\n'
      '  int run(int alpha) => alpha;\n'
      '}';
  const String twinLine = '  int run(int alpha) => alpha;';

  Future<CodeSemanticOverlayController> pumpEditor(
    WidgetTester tester, {
    required CodeLineEditingController controller,
    required CodeSemanticOverlayController overlay,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 600,
            height: 240,
            child: CodeEditor(
              controller: controller,
              semanticOverlay: overlay,
              autofocus: false,
              wordWrap: false,
              style: const CodeEditorStyle(
                fontSize: 13,
                fontFamily: 'monospace',
                fontHeight: 1.4,
                codeTheme: theme,
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return overlay;
  }

  /// The code field render object, found by name as it is library private.
  RenderObject codeFieldRender(WidgetTester tester) {
    RenderObject? found;
    void visit(RenderObject object) {
      if (found != null) {
        return;
      }
      if (object.runtimeType.toString() == '_CodeFieldRender') {
        found = object;
        return;
      }
      object.visitChildren(visit);
    }
    visit(tester.renderObject(find.byType(CodeEditor)));
    expect(found, isNotNull, reason: 'the code field render object is gone');
    return found!;
  }

  /// The painted runs of absolute line [index]: the text of each child span of
  /// the paragraph, paired with the colour it resolved to (null = the editor's
  /// base style, i.e. no theme entry matched).
  List<(String, Color?)> runsOf(WidgetTester tester, int index) {
    final List<CodeLineRenderParagraph> paragraphs =
        // ignore: avoid_dynamic_calls
        (codeFieldRender(tester) as dynamic).displayParagraphs
            as List<CodeLineRenderParagraph>;
    final CodeLineRenderParagraph line = paragraphs.firstWhere(
      (CodeLineRenderParagraph p) => p.index == index,
      orElse: () => throw StateError('line $index is not displayed'),
    );
    // ignore: avoid_dynamic_calls
    final TextSpan span = (line.paragraph as dynamic).span as TextSpan;
    return <(String, Color?)>[
      for (final InlineSpan child in span.children ?? const <InlineSpan>[])
        ((child as TextSpan).text ?? '', child.style?.color),
    ];
  }

  /// Pumps until the grammar worker's answer for [index] has landed.
  ///
  /// The worker is a real isolate, so its reply rides the real event loop and
  /// is invisible to the fake clock `testWidgets` runs on: only
  /// [WidgetTester.runAsync] lets it be delivered at all.
  Future<void> awaitGrammar(WidgetTester tester, int index) async {
    for (int i = 0; i < 200; i++) {
      if (runsOf(tester, index)
          .any(((String, Color?) run) => run.$2 != null)) {
        return;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    fail('the grammar layer never coloured line $index');
  }

  /// The colour painted at code unit [offset] of line [index].
  Color? colorAt(WidgetTester tester, int index, int offset) {
    int cursor = 0;
    for (final (String text, Color? color) in runsOf(tester, index)) {
      if (offset < cursor + text.length) {
        return color;
      }
      cursor += text.length;
    }
    fail('offset $offset is past the end of line $index');
  }

  group('CodeSemanticOverlayController', () {
    test('drops empty spans and orders a line by start offset', () {
      final CodeSemanticOverlayController overlay =
          CodeSemanticOverlayController();
      addTearDown(overlay.dispose);

      overlay.value = <int, List<CodeSemanticSpan>>{
        0: <CodeSemanticSpan>[
          const CodeSemanticSpan(start: 10, end: 14, style: 'type'),
          const CodeSemanticSpan(start: 4, end: 4, style: 'function'),
          const CodeSemanticSpan(start: 0, end: 3, style: 'parameter'),
        ],
        1: const <CodeSemanticSpan>[],
      };

      expect(overlay.spansForLine(0), <CodeSemanticSpan>[
        const CodeSemanticSpan(start: 0, end: 3, style: 'parameter'),
        const CodeSemanticSpan(start: 10, end: 14, style: 'type'),
      ]);
      expect(overlay.spansForLine(1), isNull,
          reason: 'a line with no usable spans is not in the map at all');
    });

    test('trims overlapping spans so the earlier one keeps its text', () {
      final CodeSemanticOverlayController overlay =
          CodeSemanticOverlayController(<int, List<CodeSemanticSpan>>{
        0: <CodeSemanticSpan>[
          const CodeSemanticSpan(start: 0, end: 6, style: 'type'),
          const CodeSemanticSpan(start: 3, end: 9, style: 'function'),
          const CodeSemanticSpan(start: 4, end: 5, style: 'parameter'),
        ],
      });
      addTearDown(overlay.dispose);

      expect(overlay.spansForLine(0), <CodeSemanticSpan>[
        const CodeSemanticSpan(start: 0, end: 6, style: 'type'),
        const CodeSemanticSpan(start: 6, end: 9, style: 'function'),
      ]);
    });

    test('notifies only when the normalized overlay differs', () {
      final CodeSemanticOverlayController overlay =
          CodeSemanticOverlayController();
      addTearDown(overlay.dispose);
      int notifications = 0;
      overlay.addListener(() => notifications++);

      overlay.value = <int, List<CodeSemanticSpan>>{
        2: <CodeSemanticSpan>[
          const CodeSemanticSpan(start: 0, end: 4, style: 'type'),
        ],
      };
      expect(notifications, 1);

      // Same spans, different list instances and a dropped empty one.
      overlay.value = <int, List<CodeSemanticSpan>>{
        2: <CodeSemanticSpan>[
          const CodeSemanticSpan(start: 0, end: 4, style: 'type'),
          const CodeSemanticSpan(start: 7, end: 7, style: 'function'),
        ],
      };
      expect(notifications, 1, reason: 'nothing about the overlay changed');

      overlay.clear();
      expect(notifications, 2);
      expect(overlay.isEmpty, isTrue);
    });
  });

  testWidgets('an overlay span inside one grammar token splits it in three',
      (WidgetTester tester) async {
    final CodeLineEditingController controller =
        CodeLineEditingController.fromText(twinSource);
    addTearDown(controller.dispose);
    final CodeSemanticOverlayController overlay =
        CodeSemanticOverlayController();
    addTearDown(overlay.dispose);

    await pumpEditor(tester, controller: controller, overlay: overlay);
    await awaitGrammar(tester, 1);
    expect(colorAt(tester, 1, 6), functionColor,
        reason: 'the grammar layer calls `run` a function');

    // `u`, the middle character of `run` (offsets 6..9).
    overlay.value = <int, List<CodeSemanticSpan>>{
      1: <CodeSemanticSpan>[
        const CodeSemanticSpan(start: 7, end: 8, style: 'parameter'),
      ],
    };
    await tester.pump();

    expect(colorAt(tester, 1, 6), functionColor);
    expect(colorAt(tester, 1, 7), parameterColor);
    expect(colorAt(tester, 1, 8), functionColor);
    expect(
      runsOf(tester, 1).map(((String, Color?) r) => r.$1).join(),
      twinLine,
      reason: 'the merged runs must still concatenate to the line',
    );
  });

  testWidgets('an overlay span reaching across grammar tokens swallows them',
      (WidgetTester tester) async {
    final CodeLineEditingController controller =
        CodeLineEditingController.fromText(twinSource);
    addTearDown(controller.dispose);
    final CodeSemanticOverlayController overlay =
        CodeSemanticOverlayController();
    addTearDown(overlay.dispose);

    await pumpEditor(tester, controller: controller, overlay: overlay);
    await awaitGrammar(tester, 1);
    expect(colorAt(tester, 1, 2), typeColor, reason: '`int` is a builtin type');
    expect(colorAt(tester, 1, 6), functionColor);

    // `int run(` — three grammar tokens plus the gap between them.
    overlay.value = <int, List<CodeSemanticSpan>>{
      1: <CodeSemanticSpan>[
        const CodeSemanticSpan(start: 2, end: 10, style: 'enumMember'),
      ],
    };
    await tester.pump();

    for (int offset = 2; offset < 10; offset++) {
      expect(colorAt(tester, 1, offset), memberColor,
          reason: 'offset $offset is inside the overlay span');
    }
    expect(colorAt(tester, 1, 1), isNull, reason: 'leading indent is untouched');
    expect(colorAt(tester, 1, 10), typeColor,
        reason: 'the second `int` keeps its grammar colour');
  });

  testWidgets('an overlay span covering the whole line replaces every style',
      (WidgetTester tester) async {
    final CodeLineEditingController controller =
        CodeLineEditingController.fromText(twinSource);
    addTearDown(controller.dispose);
    final CodeSemanticOverlayController overlay =
        CodeSemanticOverlayController();
    addTearDown(overlay.dispose);

    await pumpEditor(tester, controller: controller, overlay: overlay);
    await awaitGrammar(tester, 1);

    // Deliberately longer than the line: a span left over from a wider
    // revision must be clipped, not throw.
    overlay.value = <int, List<CodeSemanticSpan>>{
      1: <CodeSemanticSpan>[
        CodeSemanticSpan(
          start: 0,
          end: twinLine.length + 40,
          style: 'parameter',
        ),
      ],
    };
    await tester.pump();

    expect(tester.takeException(), isNull);
    final List<(String, Color?)> runs = runsOf(tester, 1);
    // The grammar node boundaries survive — the merge splits, it does not
    // coalesce — but not one of them keeps its own colour.
    expect(runs.map(((String, Color?) r) => r.$1).join(), twinLine);
    expect(
      runs.map(((String, Color?) r) => r.$2).toSet(),
      <Color>{parameterColor},
    );
  });

  testWidgets('an empty overlay leaves the grammar spans exactly as they were',
      (WidgetTester tester) async {
    final CodeLineEditingController controller =
        CodeLineEditingController.fromText(twinSource);
    addTearDown(controller.dispose);
    final CodeSemanticOverlayController overlay =
        CodeSemanticOverlayController();
    addTearDown(overlay.dispose);

    await pumpEditor(tester, controller: controller, overlay: overlay);
    await awaitGrammar(tester, 1);
    final List<(String, Color?)> grammar = runsOf(tester, 1);

    overlay.value = <int, List<CodeSemanticSpan>>{
      1: <CodeSemanticSpan>[
        const CodeSemanticSpan(start: 6, end: 9, style: 'parameter'),
      ],
    };
    await tester.pump();
    expect(runsOf(tester, 1), isNot(grammar));

    overlay.clear();
    await tester.pump();
    expect(runsOf(tester, 1), grammar);
  });

  testWidgets(
      'byte-identical lines with different overlays render differently',
      (WidgetTester tester) async {
    // The E3 aliasing regression. The highlighter keeps a text-keyed cache of
    // grammar results so a line that only shifted index does not flash, and
    // these two lines are byte-identical — so they legitimately share that
    // entry. Their *semantic* classifications, however, are per line: two
    // `run(int alpha)` declarations can resolve to different symbols. The
    // merge therefore happens per absolute line index, after the cache
    // lookup, and the overlay is never written into any cache. Bake it in and
    // this test paints both lines with whichever colour was seen first.
    final CodeLineEditingController controller =
        CodeLineEditingController.fromText(twinSource);
    addTearDown(controller.dispose);
    final CodeSemanticOverlayController overlay =
        CodeSemanticOverlayController();
    addTearDown(overlay.dispose);

    await pumpEditor(tester, controller: controller, overlay: overlay);
    await awaitGrammar(tester, 1);
    await awaitGrammar(tester, 2);
    expect(
      controller.codeLines[1].text,
      controller.codeLines[2].text,
      reason: 'the premise of this test is two identical line strings',
    );
    expect(runsOf(tester, 1), runsOf(tester, 2),
        reason: 'identical text means identical grammar colours');

    // `alpha`, the parameter, at offsets 14..19 of both lines.
    overlay.value = <int, List<CodeSemanticSpan>>{
      1: <CodeSemanticSpan>[
        const CodeSemanticSpan(start: 14, end: 19, style: 'parameter'),
      ],
      2: <CodeSemanticSpan>[
        const CodeSemanticSpan(start: 14, end: 19, style: 'enumMember'),
      ],
    };
    await tester.pump();

    expect(colorAt(tester, 1, 14), parameterColor);
    expect(colorAt(tester, 2, 14), memberColor);
    expect(runsOf(tester, 1), isNot(runsOf(tester, 2)));
  });

  testWidgets('an overlay line and its unadorned twin do not alias either',
      (WidgetTester tester) async {
    final CodeLineEditingController controller =
        CodeLineEditingController.fromText(twinSource);
    addTearDown(controller.dispose);
    final CodeSemanticOverlayController overlay =
        CodeSemanticOverlayController();
    addTearDown(overlay.dispose);

    await pumpEditor(tester, controller: controller, overlay: overlay);
    await awaitGrammar(tester, 1);
    await awaitGrammar(tester, 2);
    final List<(String, Color?)> grammar = runsOf(tester, 2);

    overlay.value = <int, List<CodeSemanticSpan>>{
      1: <CodeSemanticSpan>[
        const CodeSemanticSpan(start: 14, end: 19, style: 'enumMember'),
      ],
    };
    await tester.pump();

    expect(colorAt(tester, 1, 14), memberColor);
    expect(runsOf(tester, 2), grammar,
        reason: 'the twin carries no overlay and must keep grammar colours');
  });

  testWidgets('an overlay change repaints without re-running the highlighter',
      (WidgetTester tester) async {
    // A grammar re-highlight is an isolate round trip: it cannot possibly
    // complete inside one synchronous frame. So "the new colours are on screen
    // after a single `pump()` with no elapsed time, and the untouched lines
    // still carry their grammar colours" is exactly the statement that the
    // repaint came from the merge and not from the worker.
    final CodeLineEditingController controller =
        CodeLineEditingController.fromText(twinSource);
    addTearDown(controller.dispose);
    final CodeSemanticOverlayController overlay =
        CodeSemanticOverlayController();
    addTearDown(overlay.dispose);

    await pumpEditor(tester, controller: controller, overlay: overlay);
    await awaitGrammar(tester, 1);
    final List<(String, Color?)> untouched = runsOf(tester, 2);

    overlay.value = <int, List<CodeSemanticSpan>>{
      1: <CodeSemanticSpan>[
        const CodeSemanticSpan(start: 2, end: 5, style: 'parameter'),
      ],
    };
    await tester.pump(Duration.zero);

    expect(colorAt(tester, 1, 2), parameterColor,
        reason: 'one frame, no elapsed time: the merge did this, not a worker');
    expect(runsOf(tester, 2), untouched,
        reason: 'the grammar layer was not recomputed or dropped');
  });

  testWidgets('swapping the overlay controller repaints with its spans',
      (WidgetTester tester) async {
    final CodeLineEditingController controller =
        CodeLineEditingController.fromText(twinSource);
    addTearDown(controller.dispose);
    final CodeSemanticOverlayController first =
        CodeSemanticOverlayController(<int, List<CodeSemanticSpan>>{
      1: <CodeSemanticSpan>[
        const CodeSemanticSpan(start: 2, end: 5, style: 'parameter'),
      ],
    });
    addTearDown(first.dispose);
    final CodeSemanticOverlayController second =
        CodeSemanticOverlayController(<int, List<CodeSemanticSpan>>{
      1: <CodeSemanticSpan>[
        const CodeSemanticSpan(start: 2, end: 5, style: 'enumMember'),
      ],
    });
    addTearDown(second.dispose);

    await pumpEditor(tester, controller: controller, overlay: first);
    await awaitGrammar(tester, 1);
    expect(colorAt(tester, 1, 2), parameterColor);

    await pumpEditor(tester, controller: controller, overlay: second);
    expect(colorAt(tester, 1, 2), memberColor);

    // A controller the editor no longer points at must not repaint it.
    first.clear();
    await tester.pump();
    expect(colorAt(tester, 1, 2), memberColor);
  });
}
