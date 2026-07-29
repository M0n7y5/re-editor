part of re_editor;

/// How the bottom edge of a decorated code range is underlined.
enum CodeDecorationUnderlineStyle {
  /// No underline is painted. Use this for decorations that only want
  /// [CodeDecorationStyle.backgroundColor].
  none,

  /// A straight line along the bottom of the range.
  solid,

  /// A zigzag line along the bottom of the range, the conventional rendering
  /// of a diagnostic squiggle.
  wavy,
}

/// An immutable description of how a decorated code range is painted.
///
/// Both visuals are independently optional: the underline is painted when
/// [underline] is not [CodeDecorationUnderlineStyle.none] and
/// [underlineColor] is a visible color, the tint is painted when
/// [backgroundColor] is a visible color.
///
/// The tint is painted below the text, the underline above it.
@immutable
class CodeDecorationStyle {
  /// Creates a decoration style.
  const CodeDecorationStyle({
    this.underline = CodeDecorationUnderlineStyle.wavy,
    this.underlineColor,
    this.underlineThickness = 1.0,
    this.backgroundColor,
    this.fullLine = false,
  }) : assert(underlineThickness > 0);

  /// The shape of the underline painted along the bottom of the range.
  final CodeDecorationUnderlineStyle underline;

  /// The color of the underline.
  ///
  /// If null, no underline is painted whatever [underline] is.
  final Color? underlineColor;

  /// The stroke width of the underline, in logical pixels.
  ///
  /// A wavy underline scales its wave length and amplitude with this value.
  final double underlineThickness;

  /// The color filled behind the text of the range.
  ///
  /// If null, no tint is painted. As the tint is painted above the selection
  /// and below the text, a translucent color is usually what you want.
  final Color? backgroundColor;

  /// Whether the tint spans the viewport from edge to edge instead of hugging
  /// the glyphs of the range.
  ///
  /// The conventional rendering of a "current execution line" highlight: the
  /// bar covers every covered line's full row — leading indent, trailing
  /// emptiness and empty lines included — exactly like the cursor line
  /// border. Only the [backgroundColor] tint is affected; an underline, if
  /// any, still follows the glyphs.
  final bool fullLine;

  /// Creates a copy of this style with the given fields replaced.
  CodeDecorationStyle copyWith({
    CodeDecorationUnderlineStyle? underline,
    Color? underlineColor,
    double? underlineThickness,
    Color? backgroundColor,
    bool? fullLine,
  }) {
    return CodeDecorationStyle(
      underline: underline ?? this.underline,
      underlineColor: underlineColor ?? this.underlineColor,
      underlineThickness: underlineThickness ?? this.underlineThickness,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      fullLine: fullLine ?? this.fullLine,
    );
  }

  @override
  int get hashCode => Object.hash(
      underline, underlineColor, underlineThickness, backgroundColor, fullLine);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is CodeDecorationStyle &&
        other.underline == underline &&
        other.underlineColor == underlineColor &&
        other.underlineThickness == underlineThickness &&
        other.backgroundColor == backgroundColor &&
        other.fullLine == fullLine;
  }

  @override
  String toString() =>
      'CodeDecorationStyle(underline: $underline, underlineColor: $underlineColor, '
      'underlineThickness: $underlineThickness, backgroundColor: $backgroundColor, '
      'fullLine: $fullLine)';
}

/// A [style] painted over the code inside [range].
///
/// Decorations are purely visual: they do not participate in editing, hit
/// testing or highlighting, and are not clamped to the document. A range
/// pointing outside the current content is silently clipped when painted, so
/// stale decorations (a diagnostic that arrived for an older document
/// revision) can never break rendering.
@immutable
class CodeDecoration {
  /// Creates a decoration for [range].
  const CodeDecoration({required this.range, required this.style});

  /// The decorated range.
  ///
  /// A collapsed range is still painted: it is widened to a couple of
  /// characters so that zero length diagnostics stay visible.
  final CodeLineSelection range;

  /// How [range] is painted.
  final CodeDecorationStyle style;

  @override
  int get hashCode => Object.hash(range, style);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is CodeDecoration && other.range == range && other.style == style;
  }

  @override
  String toString() => 'CodeDecoration(range: $range, style: $style)';
}

/// Holds the decorations painted over the code of a [CodeEditor].
///
/// Assign [value] whenever the decorations change, for example when new
/// diagnostics arrive:
///
/// ```dart
/// decorationController.value = diagnostics.map((Diagnostic d) => CodeDecoration(
///   range: CodeLineSelection(
///     baseIndex: d.startLine, baseOffset: d.startColumn,
///     extentIndex: d.endLine, extentOffset: d.endColumn,
///   ),
///   style: const CodeDecorationStyle(underlineColor: Colors.red),
/// )).toList();
/// ```
///
/// Updating the controller only repaints the decoration layer of the editor:
/// the text is neither relaid out nor re-highlighted.
class CodeDecorationController extends ValueNotifier<List<CodeDecoration>> {
  /// Creates a controller holding [decorations].
  CodeDecorationController([
    List<CodeDecoration> decorations = const <CodeDecoration>[],
  ]) : this._(_freeze(decorations));

  /// Both the frozen list and its index are derived from the same list, so the
  /// index can never be stale for [value].
  CodeDecorationController._(super.decorations)
      : _index = _CodeDecorationIndex.of(decorations);

  /// The line sorted index of [value], rebuilt whenever the decorations change.
  _CodeDecorationIndex _index;

  /// Replaces the painted decorations.
  ///
  /// The list is copied, and listeners are only notified when the new
  /// decorations differ from the current ones.
  @override
  set value(List<CodeDecoration> newValue) {
    if (listEquals(value, newValue)) {
      return;
    }
    final List<CodeDecoration> decorations = _freeze(newValue);
    _index = _CodeDecorationIndex.of(decorations);
    super.value = decorations;
  }

  /// Removes all decorations.
  void clear() {
    value = const <CodeDecoration>[];
  }

  /// The decorations overlapping the closed line window
  /// `[firstLine, lastLine]`, in start line order.
  ///
  /// This is how the editor finds what to paint for the lines it displays: it
  /// costs a binary search plus the reported decorations, so a viewport of a
  /// document carrying thousands of diagnostics never pays for the ones it
  /// cannot show. Decorations that start above the window and span into it are
  /// reported too. See [_CodeDecorationIndex] for the shape of the index.
  @visibleForTesting
  List<CodeDecoration> decorationsOverlappingLines(int firstLine, int lastLine) {
    return _index.query(firstLine, lastLine);
  }

  static List<CodeDecoration> _freeze(List<CodeDecoration> decorations) {
    return decorations.isEmpty
        ? const <CodeDecoration>[]
        : List<CodeDecoration>.unmodifiable(decorations);
  }
}

/// A line sorted interval index over a set of [CodeDecoration]s.
///
/// The editor paints far more often than its decorations change, so the whole
/// cost of finding the decorations of a viewport is moved to the set path: the
/// decorations are sorted by start line once, and a max heap of their end
/// lines, an implicit segment tree laid over that order, is built alongside.
///
/// A [query] for a line window then reports the overlapping decorations
/// without looking at the others:
///
///  * `start <= lastLine` holds for a prefix of the sorted order, found with a
///    binary search, which bounds the descent on the right.
///  * `end >= firstLine` is answered by the max heap: a subtree whose greatest
///    end line lies above the window holds no overlap and is pruned whole.
///    This is what makes a decoration starting far above the viewport and
///    spanning into it cost the same as any other overlap, instead of being
///    found by scanning everything between.
///
/// The descent only enters subtrees that hold an answer, so a query costs
/// `O(log D + K)` for the K reported decorations of the mostly non nested
/// ranges diagnostics are in practice, degrading to `O(log D + K log D)` if
/// every range nests inside another. Either way it never depends on the number
/// of decorations outside the window, which a scan does.
class _CodeDecorationIndex {
  _CodeDecorationIndex._(
    this._decorations,
    this._startLines,
    this._maxEndLines,
    this._leafOffset,
  );

  /// The index of an empty set of decorations.
  static final _CodeDecorationIndex empty = _CodeDecorationIndex._(
    const <CodeDecoration>[],
    _noLines,
    _noLines,
    0,
  );

  static final Int32List _noLines = Int32List(0);

  /// [decorations] sorted by start line.
  final List<CodeDecoration> _decorations;

  /// The start line of every decoration, in the order of [_decorations].
  final Int32List _startLines;

  /// The segment tree of end lines: node `i` holds the greatest end line of
  /// its subtree, its children are `2i` and `2i + 1`, and leaf `i` of
  /// [_decorations] lives at `_leafOffset + i`.
  final Int32List _maxEndLines;

  /// Where the leaves of [_maxEndLines] begin, a power of two so that the tree
  /// is complete and the node of a subrange is pure index arithmetic.
  final int _leafOffset;

  factory _CodeDecorationIndex.of(List<CodeDecoration> decorations) {
    final int count = decorations.length;
    if (count == 0) {
      return empty;
    }
    final Int32List starts = Int32List(count);
    final Int32List ends = Int32List(count);
    for (int i = 0; i < count; i++) {
      final CodeLineSelection range = decorations[i].range;
      // Read the line indices directly: CodeLineSelection.start and .end
      // allocate a position, and only the lines matter here.
      final int base = range.baseIndex;
      final int extent = range.extentIndex;
      starts[i] = base < extent ? base : extent;
      ends[i] = base < extent ? extent : base;
    }
    // Decorations of the same start line keep the order they were given in, so
    // that the order they are painted in stays predictable.
    final List<int> order = List<int>.generate(count, (int i) => i, growable: false);
    order.sort((int a, int b) {
      final int byStart = starts[a] - starts[b];
      return byStart != 0 ? byStart : a - b;
    });
    int leafOffset = 1;
    while (leafOffset < count) {
      leafOffset <<= 1;
    }
    final List<CodeDecoration> sorted = List<CodeDecoration>.generate(
      count,
      (int i) => decorations[order[i]],
      growable: false,
    );
    final Int32List startLines = Int32List(count);
    final Int32List maxEndLines = Int32List(leafOffset << 1);
    for (int i = 0; i < count; i++) {
      startLines[i] = starts[order[i]];
      maxEndLines[leafOffset + i] = ends[order[i]];
    }
    // A padding leaf must never be reported: line windows are never negative.
    for (int i = count; i < leafOffset; i++) {
      maxEndLines[leafOffset + i] = -1;
    }
    for (int i = leafOffset - 1; i > 0; i--) {
      maxEndLines[i] = max(maxEndLines[i << 1], maxEndLines[(i << 1) | 1]);
    }
    return _CodeDecorationIndex._(sorted, startLines, maxEndLines, leafOffset);
  }

  /// The decorations overlapping the closed line window
  /// `[firstLine, lastLine]`, in start line order.
  List<CodeDecoration> query(int firstLine, int lastLine) {
    final int count = _decorations.length;
    if (count == 0 || lastLine < firstLine) {
      return const <CodeDecoration>[];
    }
    final int from = firstLine < 0 ? 0 : firstLine;
    if (_maxEndLines[1] < from) {
      // Every decoration ends above the window.
      return const <CodeDecoration>[];
    }
    // The number of decorations that can start inside or above the window.
    int low = 0;
    int high = count;
    while (low < high) {
      final int middle = (low + high) >> 1;
      if (_startLines[middle] <= lastLine) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    if (low == 0) {
      // Every decoration starts below the window.
      return const <CodeDecoration>[];
    }
    final List<CodeDecoration> overlapping = <CodeDecoration>[];
    _collect(1, 0, _leafOffset - 1, low - 1, from, overlapping);
    return overlapping;
  }

  /// Reports the decorations of `[low, high]` that end at or below [firstLine],
  /// stopping at index [last].
  void _collect(
    int node,
    int low,
    int high,
    int last,
    int firstLine,
    List<CodeDecoration> overlapping,
  ) {
    if (low > last || _maxEndLines[node] < firstLine) {
      return;
    }
    if (low == high) {
      overlapping.add(_decorations[low]);
      return;
    }
    final int middle = (low + high) >> 1;
    _collect(node << 1, low, middle, last, firstLine, overlapping);
    _collect((node << 1) | 1, middle + 1, high, last, firstLine, overlapping);
  }
}
