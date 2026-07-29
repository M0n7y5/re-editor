part of re_editor;

class _DefaultCodeAutocompletePromptsBuilder implements DefaultCodeAutocompletePromptsBuilder {

  final Mode? language;
  final List<CodeKeywordPrompt> keywordPrompts;
  final List<CodePrompt> directPrompts;
  final Map<String, List<CodePrompt>> relatedPrompts;

  final Set<CodePrompt> _allKeywordPrompts = {};

  _DefaultCodeAutocompletePromptsBuilder({
    this.language,
    required this.keywordPrompts,
    required this.directPrompts,
    required this.relatedPrompts
  }) {
    _allKeywordPrompts.addAll(keywordPrompts);
    _allKeywordPrompts.addAll(directPrompts);
    final dynamic keywords = language?.keywords;
    if (keywords is Map) {
      final dynamic keywordList = keywords['keyword'];
      if (keywordList is List) {
        _allKeywordPrompts.addAll(keywordList.map(
          (keyword) => CodeKeywordPrompt(word: keyword))
        );
      }
      final dynamic builtInList = keywords['built_in'];
      if (builtInList is List) {
        _allKeywordPrompts.addAll(builtInList.map(
          (keyword) => CodeKeywordPrompt(word: keyword))
        );
      }
      final dynamic literalList = keywords['literal'];
      if (literalList is List) {
        _allKeywordPrompts.addAll(literalList.map(
          (keyword) => CodeKeywordPrompt(word: keyword))
        );
      }
      final dynamic typeList = keywords['type'];
      if (typeList is List) {
        _allKeywordPrompts.addAll(typeList.map(
          (keyword) => CodeKeywordPrompt(word: keyword))
        );
      }
    }
  }

  @override
  CodeAutocompleteEditingValue? build(BuildContext context, CodeLine codeLine, CodeLineSelection selection) {
    final String text = codeLine.text;
    final Characters charactersBefore = text.substring(0, selection.extentOffset).characters;
    if (charactersBefore.isEmpty) {
      return null;
    }
    final Characters charactersAfter = text.substring(selection.extentOffset).characters;
    // FIXME：Check whether the position is inside a string
    if (charactersBefore.containsSymbols(const ['\'', '"']) && charactersAfter.containsSymbols(const ['\'', '"'])) {
      return null;
    }
    // TODO Should check operator `->` for some languages like c/c++
    final Iterable<CodePrompt> prompts;
    final String input;
    if (charactersBefore.takeLast(1).string == '.') {
      input = '';
      int start = charactersBefore.length - 2;
      for (; start >= 0; start--) {
        if (!charactersBefore.elementAt(start).isValidVariablePart) {
          break;
        }
      }
      final String target = charactersBefore.getRange(start + 1, charactersBefore.length - 1).string;
      prompts = relatedPrompts[target] ?? const [];
    } else {
      int start = charactersBefore.length - 1;
      for (; start >= 0; start--) {
        if (!charactersBefore.elementAt(start).isValidVariablePart) {
          break;
        }
      }
      input = charactersBefore.getRange(start + 1, charactersBefore.length).string;
      if (input.isEmpty) {
        return null;
      }
      if (start > 0 && charactersBefore.elementAt(start) == '.') {
        final int mark = start;
        for (start = start - 1; start >= 0; start--) {
          if (!charactersBefore.elementAt(start).isValidVariablePart) {
            break;
          }
        }
        final String target = charactersBefore.getRange(start + 1, mark).string;
        prompts = relatedPrompts[target]?.where(
          (prompt) => prompt.match(input)
        ) ?? const [];
      } else {
        prompts = _allKeywordPrompts.where(
          (prompt) => prompt.match(input)
        );
      }
    }
    if (prompts.isEmpty) {
      return null;
    }
    return CodeAutocompleteEditingValue(
      input: input,
      prompts: prompts.toList(),
      index: 0
    );
  }

}

/// The editor surface a [_CodeAutocompleteState] runs its asks through.
///
/// Implemented by [_CodeEditableState], which is the only thing that knows where
/// the caret is drawn and what the buffer currently holds. So a manual trigger
/// asks *it* to re-run the show/dismiss decision rather than the overlay trying
/// to measure a caret from above the editor.
abstract class _CodeAutocompleteHost {

  void requestAutocomplete({required CodeAutocompleteTriggerKind kind});

}

class _CodeAutocomplete extends StatefulWidget {

  const _CodeAutocomplete({
    required this.viewBuilder,
    required this.promptsBuilder,
    required this.asyncPromptsBuilder,
    required this.controller,
    required this.onAccept,
    required this.inputDebounce,
    required this.child,
  });

  final CodeAutocompleteWidgetBuilder viewBuilder;
  final CodeAutocompletePromptsBuilder? promptsBuilder;
  final AsyncCodeAutocompletePromptsBuilder? asyncPromptsBuilder;
  final CodeAutocompleteController? controller;
  final ValueChanged<CodeAutocompleteResult>? onAccept;
  final Duration inputDebounce;
  final Widget child;

  @override
  State<StatefulWidget> createState() => _CodeAutocompleteState();

}

class _CodeAutocompleteState extends State<_CodeAutocomplete> {

  late final _CodeAutocompleteNavigateAction _navigateAction;
  late final _CodeAutocompletePageNavigateAction _pageNavigateAction;
  late final _CodeAutocompleteAction _selectAction;
  late final _CodeAutocompleteAction _tabSelectAction;
  late final _CodeAutocompleteAction _dismissAction;

  ValueChanged<CodeAutocompleteResult>? _onAutocomplete;
  OverlayEntry? _overlayEntry;
  ValueNotifier<CodeAutocompleteEditingValue>? _notifier;

  /// Where the overlay is drawn, refreshed by every [show] so it follows the
  /// caret across the keystrokes that refill it.
  LayerLink? _layerLink;
  Offset? _position;
  double? _lineHeight;

  _CodeAutocompleteHost? _host;

  /// Bumped by every [show] and every [dismiss]. An asynchronous answer whose
  /// generation is no longer current is dropped — which is the whole of "a
  /// response arriving after a newer keystroke, or after the overlay was
  /// dismissed, can never re-open it".
  int _generation = 0;

  /// The asynchronous ask in flight, kept only to cancel it.
  CodeAutocompleteRequest? _request;

  /// Whether the overlay is on screen.
  bool get isShowing => _overlayEntry != null;

  /// The prompts on screen, or null when none are.
  CodeAutocompleteEditingValue? get value => _notifier?.value;

  /// How long typing must pause before prompts are asked for. Read by
  /// [_CodeEditableState], which owns the timer because it owns the keystroke.
  Duration get inputDebounce => widget.inputDebounce;

  @override
  void initState() {
    super.initState();
    _navigateAction = _CodeAutocompleteNavigateAction(
      onInvoke: (intent) {
        if (!isShowing) {
          return null;
        }
        moveSelection(intent.direction == AxisDirection.up ? -1 : 1);
        return intent;
      },
    );
    _pageNavigateAction = _CodeAutocompletePageNavigateAction(
      onInvoke: (intent) {
        if (!isShowing) {
          return null;
        }
        // Clamped rather than wrapped: a page jump is "as far as you can go in
        // this direction", and wrapping it lands the user at the opposite end of
        // a list they were paging through.
        moveSelection(
          intent.forward ? kCodeAutocompletePageStep : -kCodeAutocompletePageStep,
          wrap: false,
        );
        return intent;
      },
    );
    _selectAction = _CodeAutocompleteAction<CodeShortcutNewLineIntent>(
      onInvoke: (intent) {
        if (!isShowing) {
          return null;
        }
        acceptSelected();
        return intent;
      },
    );
    _tabSelectAction = _CodeAutocompleteAction<CodeShortcutIndentIntent>(
      onInvoke: (intent) {
        if (!isShowing) {
          return null;
        }
        acceptSelected();
        return intent;
      },
    );
    _dismissAction = _CodeAutocompleteAction<CodeShortcutEscIntent>(
      onInvoke: (intent) {
        if (!isShowing) {
          return null;
        }
        dismiss();
        return intent;
      },
    );
    widget.controller?._attach(this);
  }

  @override
  void didUpdateWidget(covariant _CodeAutocomplete oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    // The overlay is inserted into an ancestor Overlay, so nothing else tears it
    // down when this state goes away.
    dismiss();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: {
        CodeShortcutCursorMoveIntent: _navigateAction,
        CodeShortcutCursorMovePageIntent: _pageNavigateAction,
        CodeShortcutNewLineIntent: _selectAction,
        CodeShortcutIndentIntent: _tabSelectAction,
        CodeShortcutEscIntent: _dismissAction,
      },
      child: widget.child
    );
  }

  void _attachHost(_CodeAutocompleteHost host) {
    _host = host;
  }

  void _detachHost(_CodeAutocompleteHost host) {
    if (identical(_host, host)) {
      _host = null;
    }
  }

  /// Asks for prompts at the caret with no debounce — the manual trigger behind
  /// [CodeAutocompleteController.trigger].
  void triggerManually() {
    _host?.requestAutocomplete(kind: CodeAutocompleteTriggerKind.manual);
  }

  /// Asks both prompt sources about the caret [value] describes, and opens or
  /// refills the overlay with whatever they answer.
  ///
  /// The synchronous source answers in this frame. The asynchronous one answers
  /// later and is allowed to replace what the synchronous one put up, so an
  /// overlay can be opened empty-handed and filled when the round trip lands —
  /// and the overlay is deliberately *not* torn down while that is in flight,
  /// because closing and re-opening it on every keystroke is a flicker the user
  /// pays for and learns nothing from.
  void show({
    required LayerLink layerLink,
    required Offset position,
    required double lineHeight,
    required CodeLineEditingValue value,
    required ValueChanged<CodeAutocompleteResult> onAutocomplete,
    CodeAutocompleteTriggerKind kind = CodeAutocompleteTriggerKind.typing,
  }) {
    // Supersedes whatever was in flight, and takes the generation this ask will
    // be checked against. Not `dismiss()`: an open overlay stays up.
    final int generation = _abandon();
    if (value.extraSelections.isNotEmpty) {
      dismiss();
      return;
    }
    if (_layerLink != layerLink || _position != position || _lineHeight != lineHeight) {
      _layerLink = layerLink;
      _position = position;
      _lineHeight = lineHeight;
      // The placement is read at build time, so an already-open overlay has to be
      // told the caret moved.
      _overlayEntry?.markNeedsBuild();
    }
    _onAutocomplete = onAutocomplete;
    final CodeLine codeLine = value.codeLines[value.selection.extentIndex];
    final CodeAutocompleteEditingValue? prompts = widget.promptsBuilder?.build(
      context,
      codeLine,
      value.selection,
    );
    final AsyncCodeAutocompletePromptsBuilder? asyncBuilder = widget.asyncPromptsBuilder;
    if (prompts != null && prompts.prompts.isNotEmpty) {
      _present(prompts);
    } else if (asyncBuilder == null) {
      dismiss();
      return;
    }
    if (asyncBuilder == null) {
      return;
    }
    final CodeAutocompleteRequest request = CodeAutocompleteRequest(
      codeLine: codeLine,
      selection: value.selection,
      kind: kind,
    );
    _request = request;
    asyncBuilder.build(request).then((result) {
      if (!_isCurrent(generation, request)) {
        return;
      }
      _request = null;
      if (result == null || result.prompts.isEmpty) {
        dismiss();
        return;
      }
      _present(result);
    }, onError: (Object error, StackTrace stackTrace) {
      if (!_isCurrent(generation, request)) {
        return;
      }
      _request = null;
      // A source that failed has no prompts to show. Reporting it is the host's
      // business; the overlay's only job is not to keep stale ones up.
      dismiss();
    });
  }

  /// Whether an answer to [request] is still wanted.
  bool _isCurrent(int generation, CodeAutocompleteRequest request) =>
    mounted && !request.isCancelled && generation == _generation;

  /// Opens the overlay with [value], or replaces what is already in it.
  void _present(CodeAutocompleteEditingValue value) {
    final ValueNotifier<CodeAutocompleteEditingValue>? notifier = _notifier;
    if (notifier != null && _overlayEntry != null) {
      notifier.value = value;
      return;
    }
    _notifier = ValueNotifier(value);
    _overlayEntry = OverlayEntry(
      builder:(context) {
        return _buildWidget(context, _layerLink!, _position!, _lineHeight!);
      },
    );
    Overlay.of(context, rootOverlay: true).insert(_overlayEntry!);
    _navigateAction.setEnabled(true);
    _pageNavigateAction.setEnabled(true);
    _selectAction.setEnabled(true);
    _tabSelectAction.setEnabled(true);
    _dismissAction.setEnabled(true);
  }

  /// Moves the highlighted prompt by [delta] rows.
  void moveSelection(int delta, {bool wrap = true}) {
    final ValueNotifier<CodeAutocompleteEditingValue>? notifier = _notifier;
    final CodeAutocompleteEditingValue? value = notifier?.value;
    if (notifier == null || value == null || value.prompts.isEmpty || delta == 0) {
      return;
    }
    final int count = value.prompts.length;
    int index = value.index + delta;
    if (wrap) {
      index %= count;
      if (index < 0) {
        index += count;
      }
    } else {
      index = index.clamp(0, count - 1);
    }
    if (index == value.index) {
      return;
    }
    notifier.value = value.copyWith(index: index);
  }

  /// Accepts the highlighted prompt, exactly as Enter or Tab does.
  void acceptSelected() {
    final CodeAutocompleteEditingValue? value = _notifier?.value;
    if (value == null || value.prompts.isEmpty) {
      return;
    }
    _accept(value.autocomplete);
  }

  /// Closes the overlay first, then applies [result] — through the host when it
  /// supplied [CodeAutocomplete.onAccept], else through the editor's own
  /// strip-input-and-insert.
  ///
  /// Closing first is not tidiness: applying mutates the buffer, which runs the
  /// editor's own change listeners, and an overlay still on screen at that point
  /// would be torn down from inside the apply.
  void _accept(CodeAutocompleteResult result) {
    final ValueChanged<CodeAutocompleteResult>? host = widget.onAccept;
    final ValueChanged<CodeAutocompleteResult>? editor = _onAutocomplete;
    dismiss();
    if (host != null) {
      host(result);
      return;
    }
    editor?.call(result);
  }

  /// Supersedes any ask in flight and returns the generation the next one owns.
  int _abandon() {
    final CodeAutocompleteRequest? request = _request;
    _request = null;
    request?._cancel();
    return ++_generation;
  }

  void dismiss() {
    _abandon();
    _notifier = null;
    _onAutocomplete = null;
    _overlayEntry?.remove();
    _overlayEntry = null;
    _navigateAction.setEnabled(false);
    _pageNavigateAction.setEnabled(false);
    _selectAction.setEnabled(false);
    _tabSelectAction.setEnabled(false);
    _dismissAction.setEnabled(false);
  }

  Widget _buildWidget(BuildContext context, LayerLink layerLink, Offset position, double lineHeight) {
    final PreferredSizeWidget child = widget.viewBuilder(context, _notifier!, _accept);
    final Size screenSize =  MediaQuery.of(context).size;
    final double offsetX;
    if (position.dx + child.preferredSize.width > screenSize.width) {
      offsetX = screenSize.width - (position.dx + child.preferredSize.width);
    } else {
      offsetX = 0;
    }
    final double offsetY;
    if (position.dy + child.preferredSize.height > screenSize.height) {
      offsetY = -child.preferredSize.height - lineHeight;
    } else {
      offsetY = 0;
    }
    return CompositedTransformFollower(
      link: layerLink,
      showWhenUnlinked: false,
      offset: Offset(offsetX, offsetY),
      child: Align(
        alignment: Alignment.topLeft,
        child: Material(
          color: Colors.transparent,
          child: TapRegion(
            onTapOutside: (event) {
              dismiss();
            },
            child: CodeEditorTapRegion(
              child: ExcludeSemantics(
                child: child,
              )
            )
          ),
        )
      ),
    );
  }

}

class _CodeAutocompleteAction<T extends Intent> extends CallbackAction<T> {

  bool _isEnabled = false;

  _CodeAutocompleteAction({
    required super.onInvoke
  });

  void setEnabled(bool enabled) {
    _isEnabled = enabled;
  }

  @override
  bool get isActionEnabled => _isEnabled;

}

class _CodeAutocompleteNavigateAction extends _CodeAutocompleteAction<CodeShortcutCursorMoveIntent> {

  _CodeAutocompleteNavigateAction({
    required super.onInvoke
  });

  @override
  bool consumesKey(CodeShortcutCursorMoveIntent intent) {
    return intent.direction == AxisDirection.up || intent.direction == AxisDirection.down;
  }

}

class _CodeAutocompletePageNavigateAction extends _CodeAutocompleteAction<CodeShortcutCursorMovePageIntent> {

  _CodeAutocompletePageNavigateAction({
    required super.onInvoke
  });

}

extension _CodeAutocompleteStringExtension on String {

  bool get isValidVariablePart {
    final int char = codeUnits.first;
    return (char >= 65 && char <= 90) || (char >= 97 && char <= 122) || char == 95;
  }

}

extension _CodeAutocompleteCharactersExtension on Characters {

  bool containsSymbols(List<String> symbols) {
    for (int i = length - 1; i >= 0; i--) {
      if (symbols.contains(elementAt(i))) {
        return true;
      }
    }
    return false;
  }

}