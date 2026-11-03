import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nok_tree_sitter/nok_tree_sitter.dart' show Grammar, dartGrammar;
import 'package:re_editor/re_editor.dart';

/// The highlight worker keeps one tree-sitter highlighter per language id.
/// These tests switch one editor (so one worker isolate) between two ids and
/// read the painted colours off the laid-out paragraphs.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const Color keywordColor = Color(0xFF00FF00);
  const Color commentColor = Color(0xFF0000FF);
  const Map<String, TextStyle> palette = <String, TextStyle>{
    'keyword': TextStyle(color: keywordColor),
    'comment': TextStyle(color: commentColor),
  };
  final Grammar commentsOnly = Grammar(
    id: 'dart-comments',
    language: dartGrammar.language,
    highlightsScm: '(comment) @comment',
  );
  final Map<String, Grammar> grammars = <String, Grammar>{
    'dart': dartGrammar,
    'dart-comments': commentsOnly,
  };
  const String source = 'class A {} // c';

  Future<void> pumpEditor(WidgetTester tester,
      CodeLineEditingController controller, String languageId) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 600,
          height: 240,
          child: CodeEditor(
            controller: controller,
            autofocus: false,
            wordWrap: false,
            style: CodeEditorStyle(
              fontSize: 13,
              fontFamily: 'monospace',
              codeTheme: CodeHighlightTheme(
                theme: palette,
                languageId: languageId,
                grammars: grammars,
              ),
            ),
          ),
        ),
      ),
    ));
  }

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
    return found!;
  }

  /// The colour painted at the start of [token] on line 0.
  Color? colorOf(WidgetTester tester, String token) {
    final List<CodeLineRenderParagraph> paragraphs =
        // ignore: avoid_dynamic_calls
        (codeFieldRender(tester) as dynamic).displayParagraphs
            as List<CodeLineRenderParagraph>;
    // ignore: avoid_dynamic_calls
    final TextSpan span = (paragraphs.first.paragraph as dynamic).span as TextSpan;
    final int offset = source.indexOf(token);
    int cursor = 0;
    for (final InlineSpan child in span.children ?? const <InlineSpan>[]) {
      final TextSpan run = child as TextSpan;
      final int length = run.text?.length ?? 0;
      if (offset < cursor + length) {
        return run.style?.color;
      }
      cursor += length;
    }
    return null;
  }

  /// Pumps until [done] holds; the worker reply rides the real event loop.
  Future<void> awaitPaint(WidgetTester tester, bool Function() done) async {
    for (int i = 0; i < 200; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      if (done()) {
        return;
      }
    }
    fail('the highlight never settled');
  }

  // Catches a worker cache that ignores the language id: after the switch the
  // first id's highlighter (and its keyword query) would keep painting `class`.
  testWidgets('switching language id switches the highlighter',
      (WidgetTester tester) async {
    final CodeLineEditingController controller =
        CodeLineEditingController.fromText(source);
    addTearDown(controller.dispose);

    await pumpEditor(tester, controller, 'dart');
    await awaitPaint(tester, () => colorOf(tester, 'class') == keywordColor);
    expect(colorOf(tester, '// c'), commentColor);

    await pumpEditor(tester, controller, 'dart-comments');
    await awaitPaint(tester, () => colorOf(tester, 'class') == null);
    expect(colorOf(tester, '// c'), commentColor);
  });
}
