// Unlike its siblings this part names the library by URI: the fork's analyze
// gate is held at a fixed issue count, and the legacy `part of re_editor;`
// form the other parts use is itself one of the lints being counted.
part of 're_editor.dart';

/// A styled slice of one line, pushed by the application on top of the
/// grammar highlighting.
///
/// [start] and [end] are UTF-16 code unit offsets into the line's text, `end`
/// exclusive — the same units a Dart [String] is indexed in, and the same units
/// LSP positions are expressed in, so a decoded semantic token needs no
/// conversion. Offsets outside the line are clipped when the span is painted,
/// never validated here: a span left over from a buffer revision that has since
/// shrunk must not be able to throw.
///
/// [style] is a theme key resolved through [CodeHighlightTheme] exactly like a
/// tree-sitter capture name, dotted fallback included. Reusing the one lookup
/// is what lets the semantic layer share the grammar layer's palette instead of
/// carrying [TextStyle]s of its own.
@immutable
class CodeSemanticSpan {
  const CodeSemanticSpan({
    required this.start,
    required this.end,
    required this.style,
  });

  /// First code unit covered.
  final int start;

  /// One past the last code unit covered.
  final int end;

  /// The [CodeHighlightTheme] key this span paints with.
  final String style;

  bool get isEmpty => end <= start;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CodeSemanticSpan &&
          other.start == start &&
          other.end == end &&
          other.style == style;

  @override
  int get hashCode => Object.hash(start, end, style);

  @override
  String toString() => 'CodeSemanticSpan($start..$end, $style)';
}

/// Holds the semantic (LSP) colour overlay of a [CodeEditor], keyed by absolute
/// line index.
///
/// The grammar layer inside the editor is a single pipeline: tree-sitter styles
/// a window of lines and the result is flattened into gap-filled nodes. This
/// controller is the *second* span source, and the only one the application can
/// write. Where an overlay span covers a line, its style replaces the grammar
/// style for exactly those code units; everywhere else the grammar layer shows
/// through, its nodes split as needed. That is the merge policy: semantic
/// tokens win over tree-sitter for colour, and both stay below the decoration
/// painters (diagnostics, selection), which are not spans at all.
///
/// ```dart
/// overlayController.value = <int, List<CodeSemanticSpan>>{
///   12: <CodeSemanticSpan>[
///     CodeSemanticSpan(start: 8, end: 13, style: 'parameter'),
///   ],
/// };
/// ```
///
/// Assigning [value] repaints the text with the new colours. It does **not**
/// re-run the grammar highlighter: the merge happens when a line's span is
/// built, so the worker is never asked for anything it has already answered.
///
/// The overlay is deliberately *not* cleared when the buffer moves ahead of the
/// server. Colour is cosmetic — a slightly stale classification is invisible,
/// where blanking it would flash every identifier back to plain on each
/// keystroke. Diagnostics take the opposite decision, because a squiggle in the
/// wrong place is a lie about *where* a problem is.
class CodeSemanticOverlayController
    extends ValueNotifier<Map<int, List<CodeSemanticSpan>>> {
  /// Creates a controller holding [spans].
  CodeSemanticOverlayController([
    Map<int, List<CodeSemanticSpan>> spans =
        const <int, List<CodeSemanticSpan>>{},
  ]) : super(_normalize(spans));

  /// Whether any line carries overlay spans.
  bool get isEmpty => value.isEmpty;

  /// Replaces the whole overlay.
  ///
  /// Per line the spans are sorted by [CodeSemanticSpan.start], emptied ones
  /// dropped and overlaps trimmed so the earlier span keeps its text — the
  /// merge below relies on a line's spans being disjoint and ordered, and the
  /// cheapest place to guarantee that is the one door they come through.
  /// Listeners are notified only when the normalized overlay differs.
  @override
  set value(Map<int, List<CodeSemanticSpan>> newValue) {
    final Map<int, List<CodeSemanticSpan>> next = _normalize(newValue);
    if (_sameOverlay(value, next)) {
      return;
    }
    super.value = next;
  }

  /// Removes every span.
  void clear() {
    value = const <int, List<CodeSemanticSpan>>{};
  }

  /// The disjoint, ordered spans of absolute line [index], or null when the
  /// line carries none.
  List<CodeSemanticSpan>? spansForLine(int index) => value[index];

  static Map<int, List<CodeSemanticSpan>> _normalize(
    Map<int, List<CodeSemanticSpan>> spans,
  ) {
    if (spans.isEmpty) {
      return const <int, List<CodeSemanticSpan>>{};
    }
    final Map<int, List<CodeSemanticSpan>> out =
        <int, List<CodeSemanticSpan>>{};
    for (final MapEntry<int, List<CodeSemanticSpan>> entry in spans.entries) {
      if (entry.key < 0 || entry.value.isEmpty) {
        continue;
      }
      final List<CodeSemanticSpan> line = <CodeSemanticSpan>[
        for (final CodeSemanticSpan span in entry.value)
          if (!span.isEmpty && span.end > 0)
            span.start < 0
                ? CodeSemanticSpan(start: 0, end: span.end, style: span.style)
                : span,
      ]..sort((CodeSemanticSpan a, CodeSemanticSpan b) =>
          a.start.compareTo(b.start));
      final List<CodeSemanticSpan> disjoint = <CodeSemanticSpan>[];
      int cursor = 0;
      for (final CodeSemanticSpan span in line) {
        if (span.end <= cursor) {
          continue;
        }
        disjoint.add(
          span.start >= cursor
              ? span
              : CodeSemanticSpan(
                  start: cursor,
                  end: span.end,
                  style: span.style,
                ),
        );
        cursor = span.end;
      }
      if (disjoint.isNotEmpty) {
        out[entry.key] = List<CodeSemanticSpan>.unmodifiable(disjoint);
      }
    }
    return out.isEmpty
        ? const <int, List<CodeSemanticSpan>>{}
        : Map<int, List<CodeSemanticSpan>>.unmodifiable(out);
  }

  static bool _sameOverlay(
    Map<int, List<CodeSemanticSpan>> a,
    Map<int, List<CodeSemanticSpan>> b,
  ) {
    if (identical(a, b)) {
      return true;
    }
    if (a.length != b.length) {
      return false;
    }
    for (final MapEntry<int, List<CodeSemanticSpan>> entry in a.entries) {
      final List<CodeSemanticSpan>? other = b[entry.key];
      if (other == null || !listEquals(entry.value, other)) {
        return false;
      }
    }
    return true;
  }
}
