part of re_editor;

class _CodeHighlighter extends ValueNotifier<_HighlightResults> {

  final BuildContext _context;
  final _CodeParagraphProvider _provider;
  final _CodeHighlightEngine _engine;

  CodeLineEditingController _controller;
  CodeHighlightTheme? _theme;

  // Latest-wins coalescing + viewport state for windowed highlighting.
  static const int _kHighlightMargin = 50;
  int _firstVisible = 0;
  int _lastVisible = 0;
  CodeLines? _sentCodeLines; // buffer last shipped to the worker (null = none)
  bool _running = false; // a worker run is in flight
  bool _dirty = false; // a (re)highlight is requested
  bool _docDirty = false; // document changed since the last shipped run

  _CodeHighlighter({
    required BuildContext context,
    required CodeLineEditingController controller,
    CodeHighlightTheme? theme,
  }) : _context = context,
    _provider = _CodeParagraphProvider(),
    _controller = controller,
    _theme = theme,
    _engine = _CodeHighlightEngine(theme),
    super(_HighlightResults.empty) {
    _controller.addListener(_onCodesChanged);
    _docDirty = true;
    _dirty = true;
    _pump();
  }

  set controller(CodeLineEditingController value) {
    if (_controller == value) {
      return;
    }
    _controller.removeListener(_onCodesChanged);
    _controller = value;
    _controller.addListener(_onCodesChanged);
    _sentCodeLines = null;
    _docDirty = true;
    _dirty = true;
    _pump();
  }

  set theme(CodeHighlightTheme? value) {
    if (_theme == value) {
      return;
    }
    _theme = value;
    _engine.theme = value;
    _sentCodeLines = null;
    _docDirty = value != null;
    _dirty = true;
    _pump();
  }

  IParagraph build({
    required int index,
    required TextStyle style,
    required double maxWidth,
    int? maxLengthSingleLineRendering,
  }) {
    _provider.updateBaseStyle(style);
    _provider.updateMaxLengthSingleLineRendering(maxLengthSingleLineRendering);
    return _provider.build(_controller.buildTextSpan(
      context: _context,
      index: index,
      textSpan: _buildSpan(index, style),
      style: style
    ), maxWidth);
  }

  void clearCache() {
    _provider.clearCache();
  }

  @override
  void dispose() {
    _controller.removeListener(_onCodesChanged);
    _engine.dispose();
    super.dispose();
  }

  TextSpan _buildSpan(int index, TextStyle style) {
    final String text = _controller.codeLines[index].text;
    final _HighlightResult? result = value[index];
    if (result == null || result.nodes.isEmpty) {
      return TextSpan(
        text: text,
        style: style
      );
    }
    if (result.source == text) {
      return _buildSpanFromNodes(result.nodes, style);
    }
    // Diff the changes and reuse node to avoid style blink.
    final List<_HighlightNode> startNodes = [];
    int start = 0;
    int end = text.length;
    for (int i = 0; i < result.nodes.length && start < end; i++) {
      final String value = result.nodes[i].value;
      if (text.startsWith(value, start)) {
        startNodes.add(result.nodes[i]);
        start += value.length;
      } else {
        break;
      }
    }
    final List<_HighlightNode> endNodes = [];
    for (int i = result.nodes.length - 1; i >= 0 && start < end; i--) {
      final String value = result.nodes[i].value;
      if (text.substring(start, end).endsWith(value)) {
        endNodes.insert(0, result.nodes[i]);
        end -= value.length;
      } else {
        break;
      }
    }
    final _HighlightNode? midNode;
    if (startNodes.isEmpty) {
      midNode = _HighlightNode(text.substring(start, end), result.nodes[0].className);
    } else if (startNodes.length < result.nodes.length) {
      midNode = _HighlightNode(text.substring(start, end), result.nodes[startNodes.length].className);
    } else if (end > start){
      midNode = _HighlightNode(text.substring(start, end), result.nodes.last.className);
    } else {
      midNode = null;
    }
    return _buildSpanFromNodes([
      ...startNodes,
      if (midNode != null)
        midNode,
      ...endNodes
    ], style);
  }

  TextSpan _buildSpanFromNodes(List<_HighlightNode> nodes, TextStyle baseStyle) {
    return TextSpan(
      children: nodes.map((e) => TextSpan(
          text: e.value,
          style: _findStyle(e.className)
        )).toList(),
      style: baseStyle
    );
  }

  TextStyle? _findStyle(String? className) {
    String? name = className;
    while (name != null && name.isNotEmpty) {
      final TextStyle? style = _theme?.theme[name];
      if (style != null) {
        return style;
      }
      // tree-sitter capture names nest with '.':
      // `string.escape` -> `string`, `function.method.call` -> `function`.
      final int dot = name.lastIndexOf('.');
      if (dot >= 0) {
        name = name.substring(0, dot);
        continue;
      }
      // hl.js class names nest with '-': `title-function_` -> `function_`.
      final int dash = name.indexOf('-');
      if (dash < 0) {
        break;
      }
      name = name.substring(dash + 1);
    }
    return null;
  }

  void _onCodesChanged() {
    if (_controller.preValue?.codeLines == _controller.codeLines) {
      return;
    }
    _docDirty = true;
    _dirty = true;
    _pump();
  }

  /// Called by the render object each layout with the strict visible line
  /// range. Widens the highlight window if it changed; a no-op otherwise.
  void setViewport(int first, int last) {
    if (first == _firstVisible && last == _lastVisible) {
      return;
    }
    _firstVisible = first;
    _lastVisible = last;
    _dirty = true;
    _pump();
  }

  // Dispatches at most one worker run at a time, always against the latest
  // viewport, shipping the full buffer only when the document changed since the
  // last shipped run. Collapses bursts of scroll/edit notifications into one
  // trailing run (the isolate tasker is FIFO and does not coalesce).
  void _pump() {
    if (_running || !_dirty) {
      return;
    }
    _dirty = false;
    if (_theme == null) {
      _docDirty = false;
      value = _HighlightResults.empty;
      return;
    }
    final CodeLines codeLines = _controller.codeLines;
    final bool ship = _docDirty || _sentCodeLines == null;
    _docDirty = false;
    if (ship) {
      _sentCodeLines = codeLines;
    }
    final int lineCount = codeLines.length;
    final int first = max(0, _firstVisible - _kHighlightMargin);
    final int last = min(lineCount - 1, _lastVisible + _kHighlightMargin);
    _running = true;
    _engine.run(ship ? codeLines : null, first, last, _onResult);
  }

  void _onResult(_HighlightResults result) {
    value = result;
    _running = false;
    _pump();
  }

}

class _CodeHighlightEngine {

  late final _IsolateTasker<_HighlightPayload, _HighlightResults> _tasker;

  CodeHighlightTheme? _theme;

  _CodeHighlightEngine(final CodeHighlightTheme? theme) {
    _theme = theme;
    _tasker = _IsolateTasker<_HighlightPayload, _HighlightResults>('CodeHighlightEngine', _run);
  }

  // A null theme disables highlighting (the editor renders plain text).
  set theme(CodeHighlightTheme? value) {
    _theme = value;
  }

  void dispose() {
    _tasker.close();
  }

  void run(CodeLines? codes, int firstLine, int lastLine,
      IsolateCallback<_HighlightResults> callback) {
    if (_theme == null) {
      callback(_HighlightResults.empty);
      return;
    }
    _tasker.run(_HighlightPayload(codes, firstLine, lastLine), callback);
  }

  @pragma('vm:entry-point')
  static _HighlightResults _run(_HighlightPayload payload) {
    final DartHighlighter highlighter = _isoHighlighter ??= DartHighlighter();
    final CodeLines? codes = payload.codes;
    if (codes != null) {
      highlighter.update(codes.asString(TextLineBreak.lf, false));
    }
    final WindowHighlight window =
        highlighter.highlightWindow(payload.firstLine, payload.lastLine);
    final List<_HighlightResult> results = <_HighlightResult>[
      for (final LineHighlight line in window.lines)
        _buildLineResult(line.text, line.ranges),
    ];
    return _HighlightResults(window.firstLine, results);
  }

}

class _HighlightPayload {

  final CodeLines? codes;
  final int firstLine;
  final int lastLine;

  const _HighlightPayload(this.codes, this.firstLine, this.lastLine);

}

/// The tree-sitter highlighter, lazily created inside (and owned by) the
/// highlight worker isolate. The engine keeps a single persistent worker, so
/// the parser + compiled query are built once and reused across runs.
DartHighlighter? _isoHighlighter;

/// Converts one line's [ranges] into a full-coverage [_HighlightResult]: gap
/// nodes (no class) fill the unstyled stretches so the node values concatenate
/// to exactly [text], letting `_buildSpan` take its `source == text` fast path.
/// A line with no ranges yields empty nodes (plain text).
_HighlightResult _buildLineResult(String text, List<StyledRange> ranges) {
  if (ranges.isEmpty) {
    return _HighlightResult(const []);
  }
  final List<_HighlightNode> nodes = <_HighlightNode>[];
  int cursor = 0;
  for (final StyledRange r in ranges) {
    final int start = r.start < 0 ? 0 : r.start;
    final int end = r.end > text.length ? text.length : r.end;
    if (start >= end) {
      continue;
    }
    if (start > cursor) {
      nodes.add(_HighlightNode(text.substring(cursor, start)));
    }
    nodes.add(_HighlightNode(text.substring(start, end), r.capture));
    cursor = end;
  }
  if (cursor < text.length) {
    nodes.add(_HighlightNode(text.substring(cursor)));
  }
  return _HighlightResult(nodes);
}

class _HighlightResult {
  final List<_HighlightNode> nodes;

  _HighlightResult(this.nodes);

  String get source => nodes.map((e) => e.value).join();
}

/// A windowed batch of per-line highlight results: [results] are the styled
/// lines starting at absolute line index [start]. Indexing by an absolute line
/// outside the window yields null, so the consumer falls back to plain text.
class _HighlightResults {
  const _HighlightResults(this.start, this.results);

  final int start;
  final List<_HighlightResult> results;

  static const _HighlightResults empty =
      _HighlightResults(0, <_HighlightResult>[]);

  _HighlightResult? operator [](int index) {
    final int i = index - start;
    return (i < 0 || i >= results.length) ? null : results[i];
  }
}

class _HighlightNode {

  final String? className;
  final String value;

  const _HighlightNode(this.value, [this.className]);
}
