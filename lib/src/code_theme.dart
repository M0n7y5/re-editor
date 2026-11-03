part of re_editor;

/// The code syntax highlighting theme. We use Re-Highlight as the syntax highlighting rule.
/// Re-Highlight provides some built-in syntax highlighting rules for dozens of programming languages,
/// and many theme styles.
///
/// Please see [Re-Highlight](https://reqable/re-highlight).
class CodeHighlightTheme {

  const CodeHighlightTheme({
    this.languages = const {},
    required this.theme,
    this.plugins = const [],
    this.languageId,
    this.grammars = const {},
  });

  /// Supported syntax highlighting language rules.
  final Map<String, CodeHighlightThemeMode> languages;

  /// The syntax highlighting style theme.
  final Map<String, TextStyle> theme;

  /// The plugins for syntax highlighting.
  final List<HLPlugin> plugins;

  /// The edited document's language: the key into [grammars] the highlight
  /// worker parses with. Null, or an id [grammars] lacks, renders plain text.
  ///
  /// It rides on the theme because the theme is already the per-document
  /// highlight config the editor hands its worker, and a changed theme already
  /// re-ships the document. [grammars] is the app's whole registry, so
  /// re_editor never names a grammar itself.
  final String? languageId;

  /// The tree-sitter grammars the application ships, by language id.
  final Map<String, Grammar> grammars;

  @override
  int get hashCode => Object.hash(languages, theme, plugins, languageId, grammars);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is CodeHighlightTheme
        && mapEquals(other.languages, languages)
        && mapEquals(other.theme, theme)
        && listEquals(other.plugins, plugins)
        && other.languageId == languageId
        && mapEquals(other.grammars, grammars);
  }

}

/// Define language rules and restrictions for highlighting.
///
/// Since the dart stack capacity is relatively small, stack overflow may occur
/// when executing syntax highlighting, so we added some restrictions to disable
/// syntax highlighting.
///
/// The issue see https://github.com/dart-lang/sdk/issues/48425
class CodeHighlightThemeMode {

  const CodeHighlightThemeMode({
    required this.mode,
    this.maxSize = 4 * 1024 * 1024,
    this.maxLineLength = 1 * 1024 * 1024,
  });

  /// Syntax highlighting language rule.
  final Mode mode;

  /// If the total text length is higher than this value, syntax highlighting
  /// will not be performed.
  ///
  /// The default value is 4MB.
  final int maxSize;

  /// If the text length of a line is higher than this value, syntax highlighting
  /// will not be performed.
  ///
  /// The default value is 1MB.
  final int maxLineLength;

  @override
  int get hashCode => Object.hash(mode, maxSize, maxLineLength);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is CodeHighlightThemeMode
        && mode == other.mode && maxSize == other.maxSize
        && maxLineLength == other.maxLineLength;
  }

}

extension CodeHighlightThemeModeExtension on Mode {

  CodeHighlightThemeMode get themeMode => CodeHighlightThemeMode(mode: this);

}