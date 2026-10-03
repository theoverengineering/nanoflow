// migrated in Task 12: still on the old model (runs, the README graph,
// GraphSource); it does not compile until then.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nanoflow_model/nanoflow_model.dart' show StepStatus;

import '../../state/log_rows.dart';
import '../../state/texts.dart' show count, shortId;
import '../../theme.dart';
import '../../widgets/clickable.dart';
import '../run_switcher.dart' show RunSign;
import 'step_bar.dart';

/// The steps of the selected run on the left of the `Logs` panel
/// (docs/ui-spec.md «Logs»: «Лента шагов»), as the rows of `logRows` give
/// them: each step's sign, node, a fork's outcome and where it went or a
/// failure's error, `2 starts`, when it started, how long it took — a
/// running one's time going on — and its bar on the session's time scale,
/// striped while it runs. Inherited steps are dimmed; `split · run e5f6`
/// stands where a run split; an ended run ends with how it ended, a split
/// one with links to its children.
///
/// The selected step is highlighted, and kept in view as the selection
/// moves; while the run is followed, so are the rows after it. Scrolled
/// down, the list says how many steps are above it.
class StepList extends StatefulWidget {
  const StepList({
    super.key,
    required this.rows,
    required this.scale,
    required this.selectedStepId,
    required this.following,
    required this.onSelect,
    required this.onSelectRun,
  });

  final List<LogRow> rows;

  /// The time scale of the rows' bars, for the axis.
  final TimeScale scale;

  final String? selectedStepId;

  /// Whether the selection moves on to each new step of the run.
  final bool following;

  /// A click on a step's row.
  final ValueChanged<StepRow> onSelect;

  /// A click on a run the selected one split into.
  final ValueChanged<String> onSelectRun;

  static Key rowKey(String stepId) => ValueKey(('step row', stepId));
  static Key splitKey(String runId) => ValueKey(('split', runId));
  static Key childKey(String runId) => ValueKey(('child run', runId));
  static const endKey = ValueKey('end row');
  static const earlierKey = ValueKey('earlier steps');

  @override
  State<StepList> createState() => _StepListState();
}

/// The mockups' sizes.
abstract final class _Sizes {
  static const header = 24.0;
  static const row = 22.0;
  static const selected = 24.0;
  static const split = 20.0;
  static const earlier = 20.0;
  static const padding = 16.0;
  static const gap = 10.0;
  static const sign = StepIcon.size;
  static const started = 58.0;
  static const took = 50.0;
  static const timeline = 150.0;

  /// The least room the step's name keeps before the timeline gives way.
  static const name = 100.0;

  /// Narrower than this, there is no timeline.
  static const leastTimeline = 40.0;
}

class _StepListState extends State<StepList> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _keepInView();
  }

  @override
  void didUpdateWidget(StepList old) {
    super.didUpdateWidget(old);
    if (old.selectedStepId != widget.selectedStepId ||
        widget.following && old.rows.length != widget.rows.length) {
      _keepInView();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  double _extentOf(LogRow row) => switch (row) {
    StepRow(:final stepId) =>
      stepId == widget.selectedStepId ? _Sizes.selected : _Sizes.row,
    SplitRow() => _Sizes.split,
    EndRow() => _Sizes.row,
  };

  /// Scrolls the selected row into view once laid out, and while
  /// following, the rows after it too; clear of the note on top.
  void _keepInView() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted || !_scroll.hasClients) return;
    final rows = widget.rows;
    var top = 0.0;
    double? start;
    double? end;
    for (final row in rows) {
      final extent = _extentOf(row);
      if (row is StepRow && row.stepId == widget.selectedStepId) {
        start = top;
        end = top + extent;
      }
      top += extent;
    }
    if (start == null || end == null) return;
    final position = _scroll.position;
    final view = position.viewportDimension;
    if (widget.following) end = math.min(top, start + view);
    var offset = position.pixels;
    if (end > offset + view) offset = end - view;
    final cover = offset > 0 ? _Sizes.earlier : 0.0;
    if (start < offset + cover) {
      offset = start <= 0 ? 0 : start - _Sizes.earlier;
    }
    offset = offset.clamp(0.0, position.maxScrollExtent);
    if (offset != position.pixels) _scroll.jumpTo(offset);
  });

  /// How many steps are scrolled away above, or under the note on top.
  int _earlier() {
    if (!_scroll.hasClients || _scroll.offset <= 0) return 0;
    final hidden = _scroll.offset + _Sizes.earlier;
    var top = 0.0;
    var count = 0;
    for (final row in widget.rows) {
      top += _extentOf(row);
      if (top > hidden) break;
      if (row is StepRow) count++;
    }
    return count;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final room =
          constraints.maxWidth -
          2 * _Sizes.padding -
          _Sizes.sign -
          _Sizes.started -
          _Sizes.took -
          4 * _Sizes.gap -
          _Sizes.name;
      final timeline = math.min(_Sizes.timeline, room);
      final columns = _Columns(
        timeline: timeline >= _Sizes.leastTimeline ? timeline : null,
      );
      final rows = widget.rows;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ColumnTitles(columns, axis: widget.scale.axis),
          Expanded(
            child: Stack(
              children: [
                ListView.builder(
                  controller: _scroll,
                  itemCount: rows.length,
                  itemExtentBuilder: (i, _) =>
                      i < rows.length ? _extentOf(rows[i]) : null,
                  itemBuilder: (context, i) => switch (rows[i]) {
                    final StepRow row => _StepRowView(
                      row,
                      columns: columns,
                      selected: row.stepId == widget.selectedStepId,
                      onTap: () => widget.onSelect(row),
                    ),
                    final SplitRow row => _SplitRowView(row),
                    final EndRow row => _EndRowView(
                      row,
                      columns: columns,
                      onSelectRun: widget.onSelectRun,
                    ),
                  },
                ),
                Positioned(
                  left: 0,
                  top: 0,
                  right: 0,
                  child: ListenableBuilder(
                    listenable: _scroll,
                    builder: (context, _) => switch (_earlier()) {
                      0 => const SizedBox.shrink(),
                      final count => _EarlierNote(
                        count,
                        onTap: () => _scroll.animateTo(
                          0,
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOut,
                        ),
                      ),
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}

/// The widths of the columns after the step's: the timeline's, `null`
/// without room for it.
final class _Columns {
  const _Columns({required this.timeline});

  final double? timeline;

  /// [sign], [step] (taking the room left), [started], [took] and [bar] in a
  /// row, as the mockup's flex row with its gaps and padding has them.
  Widget row({
    required Widget sign,
    required Widget step,
    required Widget started,
    required Widget took,
    Widget? bar,
  }) {
    final timeline = this.timeline;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _Sizes.padding),
      child: Row(
        spacing: _Sizes.gap,
        children: [
          SizedBox(
            width: _Sizes.sign,
            child: Center(child: sign),
          ),
          Expanded(child: step),
          SizedBox(width: _Sizes.started, child: started),
          SizedBox(width: _Sizes.took, child: took),
          if (timeline != null) SizedBox(width: timeline, child: bar),
        ],
      ),
    );
  }
}

/// `Step`, `Started`, `Took`, and the timeline's axis: `0m 6m 12m`.
class _ColumnTitles extends StatelessWidget {
  const _ColumnTitles(this.columns, {required this.axis});

  final _Columns columns;
  final List<String> axis;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: _Sizes.header,
    child: columns.row(
      sign: const SizedBox.shrink(),
      step: Text('Step', style: AppText.columnTitle),
      started: Text('Started', style: AppText.columnTitle),
      took: Text(
        'Took',
        style: AppText.columnTitle,
        textAlign: TextAlign.right,
      ),
      bar: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final label in axis) Text(label, style: AppText.axisLabel),
        ],
      ),
    ),
  );
}

/// A step's row.
class _StepRowView extends StatelessWidget {
  const _StepRowView(
    this.row, {
    required this.columns,
    required this.selected,
    required this.onTap,
  });

  final StepRow row;
  final _Columns columns;
  final bool selected;
  final VoidCallback onTap;

  /// How inherited steps are dimmed.
  static const _dimmed = 0.55;

  @override
  Widget build(BuildContext context) {
    final running = row.status == StepStatus.running;
    final detail = row.detail;
    final starts = row.startsText;
    final step = Text.rich(
      TextSpan(
        text: row.name,
        style: selected
            ? AppText.stepName.copyWith(
                color: AppColors.selectedText,
                fontWeight: FontWeight.w600,
              )
            : AppText.stepName,
        children: [
          if (detail != null) ...[
            const TextSpan(text: ' '),
            TextSpan(
              text: detail,
              style: row.failure
                  ? AppText.stepDetail.copyWith(color: AppColors.dangerText)
                  : AppText.stepDetail,
            ),
          ],
        ],
      ),
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
    );
    Widget content = columns.row(
      sign: StepIcon(row.status),
      step: Row(
        // The width of a space between the name and the note.
        spacing: 3,
        children: [
          Flexible(
            child: detail == null
                ? step
                : Tooltip(message: detail, child: step),
          ),
          if (starts != null) _StartsNote(starts),
        ],
      ),
      started: Text(
        row.started,
        style: selected
            ? AppText.stepTime.copyWith(color: AppColors.accentText)
            : AppText.stepTime,
      ),
      took: Text(
        row.took,
        textAlign: TextAlign.right,
        style: running
            ? AppText.stepTook.copyWith(
                color: AppColors.running,
                fontWeight: FontWeight.w500,
              )
            : AppText.stepTook,
      ),
      bar: StepTrack(row),
    );
    if (row.inherited) content = Opacity(opacity: _dimmed, child: content);
    return Clickable(
      onTap: onTap,
      child: Container(
        key: StepList.rowKey(row.stepId),
        decoration: selected
            ? const BoxDecoration(color: AppColors.accentSurface)
            : null,
        child: Stack(
          fit: StackFit.expand,
          children: [
            content,
            if (selected)
              const Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 3,
                child: ColoredBox(color: AppColors.accentLine),
              ),
          ],
        ),
      ),
    );
  }
}

/// `2 starts`: an amber note.
class _StartsNote extends StatelessWidget {
  const _StartsNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5),
    decoration: BoxDecoration(
      color: AppColors.noteSurface,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(text, style: AppText.startsNote),
  );
}

/// `split · run e5f6` between two lines.
class _SplitRowView extends StatelessWidget {
  const _SplitRowView(this.row);

  final SplitRow row;

  @override
  Widget build(BuildContext context) {
    const line = Expanded(
      child: SizedBox(
        height: 1,
        child: ColoredBox(color: AppColors.panelBorder),
      ),
    );
    return Padding(
      key: StepList.splitKey(row.runId),
      padding: const EdgeInsets.symmetric(horizontal: _Sizes.padding),
      child: Row(
        spacing: 9,
        children: [
          line,
          Tooltip(
            message: row.runId,
            child: Text.rich(
              TextSpan(
                text: 'split · run ',
                children: [
                  TextSpan(
                    text: shortId(row.runId),
                    style: AppText.listNote.copyWith(fontFamily: AppText.mono),
                  ),
                ],
              ),
              style: AppText.listNote,
            ),
          ),
          line,
        ],
      ),
    );
  }
}

/// How the run ended: `Run finished`, `Run failed: exited with code 1`,
/// `Run split into` and links to its children, which scroll sideways when
/// there are more than fit; and when.
class _EndRowView extends StatelessWidget {
  const _EndRowView(
    this.row, {
    required this.columns,
    required this.onSelectRun,
  });

  final EndRow row;
  final _Columns columns;
  final ValueChanged<String> onSelectRun;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      row.text,
      style: AppText.listNote.copyWith(color: row.phase.textColor),
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
    );
    return KeyedSubtree(
      key: StepList.endKey,
      child: columns.row(
        sign: RunSign(row.phase),
        step: Row(
          spacing: 8,
          children: [
            if (row.children.isEmpty)
              Flexible(
                child: row.error == null
                    ? text
                    : Tooltip(message: row.text, child: text),
              )
            else ...[
              text,
              Flexible(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    spacing: 8,
                    children: [
                      for (final child in row.children)
                        Tooltip(
                          message: child,
                          child: Clickable(
                            onTap: () => onSelectRun(child),
                            child: Text(
                              shortId(child),
                              key: StepList.childKey(child),
                              style: AppText.runLink,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
        started: Text(row.atText, style: AppText.stepTime),
        took: const SizedBox.shrink(),
      ),
    );
  }
}

/// `↑ 8 earlier steps` over the top of the list; a click scrolls up.
class _EarlierNote extends StatelessWidget {
  const _EarlierNote(this.steps, {required this.onTap});

  final int steps;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Clickable(
    onTap: onTap,
    child: Container(
      key: StepList.earlierKey,
      height: _Sizes.earlier,
      color: AppColors.panel,
      padding: const EdgeInsets.only(left: 40),
      alignment: Alignment.centerLeft,
      child: Text(
        '↑ ${count(steps, 'earlier step')}',
        style: AppText.listNote.copyWith(color: AppColors.textFaint),
      ),
    ),
  );
}
