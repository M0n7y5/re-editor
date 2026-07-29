import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

/// Cover for [CodeDecorationStyle.fullLine]: the background tint of a
/// full-line decoration spans the viewport from edge to edge — the rendering
/// of a "current execution line" highlight — while the default style keeps
/// hugging the glyphs of the range.
///
/// Same technique as `code_decoration_test.dart`: the painters are private,
/// so the paint of the extra render layers is replayed into a
/// [TestRecordingCanvas] and the display list inspected. A tint is a
/// `drawRect` call.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const Color tint = Color(0x332196F3);

  String source(int lines) =>
      List<String>.generate(lines, (int i) => 'line $i value;').join('\n');

  Future<void> pumpEditor(
    WidgetTester tester,
    CodeLineEditingController controller,
    CodeDecorationController? decorations,
  ) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            height: 200,
            child: CodeEditor(
              controller: controller,
              decorations: decorations,
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

  /// The rects of every recorded background tint.
  List<Rect> tintRects(WidgetTester tester) => callsTo(tester, #drawRect)
      .map((Invocation call) => call.positionalArguments[0] as Rect)
      .toList();

  double fieldWidth(WidgetTester tester) =>
      (codeFieldRender(tester) as RenderBox).size.width;

  CodeDecoration decorate(
    int line,
    int endOffset, {
    required CodeDecorationStyle style,
  }) =>
      CodeDecoration(
        range: CodeLineSelection(
          baseIndex: line,
          baseOffset: 0,
          extentIndex: line,
          extentOffset: endOffset,
        ),
        style: style,
      );

  testWidgets('a full line tint spans the viewport from edge to edge',
      (WidgetTester tester) async {
    final CodeLineEditingController controller =
        CodeLineEditingController.fromText(source(4));
    addTearDown(controller.dispose);
    final CodeDecorationController decorations = CodeDecorationController(
      <CodeDecoration>[
        decorate(1, controller.codeLines[1].length,
            style: const CodeDecorationStyle(
              underline: CodeDecorationUnderlineStyle.none,
              backgroundColor: tint,
              fullLine: true,
            )),
      ],
    );
    addTearDown(decorations.dispose);

    await pumpEditor(tester, controller, decorations);

    expect(tester.takeException(), isNull);
    final List<Rect> rects = tintRects(tester);
    expect(rects, hasLength(1));
    expect(rects.single.left, 0,
        reason: 'the bar must start at the viewport edge, before the padding');
    expect(rects.single.width, fieldWidth(tester),
        reason: 'the bar must run the full viewport width');
    expect(rects.single.height, greaterThan(0));
    expect(callsTo(tester, #drawPath), isEmpty,
        reason: 'underline none must stay unpainted');
  });

  testWidgets('the default style still hugs the glyphs of the range',
      (WidgetTester tester) async {
    final CodeLineEditingController controller =
        CodeLineEditingController.fromText(source(4));
    addTearDown(controller.dispose);
    final CodeDecorationController decorations = CodeDecorationController(
      <CodeDecoration>[
        decorate(1, 4,
            style: const CodeDecorationStyle(
              underline: CodeDecorationUnderlineStyle.none,
              backgroundColor: tint,
            )),
      ],
    );
    addTearDown(decorations.dispose);

    await pumpEditor(tester, controller, decorations);

    final List<Rect> rects = tintRects(tester);
    expect(rects, hasLength(1));
    expect(rects.single.left, greaterThan(0),
        reason: 'a span tint starts at its first glyph, inside the padding');
    expect(rects.single.width, lessThan(fieldWidth(tester) / 2),
        reason: 'a 4-character tint must not grow to the viewport');
  });

  testWidgets('a full line tint on an empty line still spans the viewport',
      (WidgetTester tester) async {
    final CodeLineEditingController controller =
        CodeLineEditingController.fromText('first\n\nthird');
    addTearDown(controller.dispose);
    final CodeDecorationController decorations = CodeDecorationController(
      <CodeDecoration>[
        decorate(1, 0,
            style: const CodeDecorationStyle(
              underline: CodeDecorationUnderlineStyle.none,
              backgroundColor: tint,
              fullLine: true,
            )),
      ],
    );
    addTearDown(decorations.dispose);

    await pumpEditor(tester, controller, decorations);

    final List<Rect> rects = tintRects(tester);
    expect(rects, hasLength(1));
    expect(rects.single.left, 0);
    expect(rects.single.width, fieldWidth(tester),
        reason: 'an empty line has no glyphs, which is exactly the case the '
            'glyph-hugging tint degrades on');
  });

  testWidgets('fullLine leaves a foreground underline on the glyphs',
      (WidgetTester tester) async {
    final CodeLineEditingController controller =
        CodeLineEditingController.fromText(source(4));
    addTearDown(controller.dispose);
    final CodeDecorationController decorations = CodeDecorationController(
      <CodeDecoration>[
        decorate(1, 4,
            style: const CodeDecorationStyle(
              underlineColor: Color(0xFFFF0000),
              backgroundColor: tint,
              fullLine: true,
            )),
      ],
    );
    addTearDown(decorations.dispose);

    await pumpEditor(tester, controller, decorations);

    final List<Rect> rects = tintRects(tester);
    expect(rects, hasLength(1));
    expect(rects.single.width, fieldWidth(tester));
    final List<Invocation> paths = callsTo(tester, #drawPath);
    expect(paths, hasLength(1), reason: 'the underline still paints');
    final Rect bounds =
        (paths.single.positionalArguments[0] as Path).getBounds();
    expect(bounds.width, lessThan(fieldWidth(tester) / 2),
        reason: 'the underline still follows the glyphs, not the bar');
  });

  test('fullLine participates in equality and copyWith', () {
    const CodeDecorationStyle base = CodeDecorationStyle(backgroundColor: tint);
    expect(base.fullLine, isFalse, reason: 'additive default');
    expect(base, isNot(base.copyWith(fullLine: true)));
    expect(base.copyWith(fullLine: true).fullLine, isTrue);
    expect(base.copyWith(fullLine: true),
        const CodeDecorationStyle(backgroundColor: tint, fullLine: true));
    expect(base.copyWith(fullLine: true).hashCode,
        isNot(base.hashCode), reason: 'hash must see the flag');
  });
}
