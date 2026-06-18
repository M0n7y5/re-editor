part of re_editor;

class _CodeLineSegmentQuckLineCount extends CodeLineSegment {
  late final int _lineCount;
  late final int _charCount;

  _CodeLineSegmentQuckLineCount({required super.codeLines}) {
    _lineCount = super.lineCount;
    _charCount = super.charCount;
  }

  @override
  int get lineCount => _lineCount;

  @override
  int get charCount => _charCount;
}
