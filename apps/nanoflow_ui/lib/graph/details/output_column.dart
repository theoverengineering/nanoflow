import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../platform/shell.dart';
import '../../state/step_details.dart';
import '../../state/step_files.dart';
import '../../state/visit_details.dart';
import '../../theme.dart';
import '../../widgets/clickable.dart';
import '../../widgets/failure_note.dart';
import '../../widgets/icons.dart';
import '../../widgets/path_bar.dart';
import '../logs/log_view.dart';
import 'data_view.dart';
import 'parts.dart';

/// A tab of the `Output` column.
enum OutputTab { output, log }

/// The `Output` column of the step details window (docs/ui-spec.md «Окно
/// деталей шага»): the tabs `Output` and `Log`. `Output` says that the data
/// passes the node's `out` — it is stored only once the graph program has
/// checked it — with its size, and shows it as `Schema` or `JSON`; a fork's
/// output is its outcome. `—` and why when the node declares no `out`, `not
/// yet` while the step runs, the run's error when it failed on the step.
/// `Log` is the step's log as it grows. The file of the open tab is at the
/// bottom. Empty for a node's description alone.
class OutputColumn extends StatefulWidget {
  const OutputColumn({
    super.key,
    required this.details,
    required this.files,
    required this.shell,
    required this.graphFile,
  });

  final VisitDetails details;
  final StepFiles files;
  final Shell shell;

  /// The graph file: paths are shown from its directory.
  final String graphFile;

  static Key tabKey(OutputTab tab) => ValueKey(('output tab', tab));

  /// What the column says for a node that declares no `out`.
  static const noOutput =
      'This node declares no out: what its command '
      'prints goes to its log';

  @override
  State<OutputColumn> createState() => _OutputColumnState();
}

class _OutputColumnState extends State<OutputColumn> {
  OutputTab _tab = OutputTab.output;
  DataMode _mode = DataMode.json;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) =>
        _column(narrow: constraints.maxWidth < _roomForTitle),
  );

  /// Narrower than this, the column's head has no room for `OUTPUT` beside
  /// its tabs and the data's toggle.
  static const _roomForTitle = 360.0;

  Widget _column({required bool narrow}) {
    final details = widget.details;
    final step = details.step;
    final output = step?.output;
    final documentId = output?.documentId;
    final showsData = _tab == OutputTab.output && documentId != null;
    final path = step == null
        ? null
        : _tab == OutputTab.log
        ? widget.files.logPath(step.stepId)
        : documentId == null
        ? null
        : widget.files.documentPath(step.sessionId, documentId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ColumnHead(
          children: [
            // Narrow, the tabs say it.
            if (!narrow || output == null) const SectionLabel('Output'),
            if (step != null && output != null)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Row(
                  spacing: 2,
                  children: [
                    for (final (which, label, marked) in [
                      (OutputTab.output, 'Output', output.marked),
                      (OutputTab.log, 'Log', false),
                    ])
                      _Tab(
                        key: OutputColumn.tabKey(which),
                        label: label,
                        marked: marked,
                        selected: which == _tab,
                        onTap: () => setState(() => _tab = which),
                      ),
                  ],
                ),
              ),
            const Spacer(),
            if (showsData)
              ModeToggle(
                mode: _mode,
                onChanged: (mode) => setState(() => _mode = mode),
              ),
          ],
        ),
        Expanded(
          child: step == null || output == null
              ? const SizedBox.shrink()
              : _tab == OutputTab.log
              ? _LogTab(
                  key: ValueKey(('log', step.sessionId, step.stepId)),
                  files: widget.files,
                  step: step,
                )
              : _output(details, step, output),
        ),
        if (path != null)
          PathBar(
            path: path,
            root: p.dirname(widget.graphFile),
            buttons: [
              FileButton(
                'Open in editor',
                onTap: () => openPath(
                  context,
                  widget.shell.openInEditor,
                  path,
                  'Could not open ${p.basename(path)} in an editor',
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _output(VisitDetails details, StepDetails step, StepDocument output) {
    final error = details.error;
    final documentId = output.documentId;
    final failure = error == null
        ? null
        : DataNote('Run failed: $error', color: AppColors.dangerText);
    if (documentId == null) {
      return Align(
        alignment: Alignment.topLeft,
        child:
            failure ??
            DataNote(
              output.state == DocumentState.undeclared
                  ? OutputColumn.noOutput
                  : output.message ?? '',
              dash: output.state == DocumentState.undeclared,
            ),
      );
    }
    final fork = details.description?.fork ?? false;
    final type = details.description?.output;
    return DocumentData(
      key: ValueKey(('output', step.sessionId, documentId)),
      files: widget.files,
      sessionId: step.sessionId,
      documentId: documentId,
      builder: (context, document) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ?failure,
          DataRowBar(
            children: [
              if (fork)
                Text('outcome', style: AppText.fromText)
              else ...[
                const CheckIcon(
                  size: 12,
                  color: AppColors.finished,
                  strokeWidth: 1.8,
                ),
                Text('passes', style: AppText.fromText),
                if (type != null) TypePill(type.label),
              ],
              const Spacer(),
              Text(document.size, style: AppText.filePath),
            ],
          ),
          Expanded(
            child: DataView(value: document.value, mode: _mode),
          ),
        ],
      ),
    );
  }
}

/// A tab: underlined when [selected]; `—` after a [marked] one's label.
class _Tab extends StatelessWidget {
  const _Tab({
    super.key,
    required this.label,
    required this.marked,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool marked;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = selected
        ? AppText.outputTab.copyWith(color: AppColors.textPrimary)
        : AppText.outputTab;
    return Clickable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? AppColors.accentLine : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text.rich(
          TextSpan(
            text: label,
            children: [
              if (marked)
                TextSpan(
                  text: ' —',
                  style: style.copyWith(color: AppColors.textDim),
                ),
            ],
          ),
          style: style,
          maxLines: 1,
          softWrap: false,
        ),
      ),
    );
  }
}

/// The step's log, holding on to its end while it grows.
class _LogTab extends StatefulWidget {
  const _LogTab({super.key, required this.files, required this.step});

  final StepFiles files;
  final StepDetails step;

  @override
  State<_LogTab> createState() => _LogTabState();
}

class _LogTabState extends State<_LogTab> {
  /// Whether the log holds on to its end: the log view lets go of it first.
  final _following = ValueNotifier(true);

  @override
  void dispose() {
    _following.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      LogView(files: widget.files, step: widget.step, following: _following);
}
