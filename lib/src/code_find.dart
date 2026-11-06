part of re_editor;

typedef CodeFindBuilder =
    PreferredSizeWidget Function(
      BuildContext context,
      CodeFindController controller,
      bool readonly,
    );

class CodeFindValue {
  final CodeFindOption option;
  final bool replaceMode;
  final CodeFindResult? result;
  final bool searching;

  const CodeFindValue({
    required this.option,
    required this.replaceMode,
    this.result,
    this.searching = false,
  });

  const CodeFindValue.empty()
    : this(
        option: const CodeFindOption(
          pattern: '',
          caseSensitive: false,
          regex: false,
        ),
        replaceMode: false,
      );

  CodeFindValue copyWith({
    CodeFindOption? option,
    bool? replaceMode,
    required CodeFindResult? result,
    bool? searching,
  }) {
    return CodeFindValue(
      option: option ?? this.option,
      replaceMode: replaceMode ?? this.replaceMode,
      result: result,
      searching: searching ?? this.searching,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is CodeFindValue &&
        other.option == option &&
        other.replaceMode == replaceMode &&
        other.result == result &&
        other.searching == searching;
  }

  @override
  int get hashCode => Object.hash(option, replaceMode, result, searching);

  @override
  String toString() {
    return '{option: $option replaceMode: $replaceMode result: $result searching:$searching}';
  }
}

class CodeFindOption {
  final String pattern;
  final bool caseSensitive;
  final bool regex;

  /// Only matches whose neighbours are not word characters: `foo` in
  /// `foo.bar` but not in `foobar`.
  final bool wholeWord;

  /// Only matches inside this range, in unfolded line coordinates (the
  /// controller's `unfoldLineSelection` at the moment it was captured); null
  /// searches the whole document.
  final CodeLineSelection? range;

  const CodeFindOption({
    required this.pattern,
    required this.caseSensitive,
    required this.regex,
    this.wholeWord = false,
    this.range,
  });

  bool get inSelection => range != null;

  CodeFindOption copyWith({
    String? pattern,
    bool? caseSensitive,
    bool? regex,
    bool? wholeWord,
    CodeLineSelection? range,
    bool clearRange = false,
  }) {
    return CodeFindOption(
      pattern: pattern ?? this.pattern,
      caseSensitive: caseSensitive ?? this.caseSensitive,
      regex: regex ?? this.regex,
      wholeWord: wholeWord ?? this.wholeWord,
      range: clearRange ? null : (range ?? this.range),
    );
  }

  RegExp? get regExp {
    final String source = regex ? pattern : RegExp.escape(pattern);
    // Lookarounds rather than `\b`, so a pattern starting or ending in a
    // non-word character (`.foo`) still requires a boundary at its edges.
    final String bounded = wholeWord ? '(?<!\\w)(?:$source)(?!\\w)' : source;
    try {
      return RegExp(bounded, caseSensitive: caseSensitive);
    } on FormatException {
      return null;
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is CodeFindOption &&
        other.pattern == pattern &&
        other.caseSensitive == caseSensitive &&
        other.regex == regex &&
        other.wholeWord == wholeWord &&
        other.range == range;
  }

  @override
  int get hashCode =>
      Object.hash(pattern, caseSensitive, regex, wholeWord, range);

  @override
  String toString() {
    return '{pattern: $pattern caseSensitive: $caseSensitive regex: $regex wholeWord: $wholeWord range: $range}';
  }
}

class CodeFindResult {
  final int index;
  final List<CodeLineSelection> matches;
  final CodeFindOption option;
  final CodeLines codeLines;
  final bool dirty;

  const CodeFindResult({
    required this.index,
    required this.matches,
    required this.option,
    required this.codeLines,
    required this.dirty,
  });

  CodeFindResult get previous =>
      copyWith(index: index == 0 ? matches.length - 1 : index - 1);

  CodeFindResult get next =>
      copyWith(index: index == matches.length - 1 ? 0 : index + 1);

  CodeLineSelection? get currentMatch => index == -1 ? null : matches[index];

  CodeFindResult copyWith({
    int? index,
    List<CodeLineSelection>? matches,
    CodeFindOption? option,
    CodeLines? codeLines,
    bool? dirty,
  }) {
    return CodeFindResult(
      index: index ?? this.index,
      matches: matches ?? this.matches,
      option: option ?? this.option,
      codeLines: codeLines ?? this.codeLines,
      dirty: dirty ?? this.dirty,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is CodeFindResult &&
        other.index == index &&
        listEquals(other.matches, matches) &&
        other.option == option &&
        other.codeLines.equals(codeLines) &&
        other.dirty == dirty;
  }

  @override
  int get hashCode => Object.hash(index, matches, option, codeLines, dirty);
}

abstract class CodeFindController extends ValueNotifier<CodeFindValue?> {
  factory CodeFindController(
    CodeLineEditingController controller, [
    CodeFindValue? value,
  ]) => _CodeFindControllerImpl(controller, value);

  TextEditingController get findInputController;

  TextEditingController get replaceInputController;

  FocusNode get findInputFocusNode;

  FocusNode get replaceInputFocusNode;

  List<CodeLineSelection>? get allMatchSelections;

  CodeLineSelection? get currentMatchSelection;

  void findMode();

  void replaceMode();

  void focusOnFindInput();

  void focusOnReplaceInput();

  void toggleMode();

  void close();

  void toggleRegex();

  void toggleCaseSensitive();

  void toggleWholeWord();

  /// Restricts the search to the editor's selection as it is now, or, when
  /// already restricted, searches the whole document again. A collapsed
  /// selection restricts nothing.
  void toggleInSelection();

  void previousMatch();

  void nextMatch();

  void replaceMatch();

  void replaceAllMatches();

  CodeLineSelection? convertMatchToSelection(CodeLineSelection match);
}
