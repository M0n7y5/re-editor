import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

/// Correctness of the multi-caret edit fan-out (`_forEachCaret`) after the
/// large-file perf work: batched `value` writes, segment-skipping flat-offset
/// helpers, and the cached per-segment `charCount`. The buffer is the ground
/// truth — every op must land identically at each caret regardless of where the
/// carets sit (segment boundaries, last line, several on one line).
///
/// Pure controller (no widget): `_render` is null so focus-scroll is a no-op,
/// isolating edit behaviour.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String source(int lines) =>
      List<String>.generate(lines, (int i) => 'line $i value;').join('\n');

  // Set K carets; `selections` is extraSelections + [primary], primary last.
  void setCollapsedCarets(
    CodeLineEditingController c,
    List<({int line, int offset})> carets,
  ) {
    final List<CodeLineSelection> sels = carets
        .map((({int line, int offset}) p) =>
            CodeLineSelection.collapsed(index: p.line, offset: p.offset))
        .toList();
    c.value = c.value.copyWith(
      selection: sels.last,
      extraSelections: sels.sublist(0, sels.length - 1),
    );
  }

  group('multi-caret edit fan-out', () {
    test('type inserts at every caret across segment boundaries and last line',
        () {
      // 600 lines => 3 segments (0-255, 256-511, 512-599); carets straddle the
      // 256-line segment boundary and include the last line.
      final CodeLineEditingController c =
          CodeLineEditingController.fromText(source(600));
      addTearDown(c.dispose);
      const List<int> hit = <int>[0, 255, 256, 511, 599];
      setCollapsedCarets(
          c, hit.map((int l) => (line: l, offset: 0)).toList());
      expect(c.selections.length, hit.length);

      c.replaceSelection('Z');

      final List<String> lines = c.text.split('\n');
      expect(lines.length, 600);
      for (int i = 0; i < 600; i++) {
        if (hit.contains(i)) {
          expect(lines[i], 'Zline $i value;', reason: 'caret line $i');
        } else {
          expect(lines[i], 'line $i value;', reason: 'untouched line $i');
        }
      }
      // Every caret advanced one column past its insert.
      for (final CodeLineSelection s in c.selections) {
        expect(s.isCollapsed, isTrue);
        expect(s.extentOffset, 1);
      }
    });

    test('two carets on the same line both insert with the running delta', () {
      final CodeLineEditingController c =
          CodeLineEditingController.fromText('abcdef\nghijkl');
      addTearDown(c.dispose);
      // Same line, offsets 0 and 3. The second insert must shift right by the
      // first insert's length — exercises the flat-offset + delta bookkeeping.
      setCollapsedCarets(c, <({int line, int offset})>[
        (line: 0, offset: 0),
        (line: 0, offset: 3),
      ]);

      c.replaceSelection('X');

      expect(c.text, 'XabcXdef\nghijkl');
    });

    test('backspace deletes one char at every caret', () {
      final CodeLineEditingController c =
          CodeLineEditingController.fromText(source(20));
      addTearDown(c.dispose);
      // Carets at offset 2 ('li|ne ...') on several lines.
      setCollapsedCarets(c, <({int line, int offset})>[
        (line: 0, offset: 2),
        (line: 9, offset: 2),
        (line: 19, offset: 2),
      ]);

      c.deleteBackward();

      final List<String> lines = c.text.split('\n');
      for (final int i in <int>[0, 9, 19]) {
        expect(lines[i], 'lne $i value;', reason: 'line $i lost char at 1');
      }
      expect(lines[1], 'line 1 value;');
    });

    test('newline splits every caret line and grows the line count by K', () {
      final CodeLineEditingController c =
          CodeLineEditingController.fromText(source(10));
      addTearDown(c.dispose);
      setCollapsedCarets(c, <({int line, int offset})>[
        (line: 0, offset: 4),
        (line: 5, offset: 4),
      ]);

      c.applyNewLine();

      final List<String> lines = c.text.split('\n');
      expect(lines.length, 12); // 10 + 2 splits
      // 'line 0 value;' split at col 4 -> 'line' + ' 0 value;'.
      expect(lines[0], 'line');
      expect(lines[1], ' 0 value;');
    });

    test('single-caret editing is unaffected by the multi-caret path', () {
      final CodeLineEditingController c =
          CodeLineEditingController.fromText(source(5));
      addTearDown(c.dispose);
      c.selection = const CodeLineSelection.collapsed(index: 2, offset: 0);

      c.replaceSelection('Q');

      final List<String> lines = c.text.split('\n');
      expect(lines[2], 'Qline 2 value;');
      expect(c.selections.length, 1);
    });
  });

  // Guards the asymptotic complexity, not micro-performance: before the fix a
  // K-caret keystroke was O(K * doc^2) (each offset conversion indexed the
  // segmented buffer in a loop), so K=64 on 20k lines took ~1s/keystroke. The
  // bound is deliberately loose (~10x the observed ~35ms) so it only trips if
  // the quadratic behaviour returns, never on normal machine variance.
  test('multi-caret typing stays near-linear on a large buffer', () {
    final CodeLineEditingController c =
        CodeLineEditingController.fromText(source(20000));
    addTearDown(c.dispose);
    final List<({int line, int offset})> carets = <({int line, int offset})>[];
    for (int i = 0; i < 64; i++) {
      carets.add((line: i * 312, offset: 0));
    }
    setCollapsedCarets(c, carets);
    expect(c.selections.length, 64);

    c.replaceSelection('x'); // warm up
    final Stopwatch sw = Stopwatch()..start();
    for (int i = 0; i < 5; i++) {
      c.replaceSelection('x');
    }
    sw.stop();
    final double msPerStroke = sw.elapsedMicroseconds / 5 / 1000.0;
    expect(msPerStroke, lessThan(400),
        reason: 'O(K*doc^2) regression: ${msPerStroke.toStringAsFixed(1)} ms/keystroke');
  });
}
