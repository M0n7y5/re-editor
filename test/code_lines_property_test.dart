// Property/oracle tests for the tree-backed [CodeLines]. Cross-checks the buffer
// against a plain `List<CodeLine>` reference over randomized op sequences, and
// asserts the AVL+summary invariants (`debugValidate`) after every mutation.
// This is the correctness gate for the rope cutover — it must pass before the
// behavioural suite or any perf claim is trusted.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

int _counter = 0;
CodeLine _newLine() => CodeLine('v${_counter++}');

void _expectMatches(CodeLines cl, List<CodeLine> ref, {String reason = ''}) {
  cl.debugValidate();
  expect(cl.length, ref.length, reason: '$reason length');
  expect(
    cl.lineCount,
    ref.fold<int>(0, (p, e) => p + e.lineCount),
    reason: '$reason lineCount',
  );
  expect(
    cl.charCount,
    ref.fold<int>(0, (p, e) => p + e.charCount),
    reason: '$reason charCount',
  );
  expect(listEquals(cl.toList(), ref), true, reason: '$reason toList');
}

// Reference for the inverse flat-offset mapping (the pre-rope algorithm).
(int, int) _refLineOffsetForFlat(List<CodeLine> ref, int target, int br) {
  if (ref.isEmpty) {
    return (0, 0);
  }
  final int last = ref.length - 1;
  int start = 0;
  for (int i = 0; i <= last; i++) {
    final int cc = ref[i].charCount;
    final int end = start + cc + br;
    if (target < end || i == last) {
      return (i, (target - start).clamp(0, cc));
    }
    start = end;
  }
  return (last, 0);
}

void main() {
  group('CodeLines tree — randomized op fuzz vs List reference', () {
    test('edit primitives (insert/replace/delete/append) stay equivalent', () {
      int state = 0x1234567;
      int rnd(int n) {
        state = (state * 1103515245 + 12345) & 0x7fffffff;
        return state % n;
      }

      // Seed a multi-segment buffer (>2 segments at 256/segment).
      List<CodeLine> ref = List<CodeLine>.generate(600, (_) => _newLine());
      CodeLines cl = CodeLines.of(ref);
      _expectMatches(cl, ref, reason: 'seed');

      for (int op = 0; op < 2000; op++) {
        final int len = cl.length;
        final int kind = rnd(4);
        if (kind == 0) {
          // insert a line at i (mirrors sublines(0,i) + add + addFrom(i))
          final int i = rnd(len + 1);
          final CodeLine x = _newLine();
          final CodeLines c = cl.sublines(0, i);
          c.add(x);
          if (i < len) {
            c.addFrom(cl, i);
          }
          cl = c;
          ref = [...ref.sublist(0, i), x, ...ref.sublist(i)];
        } else if (kind == 1 && len > 0) {
          // replace line at i
          final int i = rnd(len);
          final CodeLine x = _newLine();
          cl[i] = x;
          ref[i] = x;
        } else if (kind == 2 && len > 0) {
          // delete line at i (mirrors sublines(0,i) + addFrom(i+1))
          final int i = rnd(len);
          final CodeLines c = cl.sublines(0, i);
          if (i + 1 < len) {
            c.addFrom(cl, i + 1);
          }
          cl = c;
          ref = [...ref.sublist(0, i), ...ref.sublist(i + 1)];
        } else {
          // append
          final CodeLine x = _newLine();
          cl.add(x);
          ref = [...ref, x];
        }
        if (op % 50 == 0) {
          _expectMatches(cl, ref, reason: 'op $op');
        }
      }
      _expectMatches(cl, ref, reason: 'final');
    });

    test('sublines slices match List.sublist', () {
      final List<CodeLine> ref = List<CodeLine>.generate(
        700,
        (_) => _newLine(),
      );
      final CodeLines cl = CodeLines.of(ref);
      int state = 99;
      int rnd(int n) {
        state = (state * 1103515245 + 12345) & 0x7fffffff;
        return state % n;
      }

      for (int t = 0; t < 200; t++) {
        final int a = rnd(701);
        final int b = a + rnd(701 - a);
        final CodeLines slice = cl.sublines(a, b);
        slice.debugValidate();
        expect(
          listEquals(slice.toList(), ref.sublist(a, b)),
          true,
          reason: 'sublines($a,$b)',
        );
      }
    });

    test(
      'from() snapshot is independent (structural sharing, copy-on-write)',
      () {
        final List<CodeLine> ref = List<CodeLine>.generate(
          300,
          (_) => _newLine(),
        );
        final CodeLines original = CodeLines.of(ref);
        final CodeLines copy = CodeLines.from(original);
        // mutate the copy
        final CodeLine y = _newLine();
        copy[0] = y;
        copy.add(_newLine());
        // original is unaffected
        _expectMatches(original, ref, reason: 'original after copy mutated');
        expect(copy[0], y);
        expect(copy.length, ref.length + 1);
        // mutate the original; copy unaffected by it
        final CodeLine z = _newLine();
        original[5] = z;
        expect(copy[5], ref[5]);
        expect(original[5], z);
      },
    );

    test('operator[] and index2lineIndex match across segment boundaries', () {
      final List<CodeLine> ref = List<CodeLine>.generate(
        1000,
        (_) => _newLine(),
      );
      final CodeLines cl = CodeLines.of(ref);
      for (final int i in <int>[0, 1, 255, 256, 257, 511, 512, 999]) {
        expect(cl[i], ref[i], reason: 'operator[$i]');
        expect(
          cl.index2lineIndex(i),
          i,
          reason: 'index2lineIndex($i) (flat → identity)',
        );
        expect(
          cl.charCountBefore(i),
          ref.take(i).fold<int>(0, (p, e) => p + e.charCount),
          reason: 'charCountBefore($i)',
        );
      }
      expect(() => cl[1000], throwsA(isA<RangeError>()));
    });
  });

  group('CodeLines tree — folding (chunks) aware mapping', () {
    // A buffer where some top-level lines carry folded chunk children.
    CodeLines buildFolded() {
      return CodeLines.of(<CodeLine>[
        const CodeLine('a'),
        const CodeLine('b', <CodeLine>[
          CodeLine('b1'),
          CodeLine('b2'),
        ]), // 3 display lines
        const CodeLine('c'),
        const CodeLine('d', <CodeLine>[CodeLine('d1')]), // 2 display lines
        const CodeLine('e'),
      ]);
    }

    test('lineCount counts folded chunks', () {
      final CodeLines cl = buildFolded();
      expect(cl.length, 5); // top-level
      expect(cl.lineCount, 1 + 3 + 1 + 2 + 1); // 8 display lines
    });

    test('lineIndex2Index resolves display lines to (index, chunkIndex)', () {
      final CodeLines cl = buildFolded();
      // display order: a(0) | b(1) b1(2) b2(3) | c(4) | d(5) d1(6) | e(7)
      expect(cl.lineIndex2Index(0), const CodeLineIndex(0, -1));
      expect(cl.lineIndex2Index(1), const CodeLineIndex(1, -1)); // visible 'b'
      expect(cl.lineIndex2Index(2), const CodeLineIndex(1, 0)); // chunk b1
      expect(cl.lineIndex2Index(3), const CodeLineIndex(1, 1)); // chunk b2
      expect(cl.lineIndex2Index(4), const CodeLineIndex(2, -1)); // 'c'
      expect(cl.lineIndex2Index(5), const CodeLineIndex(3, -1)); // visible 'd'
      expect(cl.lineIndex2Index(6), const CodeLineIndex(3, 0)); // chunk d1
      expect(cl.lineIndex2Index(7), const CodeLineIndex(4, -1)); // 'e'
      // index2lineIndex is the inverse for visible lines
      expect(cl.index2lineIndex(0), 0);
      expect(cl.index2lineIndex(1), 1);
      expect(cl.index2lineIndex(2), 4);
      expect(cl.index2lineIndex(3), 5);
      expect(cl.index2lineIndex(4), 7);
    });
  });

  group('CodeLines tree — flat offset mapping', () {
    test('lineOffsetForFlat matches the reference algorithm over a sweep', () {
      final List<CodeLine> ref = <CodeLine>[
        const CodeLine('hello'),
        const CodeLine(''),
        const CodeLine('a longer line here'),
        const CodeLine('xy'),
      ];
      final CodeLines cl = CodeLines.of(ref);
      const int br = 1;
      final int total = cl.charCount + cl.length * br;
      for (int target = -2; target <= total + 5; target++) {
        expect(
          cl.lineOffsetForFlat(target, br),
          _refLineOffsetForFlat(ref, target, br),
          reason: 'flat $target',
        );
      }
    });
  });

  group('CodeLines tree — boundary sizes', () {
    for (final int n in <int>[0, 1, 255, 256, 257, 512, 513]) {
      test('build + append + slice at n=$n', () {
        final List<CodeLine> ref = List<CodeLine>.generate(
          n,
          (_) => _newLine(),
        );
        final CodeLines cl = CodeLines.of(ref);
        _expectMatches(cl, ref, reason: 'n=$n build');
        final CodeLine x = _newLine();
        cl.add(x);
        ref.add(x);
        _expectMatches(cl, ref, reason: 'n=$n after append');
        if (n > 0) {
          expect(
            listEquals(cl.sublines(0, n).toList(), ref.sublist(0, n)),
            true,
          );
        }
      });
    }
  });
}
