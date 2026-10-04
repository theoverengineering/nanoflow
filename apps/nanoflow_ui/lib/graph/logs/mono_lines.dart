import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderSliverFixedExtentList;

import '../../state/texts.dart' show thousands;
import '../../theme.dart';
import '../../widgets/clickable.dart';

/// How many lines of a log or a document are shown until `Show all`: a log's
/// last, a document's first (docs/ui-spec.md «Окно деталей эффекта»: «Большие
/// данные показаны не целиком»).
const previewLines = 1000;

/// How many characters of a line are shown until `Show all`.
const previewLineLength = 2000;

/// What the note over a text not shown whole says: which [lines] of it are
/// shown, when not all, and whether lines are cut because the [widest] line
/// shown is longer than [previewLineLength]; `null` when nothing is cut.
String? cutText({String? lines, required String widest}) {
  final cutAt = 'cut at ${thousands(previewLineLength)} characters';
  final long = widest.length > previewLineLength;
  return switch (lines) {
    null => long ? 'Lines $cutAt' : null,
    final lines => long ? '$lines, $cutAt' : lines,
  };
}

/// The first lines of a text, as shown until `Show all`: how many, the
/// longest of them, and what the note over them says, `null` when nothing is
/// cut.
typedef TextStart = ({int count, String widest, String? cut});

/// The first [previewLines] of [lines] — all of them when [all] — with lines
/// cut at [previewLineLength] unless [all] (docs/ui-spec.md «Окно деталей
/// эффекта»: «у JSON — начало»).
TextStart textStart(List<String> lines, {required bool all}) {
  final linesCut = !all && lines.length > previewLines;
  final count = linesCut ? previewLines : lines.length;
  final widest = widestLine(lines, 0, count);
  return (
    count: count,
    widest: widest,
    cut: all
        ? null
        : cutText(
            lines: linesCut
                ? 'Showing the first ${thousands(previewLines)} of '
                      '${thousands(lines.length)} lines'
                : null,
            widest: widest,
          ),
  );
}

/// What is cut from a long text, and how to show all of it.
typedef TextCut = ({String text, VoidCallback showAll});

/// Lines of monospace text, laid out lazily: only the lines in view are
/// built, so a text of a million lines scrolls as one of ten does. Lines do
/// not wrap: the text is as wide as its [widest] line and scrolls sideways.
/// It can be selected and copied.
///
/// The lines are in [style] on [background], [padding] round them; with
/// [spanOf], each line in its parts' own colors.
class MonoLines extends StatefulWidget {
  MonoLines({
    super.key,
    required this.count,
    required this.lineAt,
    required this.widest,
    this.controller,
    this.cursor = false,
    this.cut,
    TextStyle? style,
    this.spanOf,
    this.background = AppColors.textArea,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
  }) : style = style ?? AppText.textLine;

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

  final TextStyle style;

  /// A line as styled parts.
  final InlineSpan Function(String line)? spanOf;

  final Color background;
  final EdgeInsets padding;

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
        text: TextSpan(text: line, style: widget.style),
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

  /// A line, in its parts' colors when there is [MonoLines.spanOf].
  Widget _line(String line) => switch (widget.spanOf) {
    final spanOf? => Text.rich(
      spanOf(line),
      style: widget.style,
      maxLines: 1,
      softWrap: false,
    ),
    null => Text(line, style: widget.style, maxLines: 1, softWrap: false),
  };

  @override
  Widget build(BuildContext context) {
    final cut = widget.cut;
    final textWidth = _widthOf(widget.widest, MediaQuery.textScalerOf(context));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (cut != null) _CutNote(cut, background: widget.background),
        Expanded(
          child: ColoredBox(
            color: widget.background,
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
                      width: math.max(
                        constraints.maxWidth,
                        textWidth + widget.padding.horizontal + 1,
                      ),
                      height: constraints.maxHeight,
                      child: SelectionArea(
                        child: CustomScrollView(
                          key: MonoLines.linesKey,
                          controller: _lines,
                          slivers: [
                            SliverPadding(
                              padding: widget.padding,
                              sliver: _Lines(
                                itemExtent:
                                    widget.style.fontSize! *
                                    widget.style.height!,
                                delegate: SliverChildBuilderDelegate(
                                  (context, i) => i == widget.count
                                      ? const _Cursor()
                                      : _line(widget.lineAt(i)),
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
  const _CutNote(this.cut, {required this.background});

  final TextCut cut;
  final Color background;

  @override
  Widget build(BuildContext context) => Container(
    key: MonoLines.cutKey,
    height: 26,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      color: background,
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

/// [line] as shown: tabs to the next multiple of 8 columns, a carriage
/// return before the end dropped, and cut at [previewLineLength] unless
/// [whole].
String shownLine(String line, {required bool whole}) {
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
String widestLine(List<String> lines, int from, int to) {
  var widest = '';
  for (var i = from; i < to; i++) {
    if (lines[i].length > widest.length) widest = lines[i];
  }
  return widest;
}
