part of re_editor;

const int _kCodeLineSegamentDefaultSize = 256;

// ===========================================================================
// Persistent AVL tree of segments backing [CodeLines].
//
// Nodes are immutable; every mutation returns new nodes that share untouched
// subtrees with the original (structural sharing). Leaves hold a
// [CodeLineSegment] (a run of <=256 top-level [CodeLine]s); branches cache
// subtree summaries: `count` (top-level lines = CodeLines.length), `lineCount`
// (incl. folded chunks = CodeLines.lineCount) and `charCount`. `concat` and
// `splitAt` are the join-based primitives; the editor's per-edit
// `sublines(0,k) + add + addFrom(k+1)` recipe composes them in O(log N) instead
// of the previous O(N/256) segment-list rebuild. Snapshots (sublines / from)
// share structure, so undo retention and equality are O(1) on the common path.
// ===========================================================================

sealed class _LineNode {
  _LineNode(this.count, this.lineCount, this.charCount, this.height);

  final int count; // top-level CodeLine count
  final int lineCount; // including folded chunks
  final int charCount; // sum of CodeLine.charCount
  final int height; // AVL height (leaf == 1)
}

final class _LineLeaf extends _LineNode {
  _LineLeaf(this.segment)
    : super(segment.length, segment.lineCount, segment.charCount, 1);

  final CodeLineSegment segment;
}

final class _LineBranch extends _LineNode {
  _LineBranch(this.left, this.right)
    : super(
        left.count + right.count,
        left.lineCount + right.lineCount,
        left.charCount + right.charCount,
        1 + (left.height > right.height ? left.height : right.height),
      );

  final _LineNode left;
  final _LineNode right;
}

int _nodeHeight(_LineNode? n) => n == null ? 0 : n.height;

_LineNode _rotateLeft(_LineBranch x) {
  final _LineBranch r = x.right as _LineBranch;
  return _LineBranch(_LineBranch(x.left, r.left), r.right);
}

_LineNode _rotateRight(_LineBranch x) {
  final _LineBranch l = x.left as _LineBranch;
  return _LineBranch(l.left, _LineBranch(l.right, x.right));
}

/// Build a balanced node from [l] and [r] whose heights differ by at most 2
/// (standard AVL rebalance — used by [_concat] after a recursive descent).
_LineNode _mkBalanced(_LineNode l, _LineNode r) {
  if (_nodeHeight(l) > _nodeHeight(r) + 1) {
    final _LineBranch b = l as _LineBranch;
    if (_nodeHeight(b.left) >= _nodeHeight(b.right)) {
      return _rotateRight(_LineBranch(l, r));
    }
    return _rotateRight(_LineBranch(_rotateLeft(b), r));
  }
  if (_nodeHeight(r) > _nodeHeight(l) + 1) {
    final _LineBranch b = r as _LineBranch;
    if (_nodeHeight(b.right) >= _nodeHeight(b.left)) {
      return _rotateLeft(_LineBranch(l, r));
    }
    return _rotateLeft(_LineBranch(l, _rotateRight(b)));
  }
  return _LineBranch(l, r);
}

/// Concatenate two sequences (AVL join). O(height difference).
_LineNode? _concat(_LineNode? l, _LineNode? r) {
  if (l == null) return r;
  if (r == null) return l;
  if (_nodeHeight(l) > _nodeHeight(r) + 1) {
    final _LineBranch b = l as _LineBranch;
    return _mkBalanced(b.left, _concat(b.right, r)!);
  }
  if (_nodeHeight(r) > _nodeHeight(l) + 1) {
    final _LineBranch b = r as _LineBranch;
    return _mkBalanced(_concat(l, b.left)!, b.right);
  }
  return _LineBranch(l, r);
}

/// Split the sequence at top-level index [i]: left gets `[0, i)`, right `[i, end)`.
(_LineNode?, _LineNode?) _splitAt(_LineNode? node, int i) {
  if (node == null) {
    return (null, null);
  }
  if (node is _LineLeaf) {
    if (i <= 0) {
      return (null, node);
    }
    if (i >= node.count) {
      return (node, null);
    }
    final List<CodeLine> lines = node.segment.codeLines;
    return (
      _LineLeaf(CodeLineSegment.of(codeLines: lines.sublist(0, i))),
      _LineLeaf(CodeLineSegment.of(codeLines: lines.sublist(i))),
    );
  }
  final _LineBranch b = node as _LineBranch;
  final int lc = b.left.count;
  if (i < lc) {
    final (_LineNode? ll, _LineNode? lr) = _splitAt(b.left, i);
    return (ll, _concat(lr, b.right));
  }
  if (i > lc) {
    final (_LineNode? rl, _LineNode? rr) = _splitAt(b.right, i - lc);
    return (_concat(b.left, rl), rr);
  }
  return (b.left, b.right);
}

/// Build a balanced tree from [leaves] `[lo, hi)` via median split (AVL-valid).
_LineNode? _buildFromLeaves(List<_LineLeaf> leaves, int lo, int hi) {
  if (lo >= hi) {
    return null;
  }
  if (hi - lo == 1) {
    return leaves[lo];
  }
  final int mid = lo + ((hi - lo) >> 1);
  return _LineBranch(
    _buildFromLeaves(leaves, lo, mid)!,
    _buildFromLeaves(leaves, mid, hi)!,
  );
}

List<_LineLeaf> _chunkToLeaves(List<CodeLine> all) {
  final List<_LineLeaf> leaves = [];
  for (int i = 0; i < all.length; i += _kCodeLineSegamentDefaultSize) {
    final int end = i + _kCodeLineSegamentDefaultSize < all.length
        ? i + _kCodeLineSegamentDefaultSize
        : all.length;
    leaves.add(_LineLeaf(CodeLineSegment.of(codeLines: all.sublist(i, end))));
  }
  return leaves;
}

class CodeLines {
  CodeLines._(this._root);

  /// Builds a buffer from explicit [segments] (each becomes one leaf). Kept for
  /// API compatibility; runtime construction prefers [CodeLines.of].
  factory CodeLines(List<CodeLineSegment> segments) {
    final List<_LineLeaf> leaves = [];
    for (final CodeLineSegment segment in segments) {
      if (segment.isEmpty) {
        continue;
      }
      leaves.add(_LineLeaf(segment));
    }
    return CodeLines._(_buildFromLeaves(leaves, 0, leaves.length));
  }

  factory CodeLines.empty() => CodeLines._(null);

  factory CodeLines.fromText(String text) {
    return text.codeLines;
  }

  /// An independent snapshot. The tree is immutable, so this shares structure in
  /// O(1); mutating either side copies only the touched root-to-leaf path.
  factory CodeLines.from(CodeLines codeLines) => CodeLines._(codeLines._root);

  factory CodeLines.of(Iterable<CodeLine> elements) {
    final List<CodeLine> all = elements is List<CodeLine>
        ? elements
        : elements.toList();
    if (all.isEmpty) {
      return CodeLines._(null);
    }
    final List<_LineLeaf> leaves = _chunkToLeaves(all);
    return CodeLines._(_buildFromLeaves(leaves, 0, leaves.length));
  }

  _LineNode? _root;
  List<CodeLineSegment>? _segmentsCache;

  /// In-order leaves, materialized lazily (cleared on mutation). Reads only.
  List<CodeLineSegment> get segments => _segmentsCache ??= _collectSegments();

  List<CodeLineSegment> _collectSegments() {
    final List<CodeLineSegment> out = [];
    void walk(_LineNode? n) {
      if (n == null) {
        return;
      }
      if (n is _LineLeaf) {
        out.add(n.segment);
        return;
      }
      final _LineBranch b = n as _LineBranch;
      walk(b.left);
      walk(b.right);
    }

    walk(_root);
    return out;
  }

  CodeLine get first {
    if (_root == null) {
      throw StateError('No element');
    }
    return this[0];
  }

  CodeLine get last {
    if (_root == null) {
      throw StateError('No element');
    }
    return this[length - 1];
  }

  int get length => _root?.count ?? 0;

  bool get isEmpty => length == 0;

  bool get isNotEmpty => !isEmpty;

  int get lineCount => _root?.lineCount ?? 0;

  int get charCount => _root?.charCount ?? 0;

  CodeLine operator [](int index) {
    _LineNode? node = _root;
    if (node == null || index < 0 || index >= node.count) {
      throw RangeError.range(index, 0, length - 1);
    }
    while (node is _LineBranch) {
      final _LineBranch b = node;
      if (index < b.left.count) {
        node = b.left;
      } else {
        index -= b.left.count;
        node = b.right;
      }
    }
    return (node as _LineLeaf).segment.codeLines[index];
  }

  void operator []=(int index, CodeLine value) {
    if (_root == null || index < 0 || index >= _root!.count) {
      throw RangeError.range(index, 0, length - 1);
    }
    _root = _set(_root!, index, value);
    _segmentsCache = null;
  }

  _LineNode _set(_LineNode node, int index, CodeLine value) {
    if (node is _LineLeaf) {
      final List<CodeLine> lines = List<CodeLine>.of(node.segment.codeLines);
      lines[index] = value;
      return _LineLeaf(CodeLineSegment.of(codeLines: lines));
    }
    final _LineBranch b = node as _LineBranch;
    if (index < b.left.count) {
      return _LineBranch(_set(b.left, index, value), b.right);
    }
    return _LineBranch(b.left, _set(b.right, index - b.left.count, value));
  }

  void add(CodeLine value) {
    _root = _append(_root, value);
    _segmentsCache = null;
  }

  _LineNode _append(_LineNode? node, CodeLine value) {
    if (node == null) {
      return _LineLeaf(CodeLineSegment.of(codeLines: [value]));
    }
    if (node is _LineLeaf) {
      if (node.segment.length < _kCodeLineSegamentDefaultSize) {
        return _LineLeaf(
          CodeLineSegment.of(codeLines: [...node.segment.codeLines, value]),
        );
      }
      return _LineBranch(
        node,
        _LineLeaf(CodeLineSegment.of(codeLines: [value])),
      );
    }
    final _LineBranch b = node as _LineBranch;
    return _mkBalanced(b.left, _append(b.right, value));
  }

  void addAll(Iterable<CodeLine> iterable) {
    final CodeLines other = CodeLines.of(iterable);
    if (other._root == null) {
      return;
    }
    _root = _concat(_root, other._root);
    _segmentsCache = null;
  }

  void addFrom(CodeLines codeLines, int start, [int? end]) {
    final CodeLines sub = codeLines.sublines(start, end);
    if (sub._root == null) {
      return;
    }
    _root = _concat(_root, sub._root);
    _segmentsCache = null;
  }

  CodeLines sublines(int start, [int? end]) {
    final int len = length;
    end ??= len;
    if (end > len) {
      throw RangeError.range(end, 0, len - 1);
    }
    if (start > end) {
      throw RangeError('start $start should be less than end $end');
    }
    if (start == end) {
      return CodeLines._(null);
    }
    final (_, _LineNode? rest) = _splitAt(_root, start);
    final (_LineNode? mid, _) = _splitAt(rest, end - start);
    return CodeLines._(mid);
  }

  void clear() {
    _root = null;
    _segmentsCache = null;
  }

  String asString(TextLineBreak lineBreak, [bool expandChunks = true]) {
    final StringBuffer sb = StringBuffer();
    final int len = length;
    int count = 0;
    void walk(_LineNode? n) {
      if (n == null) {
        return;
      }
      if (n is _LineLeaf) {
        for (final CodeLine codeLine in n.segment.codeLines) {
          count++;
          if (expandChunks) {
            sb.write(codeLine.asString(0, lineBreak));
          } else {
            sb.write(codeLine.text);
          }
          if (count != len) {
            sb.write(lineBreak.value);
          }
        }
        return;
      }
      final _LineBranch b = n as _LineBranch;
      walk(b.left);
      walk(b.right);
    }

    walk(_root);
    return sb.toString();
  }

  /// Display-line index of top-level [index] (sum of `lineCount` before it).
  int index2lineIndex(int index) {
    if (index < 0 || index >= length) {
      return -1;
    }
    return _lineCountBefore(index);
  }

  int _lineCountBefore(int index) {
    _LineNode? node = _root;
    int acc = 0;
    while (node is _LineBranch) {
      final _LineBranch b = node;
      if (index < b.left.count) {
        node = b.left;
      } else {
        acc += b.left.lineCount;
        index -= b.left.count;
        node = b.right;
      }
    }
    final CodeLineSegment? seg = (node as _LineLeaf?)?.segment;
    if (seg != null) {
      for (int j = 0; j < index; j++) {
        acc += seg.codeLines[j].lineCount;
      }
    }
    return acc;
  }

  /// Sum of `CodeLine.charCount` for top-level lines before [index]. O(log N).
  int charCountBefore(int index) {
    _LineNode? node = _root;
    int acc = 0;
    while (node is _LineBranch) {
      final _LineBranch b = node;
      if (index < b.left.count) {
        node = b.left;
      } else {
        acc += b.left.charCount;
        index -= b.left.count;
        node = b.right;
      }
    }
    final CodeLineSegment? seg = (node as _LineLeaf?)?.segment;
    if (seg != null) {
      for (int j = 0; j < index; j++) {
        acc += seg.codeLines[j].charCount;
      }
    }
    return acc;
  }

  /// Inverse of a flat per-line offset (`charCount + lineBreak` per line) to a
  /// `(lineIndex, offsetInLine)` pair, clamping into the last line. O(log N).
  (int, int) lineOffsetForFlat(int target, int br) {
    final _LineNode? root = _root;
    if (root == null) {
      return (0, 0);
    }
    final int n = root.count;
    _LineNode? node = root;
    int index = 0;
    int acc = 0; // flat offset at the start of `node`
    while (node is _LineBranch) {
      final _LineBranch b = node;
      final int leftFlat = b.left.charCount + b.left.count * br;
      if (target < acc + leftFlat) {
        node = b.left;
      } else {
        acc += leftFlat;
        index += b.left.count;
        node = b.right;
      }
    }
    final List<CodeLine> lines = (node as _LineLeaf).segment.codeLines;
    for (int j = 0; j < lines.length; j++) {
      final int cc = lines[j].charCount;
      final int end = acc + cc + br;
      if (target < end || index == n - 1) {
        return (index, (target - acc).clamp(0, cc));
      }
      acc = end;
      index++;
    }
    return (n - 1, 0);
  }

  CodeLineIndex lineIndex2Index(int lineIndex) {
    if (lineIndex < 0 || _root == null) {
      return const CodeLineIndex(-1, -1);
    }
    _LineNode? node = _root;
    int index = 0;
    int remaining = lineIndex;
    while (node is _LineBranch) {
      final _LineBranch b = node;
      if (remaining < b.left.lineCount) {
        node = b.left;
      } else {
        remaining -= b.left.lineCount;
        index += b.left.count;
        node = b.right;
      }
    }
    final CodeLineSegment? seg = (node as _LineLeaf?)?.segment;
    if (seg == null) {
      return const CodeLineIndex(-1, -1);
    }
    final List<CodeLine> lines = seg.codeLines;
    for (int i = 0; i < lines.length; i++) {
      final int lc = lines[i].lineCount;
      if (remaining < lc) {
        if (remaining == 0) {
          return CodeLineIndex(index + i, -1);
        }
        final List<CodeLine> chunks = lines[i].chunks;
        int start = 1; // the visible line occupies span 0; chunks follow
        for (int c = 0; c < chunks.length; c++) {
          final int end = start + chunks[c].lineCount;
          if (remaining >= start && remaining < end) {
            return CodeLineIndex(index + i, c);
          }
          start = end;
        }
        return CodeLineIndex(index + i, -1);
      }
      remaining -= lc;
    }
    return const CodeLineIndex(-1, -1);
  }

  List<CodeLine> toList() {
    final List<CodeLine> codeLines = [];
    void walk(_LineNode? n) {
      if (n == null) {
        return;
      }
      if (n is _LineLeaf) {
        codeLines.addAll(n.segment.codeLines);
        return;
      }
      final _LineBranch b = n as _LineBranch;
      walk(b.left);
      walk(b.right);
    }

    walk(_root);
    return codeLines;
  }

  bool equals(CodeLines? codeLines) {
    if (codeLines == null) {
      return false;
    }
    if (identical(_root, codeLines._root)) {
      return true;
    }
    if (length != codeLines.length ||
        lineCount != codeLines.lineCount ||
        charCount != codeLines.charCount) {
      return false;
    }
    return listEquals(toList(), codeLines.toList());
  }

  @override
  int get hashCode => Object.hash(
    length,
    lineCount,
    charCount,
    _root == null ? 0 : first,
    _root == null ? 0 : last,
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is CodeLines && equals(other);
  }

  @override
  String toString() {
    return '[ ${segments.join(',')} ]';
  }

  /// Asserts the AVL balance invariant and summary consistency of every node.
  @visibleForTesting
  void debugValidate() {
    int check(_LineNode? n) {
      if (n == null) {
        return 0;
      }
      if (n is _LineLeaf) {
        if (n.count != n.segment.length) {
          throw StateError('leaf count mismatch');
        }
        if (n.height != 1) {
          throw StateError('leaf height != 1');
        }
        return 1;
      }
      final _LineBranch b = n as _LineBranch;
      final int hl = check(b.left);
      final int hr = check(b.right);
      if ((hl - hr).abs() > 1) {
        throw StateError('AVL imbalance: $hl vs $hr');
      }
      if (b.height != 1 + (hl > hr ? hl : hr)) {
        throw StateError('height mismatch');
      }
      if (b.count != b.left.count + b.right.count) {
        throw StateError('count mismatch');
      }
      if (b.lineCount != b.left.lineCount + b.right.lineCount) {
        throw StateError('lineCount mismatch');
      }
      if (b.charCount != b.left.charCount + b.right.charCount) {
        throw StateError('charCount mismatch');
      }
      return b.height;
    }

    check(_root);
  }
}

class CodeLineSegment with ListMixin<CodeLine> {
  const CodeLineSegment({required this.codeLines});

  factory CodeLineSegment.of({required List<CodeLine> codeLines}) =>
      _CodeLineSegmentQuckLineCount(codeLines: codeLines);

  final List<CodeLine> codeLines;

  @override
  int get length => codeLines.length;

  int get lineCount => codeLines.fold(
    0,
    (previousValue, element) => previousValue += element.lineCount,
  );

  int get charCount => codeLines.fold(
    0,
    (previousValue, element) => previousValue += element.charCount,
  );

  @override
  CodeLine operator [](int index) {
    return codeLines[index];
  }

  @override
  void operator []=(int index, CodeLine value) {
    throw UnsupportedError('CodeLineSegment is immutable');
  }

  @override
  set length(int newLength) {
    throw UnsupportedError('CodeLineSegment is immutable');
  }

  @override
  void add(CodeLine element) {
    throw UnsupportedError('CodeLineSegment is immutable');
  }

  CodeLineSegment clone([int start = 0, int? end]) =>
      CodeLineSegment.of(codeLines: codeLines.sublist(start, end));

  CodeLineSegment copyWith({List<CodeLine>? codeLines}) {
    return CodeLineSegment.of(codeLines: codeLines ?? this.codeLines);
  }

  @override
  int get hashCode => Object.hash(Object.hashAll(codeLines), lineCount);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is CodeLineSegment &&
        listEquals(other.codeLines, codeLines) &&
        other.lineCount == lineCount;
  }

  @override
  String toString() {
    return '[ ${join(',')} ]';
  }
}
