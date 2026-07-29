import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

/// A [testWidgets] that forces the desktop keymap.
///
/// re_editor caches the platform flag in a top-level `final`, so the override
/// has to be in place before the first editor is built — and cleared inside the
/// body, because the framework checks for leaked debug variables before
/// `tearDown` runs. On the test default (android) the editor deliberately drops
/// its Backspace binding, which is the keystroke these tests ask with.
void editorTest(
  String description,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(description, (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

/// The autocomplete overlay's two contracts: prompts that arrive after the frame
/// that asked for them, and a keyboard that can accept, dismiss and navigate.
///
/// Input is driven with real key events through the editor's own
/// Shortcuts/Actions tree, so what these tests exercise is the path a user takes.
/// Backspace is the keystroke used to *ask*: it is the one intent the editor
/// deliberately does not treat as a dismissal, and its handler is what pokes the
/// input controller the debounce hangs off.
void main() {
  /// How long the harness makes typing pause before prompts are asked for. Long
  /// enough that a burst inside it is unambiguous, short enough to pump past.
  const Duration debounce = Duration(milliseconds: 40);

  late CodeLineEditingController controller;
  late CodeAutocompleteController overlay;
  late _RecordingPromptsSource source;
  late List<CodeAutocompleteResult> accepted;

  setUp(() {
    controller = CodeLineEditingController.fromText('alpha\nbeta\n');
    overlay = CodeAutocompleteController();
    source = _RecordingPromptsSource();
    accepted = <CodeAutocompleteResult>[];
  });

  tearDown(() {
    controller.dispose();
  });

  /// Mounts an editor under an autocomplete overlay and parks the caret at the
  /// end of line 0, so a backspace has something to delete.
  ///
  /// [hostApplies] chooses which accept contract is under test: with it, the
  /// editor hands the result over and mutates nothing; without it, the editor
  /// keeps its original strip-the-input-and-insert behaviour.
  Future<void> pumpEditor(
    WidgetTester tester, {
    bool hostApplies = true,
    bool withAsync = true,
    CodeAutocompletePromptsBuilder? syncSource,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: CodeAutocomplete(
              controller: overlay,
              promptsBuilder: syncSource,
              asyncPromptsBuilder: withAsync ? source : null,
              inputDebounce: debounce,
              onAccept: hostApplies ? accepted.add : null,
              viewBuilder:
                  (
                    BuildContext context,
                    ValueNotifier<CodeAutocompleteEditingValue> notifier,
                    ValueChanged<CodeAutocompleteResult> onSelected,
                  ) => _PromptsView(notifier: notifier, onSelected: onSelected),
              child: CodeEditor(
                controller: controller,
                autofocus: true,
                style: const CodeEditorStyle(
                  fontSize: 13,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    controller.selection = const CodeLineSelection.collapsed(
      index: 0,
      offset: 5,
    );
    await tester.pump();
  }

  /// One keystroke the editor answers with an ask for prompts.
  Future<void> type(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
  }

  /// Waits out the debounce window.
  Future<void> settleDebounce(WidgetTester tester) =>
      tester.pump(debounce + const Duration(milliseconds: 10));

  Finder promptRow(String word) => find.byWidgetPredicate(
    (Widget widget) =>
        widget is Text && (widget.data == '> $word' || widget.data == '  $word'),
  );
  Finder highlightedRow(String word) => find.text('> $word');

  editorTest('an asynchronous source opens the overlay when it answers, not '
      'when it is asked', (WidgetTester tester) async {
    await pumpEditor(tester);
    await type(tester);
    await settleDebounce(tester);

    // Asked, and nothing on screen: the frame that produced the keystroke was
    // never blocked waiting for prompts.
    expect(source.requests, hasLength(1));
    expect(find.byType(_PromptsView), findsNothing);

    source.answer(<String>['alphabet', 'alpha']);
    await tester.pump();

    expect(find.byType(_PromptsView), findsOneWidget);
    expect(promptRow('alphabet'), findsOneWidget);
    expect(promptRow('alpha'), findsOneWidget);
  });

  editorTest('the overlay keeps the order the source returned', (
    WidgetTester tester,
  ) async {
    await pumpEditor(tester);
    await type(tester);
    await settleDebounce(tester);
    // Reverse alphabetical, so any re-sort shows up.
    source.answer(<String>['zeta', 'gamma', 'beta', 'alpha']);
    await tester.pump();

    expect(
      _visibleWords(tester),
      <String>['zeta', 'gamma', 'beta', 'alpha'],
    );
  });

  editorTest('a burst of keystrokes is one ask', (WidgetTester tester) async {
    await pumpEditor(tester);
    // Four keystrokes well inside one debounce window.
    for (int i = 0; i < 4; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump(const Duration(milliseconds: 5));
    }
    expect(source.requests, isEmpty);

    await settleDebounce(tester);
    expect(source.requests, hasLength(1));
    // The ask describes where the caret ended up, not where the burst started.
    expect(source.requests.single.selection.extentOffset, 1);
  });

  editorTest('an answer that lands after a dismissal is dropped', (
    WidgetTester tester,
  ) async {
    await pumpEditor(tester);
    await type(tester);
    await settleDebounce(tester);
    expect(source.requests, hasLength(1));

    overlay.dismiss();
    await tester.pump();
    // The source is told, so a cancellable transport can abandon the work
    // rather than merely have its answer thrown away.
    expect(source.requests.single.isCancelled, isTrue);

    source.answer(<String>['alphabet']);
    await tester.pump();

    expect(find.byType(_PromptsView), findsNothing);
  });

  editorTest('an answer superseded by a newer keystroke is dropped', (
    WidgetTester tester,
  ) async {
    await pumpEditor(tester);
    await type(tester);
    await settleDebounce(tester);
    final CodeAutocompleteRequest first = source.requests.single;

    await type(tester);
    await settleDebounce(tester);
    expect(source.requests, hasLength(2));
    expect(first.isCancelled, isTrue);

    // The slow first answer lands after the second was asked; then the second.
    source.answerAt(0, <String>['stale']);
    await tester.pump();
    expect(find.byType(_PromptsView), findsNothing);

    source.answerAt(1, <String>['fresh']);
    await tester.pump();
    expect(_visibleWords(tester), <String>['fresh']);
  });

  editorTest('a later answer refills the open overlay instead of reopening it', (
    WidgetTester tester,
  ) async {
    await pumpEditor(tester);
    await type(tester);
    await settleDebounce(tester);
    source.answer(<String>['first']);
    await tester.pump();
    final _PromptsView shown = tester.widget(find.byType(_PromptsView));

    await type(tester);
    await settleDebounce(tester);
    // Still up while the next round trip is out — no flicker.
    expect(find.byType(_PromptsView), findsOneWidget);
    source.answerAt(1, <String>['second']);
    await tester.pump();

    expect(_visibleWords(tester), <String>['second']);
    // Same notifier, so the same overlay entry was refilled.
    expect(
      identical(
        shown.notifier,
        tester.widget<_PromptsView>(find.byType(_PromptsView)).notifier,
      ),
      isTrue,
    );
  });

  editorTest('an empty answer closes the overlay', (
    WidgetTester tester,
  ) async {
    await pumpEditor(tester);
    await type(tester);
    await settleDebounce(tester);
    source.answer(<String>['first']);
    await tester.pump();
    expect(find.byType(_PromptsView), findsOneWidget);

    await type(tester);
    await settleDebounce(tester);
    source.answerAt(1, const <String>[]);
    await tester.pump();

    expect(find.byType(_PromptsView), findsNothing);
  });

  editorTest('Up and Down move the highlight and wrap', (
    WidgetTester tester,
  ) async {
    await pumpEditor(tester);
    await type(tester);
    await settleDebounce(tester);
    source.answer(<String>['one', 'two', 'three']);
    await tester.pump();
    expect(highlightedRow('one'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(highlightedRow('two'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(highlightedRow('three'), findsOneWidget);

    // Navigating never moves the caret: the overlay claims the intent.
    expect(controller.selection.extentOffset, 4);
  });

  editorTest('PageDown and PageUp move by a page and clamp at the ends', (
    WidgetTester tester,
  ) async {
    await pumpEditor(tester);
    await type(tester);
    await settleDebounce(tester);
    source.answer(<String>[
      for (int i = 0; i < kCodeAutocompletePageStep + 3; i++) 'item$i',
    ]);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pump();
    expect(highlightedRow('item$kCodeAutocompletePageStep'), findsOneWidget);

    // Clamped, not wrapped: a second page runs out of list and stops at the end.
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pump();
    expect(highlightedRow('item${kCodeAutocompletePageStep + 2}'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await tester.pump();
    expect(highlightedRow('item0'), findsOneWidget);
  });

  editorTest('Enter accepts the highlighted prompt', (
    WidgetTester tester,
  ) async {
    await pumpEditor(tester);
    await type(tester);
    await settleDebounce(tester);
    source.answer(<String>['one', 'two']);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    final String before = controller.text;
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(accepted, hasLength(1));
    expect(accepted.single.prompt, isA<_TestPrompt>());
    expect((accepted.single.prompt! as _TestPrompt).word, 'two');
    // Enter neither inserted a newline nor let the editor edit anything: the
    // host owns the whole edit.
    expect(controller.text, before);
    expect(find.byType(_PromptsView), findsNothing);
  });

  editorTest('Tab accepts the highlighted prompt', (
    WidgetTester tester,
  ) async {
    await pumpEditor(tester);
    await type(tester);
    await settleDebounce(tester);
    source.answer(<String>['one', 'two']);
    await tester.pump();

    final String before = controller.text;
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(accepted, hasLength(1));
    expect((accepted.single.prompt! as _TestPrompt).word, 'one');
    // Not an indent.
    expect(controller.text, before);
    expect(find.byType(_PromptsView), findsNothing);
  });

  editorTest('Tab indents again once the overlay is gone', (
    WidgetTester tester,
  ) async {
    await pumpEditor(tester);
    await type(tester);
    await settleDebounce(tester);
    source.answer(<String>['one']);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    // Past the retry the input connection schedules after a text change, so no
    // timer is left pending when the tree comes down.
    await tester.pump(const Duration(milliseconds: 20));

    expect(accepted, isEmpty);
    expect(controller.codeLines[0].text, startsWith('alph  '));
  });

  editorTest('Escape dismisses the overlay', (WidgetTester tester) async {
    await pumpEditor(tester);
    await type(tester);
    await settleDebounce(tester);
    source.answer(<String>['one']);
    await tester.pump();
    expect(find.byType(_PromptsView), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(find.byType(_PromptsView), findsNothing);
    expect(accepted, isEmpty);
    expect(overlay.isShowing, isFalse);
  });

  editorTest('the manual trigger asks immediately, with no debounce', (
    WidgetTester tester,
  ) async {
    await pumpEditor(tester);
    overlay.trigger();
    await tester.pump();

    expect(source.requests, hasLength(1));
    expect(
      source.requests.single.kind,
      CodeAutocompleteTriggerKind.manual,
    );

    source.answer(<String>['manual']);
    await tester.pump();
    expect(_visibleWords(tester), <String>['manual']);
  });

  editorTest('the manual trigger supersedes a keystroke still in its debounce', (
    WidgetTester tester,
  ) async {
    await pumpEditor(tester);
    await type(tester);
    overlay.trigger();
    await tester.pump();
    await settleDebounce(tester);

    // One ask, the manual one: the pending typing ask would otherwise fire a
    // moment later and overwrite its answer.
    expect(source.requests, hasLength(1));
    expect(source.requests.single.kind, CodeAutocompleteTriggerKind.manual);
  });

  editorTest('a click on a row accepts it', (WidgetTester tester) async {
    await pumpEditor(tester);
    await type(tester);
    await settleDebounce(tester);
    source.answer(<String>['one', 'two']);
    await tester.pump();

    await tester.tap(promptRow('two'));
    await tester.pump();

    expect((accepted.single.prompt! as _TestPrompt).word, 'two');
  });

  group('the synchronous path is unchanged', () {
    editorTest('a synchronous source opens the overlay in the asking frame', (
      WidgetTester tester,
    ) async {
      await pumpEditor(
        tester,
        hostApplies: false,
        syncSource: _SyncPromptsSource(<String>['sync1', 'sync2']),
        withAsync: false,
      );
      await type(tester);
      await settleDebounce(tester);

      expect(find.byType(_PromptsView), findsOneWidget);
      expect(_visibleWords(tester), <String>['sync1', 'sync2']);
    });

    editorTest('Enter strips the typed input and inserts the word', (
      WidgetTester tester,
    ) async {
      await pumpEditor(
        tester,
        hostApplies: false,
        syncSource: _SyncPromptsSource(<String>['alphabet'], input: 'alph'),
        withAsync: false,
      );
      await type(tester);
      await settleDebounce(tester);
      expect(find.byType(_PromptsView), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 20));

      // 'alpha' minus the backspace is 'alph'; the prompt's word replaces it.
      expect(controller.codeLines[0].text, 'alphabet');
      expect(controller.selection.extentOffset, 'alphabet'.length);
      expect(find.byType(_PromptsView), findsNothing);
    });

    editorTest('a synchronous source with nothing to say closes the overlay', (
      WidgetTester tester,
    ) async {
      final _SyncPromptsSource sync = _SyncPromptsSource(<String>['alphabet']);
      await pumpEditor(
        tester,
        hostApplies: false,
        syncSource: sync,
        withAsync: false,
      );
      await type(tester);
      await settleDebounce(tester);
      expect(find.byType(_PromptsView), findsOneWidget);

      sync.words = const <String>[];
      await type(tester);
      await settleDebounce(tester);

      expect(find.byType(_PromptsView), findsNothing);
    });
  });
}

List<String> _visibleWords(WidgetTester tester) => <String>[
  for (final Text text in tester.widgetList<Text>(find.byType(Text)))
    if (text.data != null) text.data!.substring(2),
];

/// A prompt that carries nothing but its word, so a host can read it back out of
/// [CodeAutocompleteResult.prompt] — the shape an LSP `CompletionItem` rides in.
class _TestPrompt extends CodePrompt {
  const _TestPrompt({required super.word});

  @override
  CodeAutocompleteResult get autocomplete =>
      CodeAutocompleteResult.fromWord(word);

  @override
  bool match(String input) => word.startsWith(input);
}

/// An asynchronous source that hands every request back to the test, so the test
/// decides when — and whether — each one is answered.
class _RecordingPromptsSource implements AsyncCodeAutocompletePromptsBuilder {
  final List<CodeAutocompleteRequest> requests = <CodeAutocompleteRequest>[];
  final List<Completer<CodeAutocompleteEditingValue?>> _pending =
      <Completer<CodeAutocompleteEditingValue?>>[];

  @override
  Future<CodeAutocompleteEditingValue?> build(
    CodeAutocompleteRequest request,
  ) {
    requests.add(request);
    final Completer<CodeAutocompleteEditingValue?> completer =
        Completer<CodeAutocompleteEditingValue?>();
    _pending.add(completer);
    return completer.future;
  }

  void answer(List<String> words) => answerAt(_pending.length - 1, words);

  void answerAt(int index, List<String> words) {
    _pending[index].complete(
      CodeAutocompleteEditingValue(
        input: '',
        prompts: <CodePrompt>[
          for (final String word in words) _TestPrompt(word: word),
        ],
        index: 0,
      ),
    );
  }
}

class _SyncPromptsSource implements CodeAutocompletePromptsBuilder {
  _SyncPromptsSource(this.words, {this.input = ''});

  List<String> words;
  final String input;

  @override
  CodeAutocompleteEditingValue? build(
    BuildContext context,
    CodeLine codeLine,
    CodeLineSelection selection,
  ) => words.isEmpty
      ? null
      : CodeAutocompleteEditingValue(
          input: input,
          prompts: <CodePrompt>[
            for (final String word in words) _TestPrompt(word: word),
          ],
          index: 0,
        );
}

/// The host's prompts list. Rows are `'> word'` for the highlighted one and
/// `'  word'` otherwise, so a `find.text` says both what is listed and what is
/// selected.
class _PromptsView extends StatelessWidget implements PreferredSizeWidget {
  const _PromptsView({required this.notifier, required this.onSelected});

  final ValueNotifier<CodeAutocompleteEditingValue> notifier;
  final ValueChanged<CodeAutocompleteResult> onSelected;

  @override
  Size get preferredSize => const Size(240, 420);

  @override
  Widget build(BuildContext context) => SizedBox.fromSize(
    size: preferredSize,
    child: ValueListenableBuilder<CodeAutocompleteEditingValue>(
      valueListenable: notifier,
      builder:
          (
            BuildContext context,
            CodeAutocompleteEditingValue value,
            Widget? _,
          ) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (int i = 0; i < value.prompts.length; i++)
                GestureDetector(
                  onTap: () =>
                      onSelected(value.copyWith(index: i).autocomplete),
                  child: Text(
                    '${i == value.index ? '>' : ' '} ${value.prompts[i].word}',
                    textDirection: TextDirection.ltr,
                  ),
                ),
            ],
          ),
    ),
  );
}
