part of re_editor;

/// Define code autocomplate prompt information.
///
/// See also [CodeKeywordPrompt], [CodeFieldPrompt] and [CodeFunctionPrompt].
abstract class CodePrompt {

  const CodePrompt({
    required this.word
  });

  /// Content associated with user input.
  ///
  /// e.g. User input is 're', the prompt word 'return' will be displayed to user.
  final String word;

  /// Get the final auto completion content. In most cases it is equal to [word], but there are some exceptions.
  /// For example, for functions, auto completion of parameters may be required.
  ///
  /// e.g. User input is 'he', 'hello(String name)' will be auto completed.
  CodeAutocompleteResult get autocomplete;

  /// Check whether the input meets this prompt condition.
  bool match(String input);

}

/// The keyword autocomplate prompt. such as 'return', 'class', 'new' and so on.
class CodeKeywordPrompt extends CodePrompt {

  const CodeKeywordPrompt({
    required super.word
  });

  @override
  CodeAutocompleteResult get autocomplete => CodeAutocompleteResult.fromWord(word);

  @override
  bool match(String input) {
    return word != input && word.startsWith(input);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is CodeKeywordPrompt && other.word == word;
  }

  @override
  int get hashCode => word.hashCode;

}

/// The field autocomplate prompt. Compared to [CodeKeywordPrompt],
/// type definitions also need to be provided.
///
/// If a line of code is 'String foo;', 'foo' is the word and 'String' is the type.
class CodeFieldPrompt extends CodePrompt {

  const CodeFieldPrompt({
    required super.word,
    required this.type,
    this.customAutocomplete,
  });

  /// The field type name.
  final String type;

  /// Will use custom autocomplete rather than word if this is not null.
  final CodeAutocompleteResult? customAutocomplete;

  @override
  CodeAutocompleteResult get autocomplete => customAutocomplete ?? CodeAutocompleteResult.fromWord(word);

  @override
  bool match(String input) {
    return word != input && word.startsWith(input);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is CodeFieldPrompt && other.word == word && other.type == type
      && other.customAutocomplete == customAutocomplete;
  }

  @override
  int get hashCode => Object.hash(word, type, customAutocomplete);

}

/// The function autocomplate prompt.
class CodeFunctionPrompt extends CodePrompt {

  const CodeFunctionPrompt({
    required super.word,
    required this.type,
    this.parameters = const {},
    this.optionalParameters = const {},
    this.customAutocomplete,
  });

  /// The function return type.
  final String type;

  /// The function required parameters.
  final Map<String, String> parameters;

  /// The function optional parameters.
  final Map<String, String> optionalParameters;

  /// Will use custom autocomplete rather than word if this is not null.
  final CodeAutocompleteResult? customAutocomplete;

  @override
  CodeAutocompleteResult get autocomplete => customAutocomplete ?? CodeAutocompleteResult.fromWord('$word(${parameters.keys.join(', ')})');

  @override
  bool match(String input) {
    return word != input && word.startsWith(input);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is CodeFunctionPrompt && other.word == word && other.type == type &&
      mapEquals(other.parameters, parameters) && mapEquals(other.optionalParameters, optionalParameters)
      && other.customAutocomplete == customAutocomplete;
  }

  @override
  int get hashCode => Object.hash(word, type, parameters, optionalParameters, customAutocomplete);

}

/// The autocomplete result selected by user, the editor will apply this
/// to code content.
class CodeAutocompleteResult {

  const CodeAutocompleteResult({
    required this.input,
    required this.word,
    required this.selection,
    this.prompt,
  });

  factory CodeAutocompleteResult.fromWord(String word) {
    return CodeAutocompleteResult(
      input: '',
      word: word,
      selection: TextSelection.collapsed(
        offset: word.length
      )
    );
  }

  /// The autocomplete text.
  /// e.g.
  /// If user inputs `go` and the word is `good`, we will replace `go` with `good`.
  final String input;
  final String word;

  /// The new selection after the autocompletion.
  final TextSelection selection;

  /// The prompt this result was produced from, when one is known.
  ///
  /// Filled in by [CodeAutocompleteEditingValue.autocomplete], and the reason a
  /// host that applies the edit itself (see [CodeAutocomplete.onAccept]) never
  /// has to reverse-engineer which row was chosen: it reads its own [CodePrompt]
  /// subclass straight back out. Null for a result assembled by hand.
  final CodePrompt? prompt;

}

/// The current user input and prompts for editing a run of text.
class CodeAutocompleteEditingValue {

  const CodeAutocompleteEditingValue({
    required this.input,
    required this.prompts,
    required this.index,
  });

  /// User input content.
  final String input;

  /// Matched code prompts.
  ///
  /// Displayed and applied in exactly this order — the editor never re-sorts.
  final List<CodePrompt> prompts;

  /// Current selected code prompt.
  final int index;

  CodeAutocompleteEditingValue copyWith({
    String? input,
    List<CodePrompt>? prompts,
    int? index,
  }) {
    return CodeAutocompleteEditingValue(
      input: input ?? this.input,
      prompts: prompts ?? this.prompts,
      index: index ?? this.index,
    );
  }

  CodeAutocompleteResult get autocomplete {
    final CodePrompt prompt = prompts[index];
    final CodeAutocompleteResult result = prompt.autocomplete;
    if (result.word.isEmpty) {
      return CodeAutocompleteResult(
        input: result.input,
        word: result.word,
        selection: result.selection,
        prompt: result.prompt ?? prompt,
      );
    }
    final TextSelection finalSelection = result.selection.copyWith(
      baseOffset: result.selection.baseOffset - input.length,
      extentOffset: result.selection.extentOffset - input.length,
    );
    return CodeAutocompleteResult(
      input: input,
      word: result.word,
      selection: finalSelection,
      prompt: result.prompt ?? prompt,
    );
  }

}

/// Builds the overlay autocomplete prompts view.
typedef CodeAutocompleteWidgetBuilder = PreferredSizeWidget Function(
  BuildContext context,
  ValueNotifier<CodeAutocompleteEditingValue> notifier,
  ValueChanged<CodeAutocompleteResult> onSelected
);

/// The autocomplete prompts builder.
abstract class CodeAutocompletePromptsBuilder {

  /// Build the prompts with the current code.
  CodeAutocompleteEditingValue? build(
    BuildContext context,
    CodeLine codeLine,
    CodeLineSelection selection,
  );

}

/// Why the editor is asking a prompt source for prompts.
enum CodeAutocompleteTriggerKind {

  /// The user typed or deleted something. Debounced by
  /// [CodeAutocomplete.inputDebounce].
  typing,

  /// The host asked explicitly — [CodeAutocompleteController.trigger], which an
  /// embedder binds to a chord such as Ctrl+Space. Never debounced, and asked
  /// even where typing would not be (an empty word, right after a symbol).
  manual,

}

/// One in-flight ask for prompts, handed to [AsyncCodeAutocompletePromptsBuilder].
///
/// Carries the caret it describes and, through [whenCancelled], the editor's
/// verdict that the answer is no longer wanted — which is what lets a source
/// with a cancellable transport abandon the work rather than merely have its
/// answer thrown away.
class CodeAutocompleteRequest {

  CodeAutocompleteRequest({
    required this.codeLine,
    required this.selection,
    required this.kind,
  });

  /// The line the caret sits on, as it was when the request was made.
  final CodeLine codeLine;

  /// The caret. Always collapsed: the editor does not ask while text is
  /// selected.
  final CodeLineSelection selection;

  /// What caused the ask.
  final CodeAutocompleteTriggerKind kind;

  /// Whether the editor has given up on this request. A value returned for a
  /// cancelled request is dropped, so it can never re-open a dismissed overlay
  /// or overwrite the answer to a newer keystroke.
  bool get isCancelled => _cancelled;
  bool _cancelled = false;

  List<VoidCallback>? _onCancel;

  /// Runs [callback] when this request is abandoned — a newer keystroke, an
  /// explicit dismissal, the editor losing focus — or immediately when it
  /// already has been.
  void whenCancelled(VoidCallback callback) {
    if (_cancelled) {
      callback();
      return;
    }
    (_onCancel ??= <VoidCallback>[]).add(callback);
  }

  void _cancel() {
    if (_cancelled) {
      return;
    }
    _cancelled = true;
    final List<VoidCallback>? callbacks = _onCancel;
    _onCancel = null;
    if (callbacks == null) {
      return;
    }
    for (final VoidCallback callback in callbacks) {
      callback();
    }
  }

}

/// A prompt source that answers after a round trip.
///
/// The counterpart of [CodeAutocompletePromptsBuilder] for sources that cannot
/// answer within the frame that produced the keystroke — a language server, an
/// index on another isolate. Both may be supplied at once: the synchronous
/// answer opens the overlay immediately and the asynchronous one replaces its
/// contents when it lands.
abstract class AsyncCodeAutocompletePromptsBuilder {

  /// Prompts for [request], or null when there are none.
  ///
  /// A non-null, non-empty value opens the overlay or replaces what is already
  /// in it, so an overlay can be opened empty-handed and filled later. A null
  /// or empty value closes it. Prompt order is preserved exactly.
  ///
  /// Never called for a caret the editor would not offer prompts for at all (a
  /// selection, an in-flight IME composition, a caret with no laid-out line).
  Future<CodeAutocompleteEditingValue?> build(CodeAutocompleteRequest request);

}

/// How far [CodeShortcutType.cursorMovePageUp]/`Down` moves the highlighted
/// prompt.
///
/// A fixed step rather than the view's visible row count: the view is the host's
/// widget and the editor cannot measure it, and a page jump that changes size
/// with the window is worse than one that is always the same.
const int kCodeAutocompletePageStep = 8;

/// A host's handle on a [CodeAutocomplete] overlay.
///
/// Two things it makes possible, neither of which the overlay can do for itself:
///
/// * **A manual trigger.** [trigger] asks for prompts at the caret with no
///   debounce and none of typing's "not here" shortcuts, which is what a
///   Ctrl+Space binding needs. The chord itself stays the host's, because the
///   editor has no opinion about which chords an application spends.
/// * **Keyboard arbitration.** An application that already claims Up/Down/Enter
///   at an `Actions` layer *above* the editor — for a second popup of its own —
///   shadows the overlay's own claims, because `Actions` resolves to the nearest
///   ancestor holding the intent type whether or not its action is enabled. Such
///   a host routes those keys here instead, and [isShowing] tells it when to.
class CodeAutocompleteController {

  _CodeAutocompleteState? _state;

  /// Whether the overlay is on screen.
  bool get isShowing => _state?.isShowing ?? false;

  /// The prompts on screen, or null when none are.
  CodeAutocompleteEditingValue? get value => _state?.value;

  /// Asks for prompts at the caret as a [CodeAutocompleteTriggerKind.manual]
  /// request: no debounce, and offered even where typing would not be.
  void trigger() => _state?.triggerManually();

  /// Closes the overlay and abandons any request in flight for it.
  void dismiss() => _state?.dismiss();

  /// Moves the highlighted prompt by [delta] rows, wrapping at both ends unless
  /// [wrap] is false (a page jump clamps instead, so PageDown at the bottom
  /// stays at the bottom rather than jumping to the top).
  void moveSelection(int delta, {bool wrap = true}) =>
    _state?.moveSelection(delta, wrap: wrap);

  /// Accepts the highlighted prompt, exactly as Enter or Tab would.
  void accept() => _state?.acceptSelected();

  void _attach(_CodeAutocompleteState state) {
    _state = state;
  }

  void _detach(_CodeAutocompleteState state) {
    if (identical(_state, state)) {
      _state = null;
    }
  }

}

/// The default autocomplete prompts builder.
abstract class DefaultCodeAutocompletePromptsBuilder implements CodeAutocompletePromptsBuilder {

  /// Constructs the builder with defined prompts.
  factory DefaultCodeAutocompletePromptsBuilder({
    Mode? language,
    List<CodeKeywordPrompt> keywordPrompts = const [],
    List<CodePrompt> directPrompts = const [],
    Map<String, List<CodePrompt>> relatedPrompts = const {},
  }) => _DefaultCodeAutocompletePromptsBuilder(
    language: language,
    keywordPrompts: keywordPrompts,
    directPrompts: directPrompts,
    relatedPrompts: relatedPrompts,
  );

}

/// A widget enables code autocomplete for [CodeEditor].
///
/// Developers can customize the view styles and prompt logic they need.
///
/// The following is a common usage.
///
/// ```
/// CodeAutocomplete(
///   viewBuilder: (context, notifier, onSelected) {
///     // TODO build the options list widget.
///   },
///   promptsBuilder: DefaultCodeAutocompletePromptsBuilder(
///     language: langDart,
///     directPrompts: [
///       CodeFieldPrompt(
///         word: 'foo',
///         type: 'String'
///       ),
///       CodeFunctionPrompt(
///         word: 'hello',
///         type: 'void',
///         parameters: {
///           'value': 'String',
///         }
///       )
///     ],
///   ),
///   child: CodeEditor()
/// )
/// ```
///
/// A source that needs a round trip supplies [asyncPromptsBuilder] instead of
/// (or as well as) [promptsBuilder], and a host that applies the accepted edit
/// itself supplies [onAccept].
class CodeAutocomplete extends StatelessWidget {

  const CodeAutocomplete({
    super.key,
    required this.viewBuilder,
    this.promptsBuilder,
    this.asyncPromptsBuilder,
    this.controller,
    this.onAccept,
    this.inputDebounce = const Duration(milliseconds: 50),
    required this.child,
  });

  final CodeAutocompleteWidgetBuilder viewBuilder;

  /// Prompts available without a round trip, or null when the source has none.
  final CodeAutocompletePromptsBuilder? promptsBuilder;

  /// Prompts that need a round trip, or null when the source has none. Asked
  /// after [promptsBuilder] and allowed to replace its answer.
  final AsyncCodeAutocompletePromptsBuilder? asyncPromptsBuilder;

  /// The host's handle on this overlay — a manual trigger, and keyboard
  /// arbitration when the host claims the overlay's keys itself.
  final CodeAutocompleteController? controller;

  /// Applies an accepted prompt, instead of the editor.
  ///
  /// When given, the editor performs **no** buffer mutation of its own on
  /// accept: it closes the overlay and hands the [CodeAutocompleteResult] —
  /// [CodeAutocompleteResult.prompt] included — straight over. That is what an
  /// LSP completion needs, because its `textEdit` and every one of its
  /// `additionalTextEdits` (the auto-import) are expressed in the *same*
  /// pre-insertion coordinate space and have to land as one batch: replacing the
  /// typed word first would move the ground the rest were measured against.
  ///
  /// Without it, accept keeps its original behaviour — strip
  /// [CodeAutocompleteResult.input] at the caret, insert
  /// [CodeAutocompleteResult.word].
  final ValueChanged<CodeAutocompleteResult>? onAccept;

  /// How long typing must pause before prompts are asked for.
  ///
  /// Coalescing and cancellable: a burst of N keystrokes asks once, and a
  /// dismissal drops the pending ask altogether. Hosts whose source is
  /// expensive (a language server) raise this; the default matches the delay the
  /// editor has always used to let the caret settle.
  final Duration inputDebounce;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _CodeAutocomplete(
      viewBuilder: viewBuilder,
      promptsBuilder: promptsBuilder,
      asyncPromptsBuilder: asyncPromptsBuilder,
      controller: controller,
      onAccept: onAccept,
      inputDebounce: inputDebounce,
      child: child
    );
  }

}
