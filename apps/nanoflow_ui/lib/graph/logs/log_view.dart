import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderSliverFixedExtentList;

import '../../state/step_details.dart';
import '../../state/step_files.dart';
import '../../theme.dart';
import '../../widgets/clickable.dart';

/// How many lines of a log or a document are shown until `Show all`: a log's
/// last, a document's first (docs/ui-spec.md «Окно деталей шага»: «Большие
/// данные показаны не целиком»).
const previewLines = 1000;

/// How many characters of a line are shown until `Show all`.
const previewLineLength = 2000;

/// What is cut from a long text, and how to show all of it.
typedef TextCut = ({String text, VoidCallback showAll});

/// Lines of monospace text, laid out lazily: only the lines in view are
/// built, so a text of a million lines scrolls as one of ten does. Lines do
/// not wrap: the text is as wide as its [widest] line and scrolls sideways.
/// It can be selected and copied.
class MonoLines extends StatefulWidget {
  const MonoLines({
    super.key,
    required this.count,
    required this.lineAt,
    required this.widest,
    this.controller,
    this.cursor = false,
    this.cut,
  });

  /// The key of the scrolling list of lines.
  static const linesKey = ValueKey('mono lines');

  /// The key of the note that says what is not shown.
  static const cutKey = ValueKey('text cut');

  /// The height of a line: the mockups' 11.5 px at 1.7.
  static final lineHeight =
      AppText.textLine.fontSize! * AppText.textLine.height!;

  final int count;
  final String Function(int index) lineAt;

  /// The longest line.
  final String widest;

  /// Scrolls the lines up and down.
  final ScrollController? controller;

  /// Whether a cursor follows the last line: the text is still written.
  final bool cursor;

  /// What is not shown; `null` when all is.
  final TextCut? cut;

  @override
  State<MonoLines> createState() => _MonoLinesState();
}

class _MonoLinesState extends State<MonoLines> {
  final _sideways = ScrollController();
  ScrollController? _own;

  ScrollController get _lines =>
      widget.controller ?? (_own ??= ScrollController());

  String? _measured;
  double _width = 0;

  @override
  void dispose() {
    _sideways.dispose();
    _own?.dispose();
    super.dispose();
  }

  double _widthOf(String line, TextScaler scaler) {
    if (line != _measured) {
      final painter = TextPainter(
        text: TextSpan(text: line, style: AppText.textLine),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      _width = painter.width;
      painter.dispose();
      _measured = line;
    }
    return _width;
  }

  @override
  Widget build(BuildContext context) {
    final cut = widget.cut;
    final textWidth = _widthOf(widget.widest, MediaQuery.textScalerOf(context));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (cut != null) _CutNote(cut),
        Expanded(
          child: ColoredBox(
            color: AppColors.textArea,
            child: LayoutBuilder(
              builder: (context, constraints) => Scrollbar(
                controller: _lines,
                // The lines scroll inside the sideways scroll.
                notificationPredicate: (notification) =>
                    notification.depth == 1,
                child: Scrollbar(
                  controller: _sideways,
                  child: SingleChildScrollView(
                    controller: _sideways,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: math.max(constraints.maxWidth, textWidth + 33),
                      height: constraints.maxHeight,
                      child: SelectionArea(
                        child: CustomScrollView(
                          key: MonoLines.linesKey,
                          controller: _lines,
                          slivers: [
                            SliverPadding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              sliver: _Lines(
                                itemExtent: MonoLines.lineHeight,
                                delegate: SliverChildBuilderDelegate(
                                  (context, i) => i == widget.count
                                      ? const _Cursor()
                                      : Text(
                                          widget.lineAt(i),
                                          style: AppText.textLine,
                                          maxLines: 1,
                                          softWrap: false,
                                        ),
                                  childCount:
                                      widget.count + (widget.cursor ? 1 : 0),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Lines of one height, laid out again whenever they are given anew: a
/// fixed-extent list is not, when only lines out of view are added, and its
/// scroll extent would stay that of the lines it had.
class _Lines extends SliverFixedExtentList {
  const _Lines({required super.delegate, required super.itemExtent});

  @override
  void updateRenderObject(
    BuildContext context,
    RenderSliverFixedExtentList renderObject,
  ) {
    super.updateRenderObject(context, renderObject);
    renderObject.markNeedsLayout();
  }
}

/// `Showing the last 1,000 of 52,340 lines` and `Show all`.
class _CutNote extends StatelessWidget {
  const _CutNote(this.cut);

  final TextCut cut;

  @override
  Widget build(BuildContext context) => Container(
    key: MonoLines.cutKey,
    height: 26,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: const BoxDecoration(
      color: AppColors.textArea,
      border: Border(bottom: BorderSide(color: AppColors.divider)),
    ),
    child: Row(
      spacing: 8,
      children: [
        Flexible(
          child: Text(
            cut.text,
            style: AppText.listNote,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Clickable(
          onTap: cut.showAll,
          child: Text(
            'Show all',
            style: AppText.listNote.copyWith(color: AppColors.accentText),
          ),
        ),
      ],
    ),
  );
}

/// The block after the last line of a log still being written.
class _Cursor extends StatelessWidget {
  const _Cursor();

  @override
  Widget build(BuildContext context) => const Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: 7,
      height: 14,
      child: ColoredBox(color: AppColors.accentLine),
    ),
  );
}

/// `1,500`.
String _thousands(int n) =>
    n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => ',');

/// [line] as shown: tabs to the next multiple of 8 columns, a carriage
/// return before the end dropped, and cut at [previewLineLength] unless
/// [whole].
String _shown(String line, {required bool whole}) {
  var text = line.endsWith('\r') ? line.substring(0, line.length - 1) : line;
  if (text.contains('\t')) {
    final out = StringBuffer();
    for (final char in text.split('')) {
      if (char == '\t') {
        out.write(' ' * (8 - out.length % 8));
      } else {
        out.write(char);
      }
    }
    text = out.toString();
  }
  return whole || text.length <= previewLineLength
      ? text
      : '${text.substring(0, previewLineLength)} …';
}

/// The longest of [lines] from [from] to [to].
String _widestOf(List<String> lines, int from, int to) {
  var widest = '';
  for (var i = from; i < to; i++) {
    if (lines[i].length > widest.length) widest = lines[i];
  }
  return widest;
}

/// A step's log in monospace, as it grows (docs/ui-spec.md «Logs»): its
/// last [previewLines] lines until `Show all`.
///
/// It opens at the end of the log and holds on to it as lines come, until
/// the user scrolls up; scrolled back down, it holds on again. Whether it
/// holds on is [following]. A running step's log ends in a cursor.
class LogView extends StatefulWidget {
  const LogView({
    super.key,
    required this.files,
    required this.step,
    required this.following,
  });

  final StepFiles files;
  final StepDetails step;
  final ValueNotifier<bool> following;

  /// What a finished step that wrote no log shows.
  static const nothing = 'The step wrote nothing to its log';

  @override
  State<LogView> createState() => _LogViewState();
}

class _LogViewState extends State<LogView> {
  /// How long a step's log may stay empty before the view says it is: the
  /// text on disk comes a moment after the view opens.
  static const _quietTime = Duration(milliseconds: 300);

  late final StreamSubscription<String> _log;
  final _scroll = ScrollController();

  /// The complete lines, and what is written after the last of them.
  final List<String> _lines = [];
  String _partial = '';

  /// The longest complete line.
  String _longest = '';

  /// The first line shown: a long log shows its tail.
  int _start = 0;
  bool _all = false;
  Object? _error;
  bool _quiet = false;
  late final Timer _quietTimer;

  int get _count => _lines.length + (_partial.isEmpty ? 0 : 1);

  @override
  void initState() {
    super.initState();
    final step = widget.step;
    _log = widget.files
        .stepLog(step.sessionId, step.runId, step.stepId)
        .listen(_add, onError: _failed);
    _scroll.addListener(_scrolled);
    _quietTimer = Timer(_quietTime, () => setState(() => _quiet = true));
  }

  @override
  void dispose() {
    _quietTimer.cancel();
    unawaited(_log.cancel());
    _scroll.dispose();
    super.dispose();
  }

  void _add(String text) {
    _error = null;
    final parts = '$_partial$text'.split('\n');
    _partial = parts.removeLast();
    for (final line in parts) {
      _lines.add(line);
      if (line.length > _longest.length) _longest = line;
    }
    setState(() {
      if (widget.following.value && !_all) {
        _start = math.max(0, _count - previewLines);
      }
    });
    if (widget.following.value) _toEnd();
  }

  /// A read that failed: reading goes on, and what was read stays.
  void _failed(Object error) => setState(() => _error = error);

  /// Holds on to the end once the lines are laid out.
  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && _scroll.hasClients) {
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    }
  });

  void _scrolled() {
    final position = _scroll.position;
    widget.following.value = position.pixels >= position.maxScrollExtent - 1;
  }

  void _showAll() {
    final above = _start;
    setState(() {
      _all = true;
      _start = 0;
    });
    // The lines in view stay in view.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(
        widget.following.value
            ? _scroll.position.maxScrollExtent
            : _scroll.offset + above * MonoLines.lineHeight,
      );
    });
  }

  String _lineAt(int index) {
    final i = _start + index;
    return _shown(i < _lines.length ? _lines[i] : _partial, whole: _all);
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null && _count == 0) {
      return TabNote(
        'Could not read the log: $error',
        color: AppColors.dangerText,
      );
    }
    final running = widget.step.running;
    if (_count == 0 && !running) {
      return _quiet ? const TabNote(LogView.nothing) : const TabNote('');
    }
    final shown = _count - _start;
    final widest = _start == 0
        ? _longest
        : _widestOf(_lines, _start, _lines.length);
    return MonoLines(
      count: shown,
      lineAt: _lineAt,
      widest: _shown(
        _partial.length > widest.length ? _partial : widest,
        whole: _all,
      ),
      controller: _scroll,
      cursor: running,
      cut: _start == 0
          ? null
          : (
              text:
                  'Showing the last ${_thousands(shown)} of '
                  '${_thousands(_count)} lines',
              showAll: _showAll,
            ),
    );
  }
}

/// A document's value as JSON, two-space indented: its first
/// [previewLines] lines until `Show all`.
class DocumentView extends StatefulWidget {
  const DocumentView({
    super.key,
    required this.files,
    required this.sessionId,
    required this.documentId,
  });

  final StepFiles files;
  final String sessionId;
  final String documentId;

  @override
  State<DocumentView> createState() => _DocumentViewState();
}

class _DocumentViewState extends State<DocumentView> {
  static const _json = JsonEncoder.withIndent('  ');

  late final Future<List<String>> _lines = widget.files
      .documentValue(widget.sessionId, widget.documentId)
      .then((value) => _json.convert(value).split('\n'));

  bool _all = false;

  /// The longest line shown, once found.
  String? _widest;

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _lines,
    builder: (context, snapshot) {
      final error = snapshot.error;
      if (error != null) {
        return TabNote(
          'Could not read the document: $error',
          color: AppColors.dangerText,
        );
      }
      final lines = snapshot.data;
      if (lines == null) return const TabNote('');
      final cut = !_all && lines.length > previewLines;
      final shown = cut ? previewLines : lines.length;
      final widest = _widest ??= _shown(
        _widestOf(lines, 0, shown),
        whole: _all,
      );
      return MonoLines(
        count: shown,
        lineAt: (i) => _shown(lines[i], whole: _all),
        widest: widest,
        cut: cut
            ? (
                text:
                    'Showing the first ${_thousands(previewLines)} of '
                    '${_thousands(lines.length)} lines',
                showAll: () => setState(() {
                  _all = true;
                  _widest = null;
                }),
              )
            : null,
      );
    },
  );
}

/// What a tab says instead of a text: that there is none, or why it cannot
/// be read.
class TabNote extends StatelessWidget {
  const TabNote(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
    color: AppColors.textArea,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    alignment: Alignment.topLeft,
    child: SelectableText(
      text,
      style: AppText.textAreaNote.copyWith(color: color),
    ),
  );
}
