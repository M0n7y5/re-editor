import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

/// Decorations ([CodeDecorationController]) are painted by two extra painters
/// adopted by the code field render object, one per layer. Mutating the
/// controller must repaint those layers only: no widget rebuild, no relayout
/// of the text, no highlighter invalidation.
///
/// The painters are private, so these tests replay the paint of the render
/// layers into a [TestRecordingCanvas] and inspect the display list. A wavy
/// underline is a `drawPath` call, a tint is a `drawRect` call.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const CodeDecorationStyle squiggle = CodeDecorationStyle(
    underlineColor: Color(0xFFFF0000),
  );

  String source(int lines) =>
      List<String>.generate(lines, (int i) => 'line $i value;').join('\n');

  Future<void> pumpEditor(
    WidgetTester tester,
    CodeLineEditingController controller,
    CodeDecorationController? decorations, {
    CodeScrollController? scrollController,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            height: 200,
            child: CodeEditor(
              controller: controller,
              decorations: decorations,
              scrollController: scrollController,
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
    ));
    await tester.pumpAndSettle();
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

  /// The background and foreground extra layers of the code field.
  List<RenderObject> extraLayers(WidgetTester tester) {
    final List<RenderObject> layers = <RenderObject>[];
    codeFieldRender(tester).visitChildren(layers.add);
    expect(layers, hasLength(2));
    return layers;
  }

  /// Every canvas call recorded while replaying the paint of both extra layers.
  List<RecordedInvocation> replayLayerPaint(WidgetTester tester) {
    final TestRecordingCanvas canvas = TestRecordingCanvas();
    final TestRecordingPaintingContext context = TestRecordingPaintingContext(canvas);
    for (final RenderObject layer in extraLayers(tester)) {
      layer.paint(context, Offset.zero);
    }
    return canvas.invocations;
  }

  List<Invocation> callsTo(WidgetTester tester, Symbol member) {
    return replayLayerPaint(tester)
        .map((RecordedInvocation call) => call.invocation)
        .where((Invocation invocation) => invocation.memberName == member)
        .toList();
  }

  testWidgets('paints a wavy underline for a decorated range', (WidgetTester tester) async {
    final CodeLineEditingController controller =
        CodeLineEditingController.fromText(source(4));
    addTearDown(controller.dispose);
    final CodeDecorationController decorations = CodeDecorationController(
      <CodeDecoration>[
        const CodeDecoration(
          range: CodeLineSelection(
            baseIndex: 1,
            baseOffset: 0,
            extentIndex: 1,
            extentOffset: 4,
          ),
          style: squiggle,
        ),
      ],
    );
    addTearDown(decorations.dispose);

    await pumpEditor(tester, controller, decorations);

    expect(tester.takeException(), isNull);
    final List<Invocation> paths = callsTo(tester, #drawPath);
    expect(paths, hasLength(1));
    final Rect bounds = (paths.single.positionalArguments[0] as Path).getBounds();
    expect(bounds.width, greaterThan(4));
    expect(bounds.height, greaterThan(0), reason: 'the underline must be wavy');
  });

  testWidgets('paints one underline per line of a multi line range', (WidgetTester tester) async {
    final CodeLineEditingController controller =
        CodeLineEditingController.fromText(source(4));
    addTearDown(controller.dispose);
    final CodeDecorationController decorations = CodeDecorationController(
      <CodeDecoration>[
        const CodeDecoration(
          range: CodeLineSelection(
            baseIndex: 0,
            baseOffset: 2,
            extentIndex: 2,
            extentOffset: 3,
          ),
          style: squiggle,
        ),
      ],
    );
    addTearDown(decorations.dispose);

    await pumpEditor(tester, controller, decorations);

    expect(callsTo(tester, #drawPath), hasLength(3));
  });

  testWidgets('paints a tint below the text and an underline above it', (WidgetTester tester) async {
    final CodeLineEditingController controller =
        CodeLineEditingController.fromText(source(4));
    addTearDown(controller.dispose);
    final CodeDecorationController decorations = CodeDecorationController(
      <CodeDecoration>[
        const CodeDecoration(
          range: CodeLineSelection(
            baseIndex: 0,
            baseOffset: 0,
            extentIndex: 0,
            extentOffset: 4,
          ),
          style: CodeDecorationStyle(
            underlineColor: Color(0xFFFF0000),
            backgroundColor: Color(0x22FF0000),
          ),
        ),
      ],
    );
    addTearDown(decorations.dispose);

    await pumpEditor(tester, controller, decorations);

    final List<RenderObject> layers = extraLayers(tester);
    // Foreground first, background second, see _CodeFieldRender.visitChildren.
    final TestRecordingCanvas foreground = TestRecordingCanvas();
    layers.first.paint(TestRecordingPaintingContext(foreground), Offset.zero);
    final TestRecordingCanvas background = TestRecordingCanvas();
    layers.last.paint(TestRecordingPaintingContext(background), Offset.zero);

    expect(
      foreground.invocations
          .where((RecordedInvocation call) => call.invocation.memberName == #drawPath),
      hasLength(1),
    );
    expect(
      background.invocations
          .where((RecordedInvocation call) => call.invocation.memberName == #drawRect),
      hasLength(1),
    );
  });

  testWidgets('mutating the controller repaints the layers only', (WidgetTester tester) async {
    final CodeLineEditingController controller =
        CodeLineEditingController.fromText(source(4));
    addTearDown(controller.dispose);
    final CodeDecorationController decorations = CodeDecorationController();
    addTearDown(decorations.dispose);

    await pumpEditor(tester, controller, decorations);
    expect(callsTo(tester, #drawPath), isEmpty);

    final Element editor = find.byType(CodeEditor).evaluate().single;
    final RenderObject field = codeFieldRender(tester);
    final List<RenderObject> layers = extraLayers(tester);

    decorations.value = <CodeDecoration>[
      const CodeDecoration(
        range: CodeLineSelection(
          baseIndex: 0,
          baseOffset: 0,
          extentIndex: 0,
          extentOffset: 4,
        ),
        style: squiggle,
      ),
    ];

    expect(editor.dirty, isFalse, reason: 'the editor must not be rebuilt');
    expect(field.debugNeedsLayout, isFalse, reason: 'the text must not be relaid out');
    expect(field.debugNeedsPaint, isFalse, reason: 'the text must not be repainted');
    for (final RenderObject layer in layers) {
      expect(layer.debugNeedsPaint, isTrue);
    }

    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(callsTo(tester, #drawPath), hasLength(1));
  });

  testWidgets('a zero width range still paints a visible underline', (WidgetTester tester) async {
    final CodeLineEditingController controller =
        CodeLineEditingController.fromText('line 0 value;\n\nline 2 value;');
    addTearDown(controller.dispose);
    final CodeDecorationController decorations = CodeDecorationController(
      <CodeDecoration>[
        // Collapsed inside a line of text.
        const CodeDecoration(
          range: CodeLineSelection.collapsed(index: 0, offset: 3),
          style: squiggle,
        ),
        // Collapsed on an empty line, nothing to measure.
        const CodeDecoration(
          range: CodeLineSelection.collapsed(index: 1, offset: 0),
          style: squiggle,
        ),
      ],
    );
    addTearDown(decorations.dispose);

    await pumpEditor(tester, controller, decorations);

    expect(tester.takeException(), isNull);
    final List<Invocation> paths = callsTo(tester, #drawPath);
    expect(paths, hasLength(2));
    for (final Invocation call in paths) {
      final Rect bounds = (call.positionalArguments[0] as Path).getBounds();
      expect(bounds.width, greaterThan(4), reason: 'the squiggle must be visible');
    }
  });

  testWidgets('ranges outside the viewport are skipped', (WidgetTester tester) async {
    final CodeLineEditingController controller =
        CodeLineEditingController.fromText(source(200));
    addTearDown(controller.dispose);
    final CodeDecorationController decorations = CodeDecorationController(
      <CodeDecoration>[
        const CodeDecoration(
          range: CodeLineSelection(
            baseIndex: 150,
            baseOffset: 0,
            extentIndex: 150,
            extentOffset: 4,
          ),
          style: squiggle,
        ),
      ],
    );
    addTearDown(decorations.dispose);

    await pumpEditor(tester, controller, decorations);

    expect(callsTo(tester, #drawPath), isEmpty);

    decorations.value = <CodeDecoration>[
      const CodeDecoration(
        range: CodeLineSelection(
          baseIndex: 0,
          baseOffset: 0,
          extentIndex: 0,
          extentOffset: 4,
        ),
        style: squiggle,
      ),
    ];
    await tester.pump();

    expect(callsTo(tester, #drawPath), hasLength(1));
  });

  testWidgets('a range starting above the viewport still paints', (WidgetTester tester) async {
    final CodeLineEditingController controller =
        CodeLineEditingController.fromText(source(400));
    addTearDown(controller.dispose);
    const CodeDecoration above = CodeDecoration(
      range: CodeLineSelection(
        baseIndex: 0,
        baseOffset: 0,
        extentIndex: 3,
        extentOffset: 4,
      ),
      style: squiggle,
    );
    const CodeDecoration spanning = CodeDecoration(
      range: CodeLineSelection(
        baseIndex: 5,
        baseOffset: 0,
        extentIndex: 250,
        extentOffset: 4,
      ),
      style: squiggle,
    );
    final CodeDecorationController decorations = CodeDecorationController(
      <CodeDecoration>[above, spanning],
    );
    addTearDown(decorations.dispose);
    final CodeScrollController scroll = CodeScrollController();

    await pumpEditor(tester, controller, decorations, scrollController: scroll);
    scroll.verticalScroller.jumpTo(2000);
    await tester.pumpAndSettle();

    // The range starting far above the viewport is painted on every visible
    // line it covers, which is what the interval index must not miss.
    expect(callsTo(tester, #drawPath).length, greaterThan(1));

    // Only the spanning range was visible: the one ending above the viewport
    // proves the viewport really did move past the top of the document.
    decorations.value = <CodeDecoration>[above];
    await tester.pump();
    expect(callsTo(tester, #drawPath), isEmpty);
  });

  testWidgets('a range beyond the end of its line is clipped, not thrown', (WidgetTester tester) async {
    final CodeLineEditingController controller =
        CodeLineEditingController.fromText('ab\ncd');
    addTearDown(controller.dispose);
    // A stale diagnostic, the line is shorter than the decorated range.
    final CodeDecorationController decorations = CodeDecorationController(
      <CodeDecoration>[
        const CodeDecoration(
          range: CodeLineSelection(
            baseIndex: 0,
            baseOffset: 40,
            extentIndex: 0,
            extentOffset: 80,
          ),
          style: squiggle,
        ),
      ],
    );
    addTearDown(decorations.dispose);

    await pumpEditor(tester, controller, decorations);

    expect(tester.takeException(), isNull);
    expect(callsTo(tester, #drawPath), hasLength(1));
  });

  testWidgets('rebinding moves the repaint subscription to the new controller', (WidgetTester tester) async {
    final CodeLineEditingController controller =
        CodeLineEditingController.fromText(source(4));
    addTearDown(controller.dispose);
    final CodeDecorationController first = CodeDecorationController();
    addTearDown(first.dispose);
    final CodeDecorationController second = CodeDecorationController();
    addTearDown(second.dispose);

    await pumpEditor(tester, controller, first);
    await pumpEditor(tester, controller, second);

    const CodeDecoration decoration = CodeDecoration(
      range: CodeLineSelection(
        baseIndex: 0,
        baseOffset: 0,
        extentIndex: 0,
        extentOffset: 4,
      ),
      style: squiggle,
    );

    first.value = <CodeDecoration>[decoration];
    for (final RenderObject layer in extraLayers(tester)) {
      expect(layer.debugNeedsPaint, isFalse, reason: 'the old controller was not unbound');
    }

    second.value = <CodeDecoration>[decoration];
    for (final RenderObject layer in extraLayers(tester)) {
      expect(layer.debugNeedsPaint, isTrue, reason: 'the new controller was not bound');
    }

    await tester.pump();
    expect(callsTo(tester, #drawPath), hasLength(1));
  });

  testWidgets('a disposed editor stops listening to the controller', (WidgetTester tester) async {
    final CodeLineEditingController controller =
        CodeLineEditingController.fromText(source(4));
    addTearDown(controller.dispose);
    final CodeDecorationController decorations = CodeDecorationController();
    addTearDown(decorations.dispose);

    await pumpEditor(tester, controller, decorations);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();

    decorations.value = <CodeDecoration>[
      const CodeDecoration(
        range: CodeLineSelection.collapsed(index: 0, offset: 0),
        style: squiggle,
      ),
    ];

    expect(tester.takeException(), isNull);
  });

  group('CodeDecorationController', () {
    test('notifies only when the decorations change', () {
      final CodeDecorationController decorations = CodeDecorationController();
      addTearDown(decorations.dispose);
      int notifications = 0;
      decorations.addListener(() => notifications++);

      const CodeDecoration decoration = CodeDecoration(
        range: CodeLineSelection.collapsed(index: 0, offset: 0),
        style: squiggle,
      );
      decorations.value = <CodeDecoration>[decoration];
      expect(notifications, 1);

      // An equal but distinct list must not repaint.
      decorations.value = <CodeDecoration>[decoration];
      expect(notifications, 1);

      decorations.clear();
      expect(notifications, 2);
      expect(decorations.value, isEmpty);
    });

    test('holds an unmodifiable copy of the decorations', () {
      final List<CodeDecoration> mutable = <CodeDecoration>[
        const CodeDecoration(
          range: CodeLineSelection.collapsed(index: 0, offset: 0),
          style: squiggle,
        ),
      ];
      final CodeDecorationController decorations = CodeDecorationController(mutable);
      addTearDown(decorations.dispose);

      mutable.clear();
      expect(decorations.value, hasLength(1));
      expect(() => decorations.value.clear(), throwsUnsupportedError);
    });
  });

  group('decorationsOverlappingLines', () {
    /// 50 short ranges, one every four lines, plus a long one spanning almost
    /// all of them. The long range starts above most windows, so it is only
    /// reported by a query that handles ranges reaching into the window from
    /// above. The list is built in start line order, which is the order the
    /// query reports in.
    List<CodeDecoration> build() {
      final List<CodeDecoration> decorations = <CodeDecoration>[
        CodeDecoration(
          range: const CodeLineSelection(
            baseIndex: 0,
            baseOffset: 0,
            extentIndex: 2,
            extentOffset: 3,
          ),
          style: squiggle,
        ),
        CodeDecoration(
          range: const CodeLineSelection(
            baseIndex: 1,
            baseOffset: 0,
            extentIndex: 195,
            extentOffset: 3,
          ),
          style: squiggle,
        ),
      ];
      for (int i = 1; i < 50; i++) {
        decorations.add(CodeDecoration(
          range: CodeLineSelection(
            baseIndex: i * 4,
            baseOffset: 0,
            extentIndex: i * 4 + 2,
            extentOffset: 3,
          ),
          style: squiggle,
        ));
      }
      return decorations;
    }

    /// The overlapping decorations, found by looking at every one of them.
    List<CodeDecoration> scan(List<CodeDecoration> all, int firstLine, int lastLine) {
      return all
          .where((CodeDecoration decoration) =>
              decoration.range.endIndex >= firstLine &&
              decoration.range.startIndex <= lastLine)
          .toList();
    }

    test('reports exactly the decorations of a window', () {
      final List<CodeDecoration> all = build();
      final CodeDecorationController decorations = CodeDecorationController(all);
      addTearDown(decorations.dispose);

      // A window inside a short range, one in the gap between two of them, the
      // first and the last lines of the document, and a window below every
      // range.
      for (final List<int> window in const <List<int>>[
        <int>[0, 0],
        <int>[3, 3],
        <int>[8, 9],
        <int>[100, 120],
        <int>[190, 199],
        <int>[196, 198],
        <int>[199, 205],
        <int>[500, 600],
      ]) {
        expect(
          decorations.decorationsOverlappingLines(window[0], window[1]),
          scan(all, window[0], window[1]),
          reason: 'window $window',
        );
      }
    });

    test('reports a range starting above the window', () {
      final List<CodeDecoration> all = build();
      final CodeDecorationController decorations = CodeDecorationController(all);
      addTearDown(decorations.dispose);

      // Line 3 is in a gap between the short ranges, so the only overlap is the
      // long range, which starts two lines above the window.
      final List<CodeDecoration> found = decorations.decorationsOverlappingLines(3, 3);
      expect(found, hasLength(1));
      expect(found.single.range.startIndex, 1);
      expect(found.single.range.endIndex, 195);
    });

    test('agrees with a full scan on every window of the document', () {
      final List<CodeDecoration> all = build();
      final CodeDecorationController decorations = CodeDecorationController(all);
      addTearDown(decorations.dispose);

      for (int first = 0; first <= 200; first++) {
        for (final int height in const <int>[0, 1, 7, 40]) {
          expect(
            decorations.decorationsOverlappingLines(first, first + height),
            scan(all, first, first + height),
            reason: 'window [$first, ${first + height}]',
          );
        }
      }
    });

    test('is independent of the order the decorations were given in', () {
      final List<CodeDecoration> all = build();
      final List<CodeDecoration> shuffled = all.reversed.toList();
      final CodeDecorationController decorations = CodeDecorationController(shuffled);
      addTearDown(decorations.dispose);

      for (int first = 0; first <= 200; first += 3) {
        expect(
          decorations.decorationsOverlappingLines(first, first + 9),
          unorderedEquals(scan(all, first, first + 9)),
          reason: 'window [$first, ${first + 9}]',
        );
      }
    });

    test('reports nothing for an empty controller or an empty window', () {
      final CodeDecorationController empty = CodeDecorationController();
      addTearDown(empty.dispose);
      expect(empty.decorationsOverlappingLines(0, 100), isEmpty);

      final CodeDecorationController decorations = CodeDecorationController(build());
      addTearDown(decorations.dispose);
      // An inverted window covers no line at all.
      expect(decorations.decorationsOverlappingLines(10, 9), isEmpty);
      // Negative lines never happen, but must not read outside the index.
      expect(decorations.decorationsOverlappingLines(-5, -1), isEmpty);
    });

    test('follows the decorations of the controller', () {
      final CodeDecorationController decorations = CodeDecorationController(build());
      addTearDown(decorations.dispose);
      expect(decorations.decorationsOverlappingLines(3, 3), hasLength(1));

      decorations.clear();
      expect(decorations.decorationsOverlappingLines(3, 3), isEmpty);

      decorations.value = <CodeDecoration>[
        const CodeDecoration(
          range: CodeLineSelection.collapsed(index: 7, offset: 0),
          style: squiggle,
        ),
      ];
      expect(decorations.decorationsOverlappingLines(3, 3), isEmpty);
      expect(decorations.decorationsOverlappingLines(7, 7), hasLength(1));
    });
  });
}
