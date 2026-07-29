part of re_editor;

const double _kDefaultTextSize = 13.0;
const double _kDefaultFontHeight = 1.4;
const double _kDefaultCaretWidth = 2;
const EdgeInsetsGeometry _kDefaultPadding = EdgeInsets.all(5);
const Duration _kCursorBlinkHalfPeriod = Duration(milliseconds: 500);

class _CodeEditable extends StatefulWidget {

  final GlobalKey editorKey;
  final String? hint;
  final CodeIndicatorBuilder? indicatorBuilder;
  final CodeScrollbarBuilder? scrollbarBuilder;
  final double? verticalScrollbarWidth;
  final double? horizontalScrollbarHeight;
  final TextStyle textStyle;
  final Color? hintTextColor;
  final Color? backgroundColor;
  final Color selectionColor;
  final Color highlightColor;
  final Color cursorColor;
  final Color? cursorLineColor;
  final Color? bracketMatchColor;
  final Color? chunkIndicatorColor;
  final CodeDecorationController? decorations;
  final double cursorWidth;
  final bool showCursorWhenReadOnly;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Widget? sperator;
  final Border? border;
  final BorderRadius? borderRadius;
  final Clip clipBehavior;
  final ValueChanged<CodeLineEditingValue>? onChanged;
  final FocusNode focusNode;
  final CodeLineEditingController controller;
  final _CodeInputController inputController;
  final _CodeFloatingCursorController floatingCursorController;
  final CodeHighlightTheme? codeTheme;
  final bool readOnly;
  final bool autofocus;
  final bool wordWrap;
  final int? maxLengthSingleLineRendering;
  final CodeFindController findController;
  final CodeScrollController scrollController;
  final CodeChunkController chunkController;
  final LayerLink startHandleLayerLink;
  final LayerLink endHandleLayerLink;
  final LayerLink toolbarLayerLink;
  final _SelectionOverlayController selectionOverlayController;

  const _CodeEditable({
    required this.editorKey,
    this.hint,
    this.indicatorBuilder,
    this.scrollbarBuilder,
    this.verticalScrollbarWidth,
    this.horizontalScrollbarHeight,
    required this.textStyle,
    this.hintTextColor,
    this.backgroundColor,
    required this.selectionColor,
    required this.highlightColor,
    required this.cursorColor,
    this.cursorLineColor,
    this.bracketMatchColor,
    this.chunkIndicatorColor,
    this.decorations,
    required this.cursorWidth,
    required this.showCursorWhenReadOnly,
    required this.padding,
    required this.margin,
    required this.sperator,
    this.border,
    this.borderRadius,
    this.clipBehavior = Clip.none,
    this.onChanged,
    required this.focusNode,
    required this.controller,
    required this.inputController,
    required this.floatingCursorController,
    required this.codeTheme,
    required this.readOnly,
    required this.autofocus,
    required this.wordWrap,
    this.maxLengthSingleLineRendering,
    required this.findController,
    required this.scrollController,
    required this.chunkController,
    required this.startHandleLayerLink,
    required this.endHandleLayerLink,
    required this.toolbarLayerLink,
    required this.selectionOverlayController,
  });

  @override
  State<StatefulWidget> createState() => _CodeEditableState();

}

class _CodeEditableState extends State<_CodeEditable> with AutomaticKeepAliveClientMixin<_CodeEditable>, SingleTickerProviderStateMixin
    implements _CodeAutocompleteHost {

  late bool _didAutoFocus;
  late final _CodeCursorBlinkController _cursorController;

  late AnimationController _floatingCursorAnimationController;

  late _CodeHighlighter _highlighter;
  late CodeIndicatorValueNotifier _codeIndicatorValueNotifier;

  /// The autocomplete overlay above this editor, or null when there is none.
  /// Resolved in [didChangeDependencies] rather than looked up per keystroke.
  _CodeAutocompleteState? _autocompleteState;

  /// The pending ask for autocomplete prompts.
  ///
  /// One coalescing, cancellable timer rather than a `Future.delayed` per
  /// keystroke: a burst of N characters used to schedule N full re-shows, none of
  /// which could be called off once the user moved on. Latest wins, and every
  /// path that closes the overlay drops the pending ask with it.
  Timer? _autocompleteDebounce;

  @override
  bool get wantKeepAlive => widget.focusNode.hasFocus;

  @override
  void initState() {
    super.initState();
    _didAutoFocus = false;

    widget.controller.addListener(_onCodeInputChanged);
    widget.inputController.addListener(_onCodeUserInputChanged);

    _highlighter = _CodeHighlighter(
      context: context,
      controller: widget.controller,
      theme: widget.codeTheme,
    );

    _codeIndicatorValueNotifier = CodeIndicatorValueNotifier(null);

    _cursorController = _CodeCursorBlinkController();
    _floatingCursorAnimationController = AnimationController(vsync: this);

    widget.floatingCursorController
      ..blinkController = _cursorController
      ..animationController = _floatingCursorAnimationController;

    widget.focusNode.addListener(_onFocusChanged);
    widget.findController.addListener(_onCodeFindChanged);
  }

  @override
  void didUpdateWidget(covariant _CodeEditable oldWidget) {
    if (oldWidget.controller != widget.controller) {
      _highlighter.controller = widget.controller;
      oldWidget.controller.removeListener(_onCodeInputChanged);
      widget.controller.addListener(_onCodeInputChanged);
    }
    if (oldWidget.inputController != widget.inputController) {
      oldWidget.inputController.removeListener(_onCodeUserInputChanged);
      widget.inputController.addListener(_onCodeUserInputChanged);
    }
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocusChanged);
      widget.focusNode.addListener(_onFocusChanged);
    }
    if (oldWidget.findController != widget.findController) {
      oldWidget.findController.removeListener(_onCodeFindChanged);
      widget.findController.addListener(_onCodeFindChanged);
    }
    if (oldWidget.codeTheme != widget.codeTheme) {
      _highlighter.theme = widget.codeTheme;
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final _CodeAutocompleteState? autocompleteState =
      context.findAncestorStateOfType<_CodeAutocompleteState>();
    if (!identical(autocompleteState, _autocompleteState)) {
      _autocompleteState?._detachHost(this);
      _autocompleteState = autocompleteState;
      autocompleteState?._attachHost(this);
    }
    if (!_didAutoFocus && widget.autofocus) {
      _didAutoFocus = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          FocusScope.of(context).autofocus(widget.focusNode);
        }
      });
    }
  }

  @override
  void dispose() {
    _autocompleteDebounce?.cancel();
    _autocompleteDebounce = null;
    _autocompleteState?._detachHost(this);
    _autocompleteState = null;
    widget.controller.removeListener(_onCodeInputChanged);
    widget.inputController.removeListener(_onCodeUserInputChanged);
    _highlighter.dispose();
    _codeIndicatorValueNotifier.dispose();
    _cursorController.dispose();
    _floatingCursorAnimationController.dispose();
    widget.focusNode.removeListener(_onFocusChanged);
    widget.findController.removeListener(_onCodeFindChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final Widget child = _CodeScrollable(
      axisDirection: AxisDirection.down,
      controller: widget.scrollController.verticalScroller,
      viewportBuilder: (context, ViewportOffset vertical) {
        Widget codeField;
        if (widget.wordWrap) {
          codeField = _buildCodeField(vertical, null);
        } else {
          codeField = _CodeScrollable(
            axisDirection: AxisDirection.right,
            controller: widget.scrollController.horizontalScroller,
            viewportBuilder: (context, ViewportOffset horizontal) {
              return _buildCodeField(vertical, horizontal);
            },
            scrollbarBuilder: widget.scrollbarBuilder
          );
        }
        if (widget.controller.value.isInitial) {
          final String? hint = widget.hint;
          if (hint != null && hint.isNotEmpty) {
            codeField = Stack(
              children: [
                codeField,
                IgnorePointer(
                  ignoring: true,
                  child: Padding(
                    padding: widget.padding,
                    child: Text(
                      hint,
                      style: widget.textStyle.copyWith(
                        color: widget.hintTextColor
                      ),
                    ),
                  )
                )
              ],
            );
          }
        }
        final Widget? indicator = widget.indicatorBuilder?.call(
          context,
          widget.controller,
          widget.chunkController,
          _codeIndicatorValueNotifier
        );
        return Container(
          decoration: BoxDecoration(
            border: widget.border,
            color: widget.backgroundColor,
            borderRadius: widget.borderRadius,
          ),
          clipBehavior: widget.clipBehavior,
          margin: widget.margin,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (indicator != null)
                indicator,
              if (widget.sperator != null)
                widget.sperator!,
              Expanded(
                child: RepaintBoundary(
                  child: CompositedTransformTarget(
                    link: widget.toolbarLayerLink,
                    child: codeField
                  ),
                ),
              )
            ],
          ),
        );
      },
      scrollbarBuilder: widget.scrollbarBuilder
    );
    return CodeEditorTapRegion(
      onTapOutside: (_) {
        widget.focusNode.unfocus();
      },
      child: NotificationListener(
        onNotification: (notification) {
          if (notification is ScrollStartNotification) {
            widget.selectionOverlayController.hideToolbar();
          }
          return false;
        },
        child: child
      )
    );
  }

  Widget _buildCodeField(ViewportOffset vertical, ViewportOffset? horizontal) {
    return _CodeField(
      key: widget.editorKey,
      verticalViewport: vertical,
      horizontalViewport: horizontal,
      verticalScrollbarWidth: widget.verticalScrollbarWidth ?? _kScrollbarThickness,
      horizontalScrollbarHeight: widget.horizontalScrollbarHeight ?? _kScrollbarThickness,
      selection: widget.controller.selection,
      carets: widget.controller.selections,
      matchedBrackets: findMatchingBracketHighlights(widget.controller.codeLines, widget.controller.selection),
      highlightSelections: widget.findController.allMatchSelections,
      codes: widget.controller.codeLines,
      textStyle: widget.textStyle,
      hasFocus: widget.focusNode.hasFocus,
      highlighter: _highlighter,
      showCursorNotifier: _cursorController,
      floatingCursorNotifier: widget.floatingCursorController,
      onRenderParagraphsChanged: (paragraphs) {
        _codeIndicatorValueNotifier.value = CodeIndicatorValue(
          paragraphs: paragraphs,
          focusedIndex: widget.controller.selection.extentIndex
        );
      },
      selectionColor: widget.selectionColor,
      highlightColor: widget.highlightColor,
      cursorColor: widget.cursorColor,
      cursorLineColor: widget.cursorLineColor,
      bracketMatchColor: widget.bracketMatchColor,
      chunkIndicatorColor: widget.chunkIndicatorColor,
      decorations: widget.decorations,
      cursorWidth: widget.cursorWidth,
      padding: widget.padding,
      readOnly: widget.readOnly,
      // Enable long text rendering when the find is on.
      maxLengthSingleLineRendering: widget.findController.value != null ? null : widget.maxLengthSingleLineRendering,
      startHandleLayerLink: widget.startHandleLayerLink,
      endHandleLayerLink: widget.endHandleLayerLink,
    );
  }

  void _onFocusChanged() {
    if (!mounted) {
      return;
    }
    _updateCursorState();
    _updateAutoCompleteState(false);
    updateKeepAlive();
    if (!widget.focusNode.hasFocus) {
      if (kIsAndroid || kIsIOS) {
        widget.controller.cancelSelection();
      }
      widget.selectionOverlayController.hideHandle();
      widget.selectionOverlayController.hideToolbar();
    }
  }

  void _onCodeInputChanged() {
    if (!mounted) {
      return;
    }
    widget.onChanged?.call(widget.controller.value);
    if (widget.controller.codeLines != widget.controller.preValue?.codeLines &&
      widget.controller.preValue != null) {
      widget.selectionOverlayController.hideHandle();
      widget.selectionOverlayController.hideToolbar();
    } else {
      _updateAutoCompleteState(false);
    }
    _updateCursorState();
    setState(() {
    });
  }

  void _onCodeUserInputChanged() {
    if (!mounted) {
      return;
    }
    // Let the caret settle, then ask once. Coalescing and cancellable: a burst
    // of keystrokes inside the window costs one ask instead of one per
    // character, and every path that closes the overlay calls the pending one
    // off (see [_updateAutoCompleteState]) so a stale ask cannot re-open it.
    _autocompleteDebounce?.cancel();
    _autocompleteDebounce = Timer(
      _autocompleteState?.inputDebounce ?? const Duration(milliseconds: 50),
      () {
        _autocompleteDebounce = null;
        _updateAutoCompleteState(true);
      },
    );
  }

  void _onCodeFindChanged() {
    if (!mounted) {
      return;
    }
    final CodeFindValue? value = widget.findController.value;
    if (value == null) {
      widget.focusNode.requestFocus();
      return;
    }
    if (widget.focusNode.hasFocus) {
      return;
    }
    final CodeLineSelection? currentMatch = widget.findController.currentMatchSelection;
    if (currentMatch == null) {
      return;
    }
    widget.controller.selection = currentMatch;
    if (currentMatch.isSameLine) {
      widget.controller.makePositionCenterIfInvisible(CodeLinePosition(
        index: currentMatch.start.index,
        offset: (currentMatch.startOffset + currentMatch.endOffset) >> 1
      ));
    } else {
      widget.controller.makePositionCenterIfInvisible(currentMatch.start);
    }
  }

  void _updateCursorState() {
    if (widget.focusNode.hasFocus && (!widget.readOnly || widget.showCursorWhenReadOnly)) {
      _cursorController.startBlink();
    } else {
      _cursorController.stopBlink();
    }
  }

  /// Asks for prompts at the caret right now — the manual trigger
  /// ([CodeAutocompleteController.trigger]) reaching the one object that knows
  /// where the caret is drawn.
  @override
  void requestAutocomplete({required CodeAutocompleteTriggerKind kind}) {
    // The pending typing ask would otherwise fire a moment later and supersede
    // the answer to this one.
    _autocompleteDebounce?.cancel();
    _autocompleteDebounce = null;
    _updateAutoCompleteState(true, kind: kind);
  }

  void _updateAutoCompleteState(bool isCodeLineChanged, {
    CodeAutocompleteTriggerKind kind = CodeAutocompleteTriggerKind.typing,
  }) {
    if (!mounted) {
      return;
    }
    final _CodeAutocompleteState? autocompleteState = _autocompleteState;
    if (autocompleteState == null) {
      return;
    }
    // Every exit below closes the overlay, so the ask a keystroke already
    // scheduled must go with it — otherwise the timer fires after the dismissal
    // and re-opens what the user just closed.
    if (!isCodeLineChanged ||
        widget.controller.isComposing ||
        !widget.controller.selection.isCollapsed) {
      _autocompleteDebounce?.cancel();
      _autocompleteDebounce = null;
      autocompleteState.dismiss();
      return;
    }
    final _CodeFieldRender? render = widget.editorKey.currentContext?.findRenderObject() as _CodeFieldRender?;
    final Offset? position = render?.calculateTextPositionScreenOffset(
      widget.controller.selection.extent,
      true,
    );
    if (render == null || position == null) {
      _autocompleteDebounce?.cancel();
      _autocompleteDebounce = null;
      autocompleteState.dismiss();
      return;
    }
    autocompleteState.show(
      layerLink: widget.startHandleLayerLink,
      position: position,
      lineHeight: render.lineHeight,
      value: widget.controller.value,
      kind: kind,
      onAutocomplete: (value) {
        final CodeLineSelection selection = widget.controller.selection;
        widget.controller.replaceSelection(value.word, selection.copyWith(
          baseOffset: selection.baseOffset - value.input.length,
        ));
        widget.controller.selection = selection.copyWith(
          baseOffset: selection.baseOffset + value.selection.baseOffset,
          extentOffset: selection.extentOffset + value.selection.extentOffset,
        );
      }
    );
  }

}

class _CodeCursorBlinkController extends ValueNotifier<bool> {

  Timer? _timer;

  _CodeCursorBlinkController() : super(false);

  void startBlink() {
    if (_timer != null) {
      _timer!.cancel();
    }
    _timer = Timer.periodic(_kCursorBlinkHalfPeriod, _cursorTick);
    if (kIsAndroid || kIsIOS) {
      // Wait selection position to update
      Future.delayed(const Duration(milliseconds: 100), () {
        value = true;
      });
    } else {
      value = true;
    }
  }

  void stopBlink() {
    if (_timer == null) {
      return;
    }
    _timer?.cancel();
    _timer = null;
    value = false;
  }

  void _cursorTick(Timer timer) {
    value = !value;
  }

  @override
  void dispose() {
    stopBlink();
    super.dispose();
  }

}