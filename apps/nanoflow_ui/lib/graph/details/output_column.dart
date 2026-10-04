import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../platform/shell.dart';
import '../../state/effect_details.dart';
import '../../state/effect_files.dart';
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

/// The `Output` column of the effect details window (docs/ui-spec.md «Окно
/// деталей эффекта»; spec §9 «Окно эффекта»): the tabs `Output` and `Log`.
/// `Output` shows the value the effect returned, with its size, as `Schema`
/// or `JSON`; `not yet` while the effect runs; the error the effect threw, with
/// its stack, when it failed. `Log` is the effect's log as it grows. The file
/// of the open tab is at the bottom. Empty for a node alone.
class OutputColumn extends StatefulWidget {
  const OutputColumn({
    super.key,
    required this.details,
    required this.files,
    required this.shell,
    required this.graphFile,
  });

  final VisitDetails details;
  final EffectFiles files;
  final Shell shell;

  /// The graph file: paths are shown from its directory.
  final String graphFile;

  static Key tabKey(OutputTab tab) => ValueKey(('output tab', tab));

  /// The key of the stack of a failed effect.
  static const stackKey = ValueKey('error stack');

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
    final effect = details.effect;
    final output = effect?.output;
    final documentId = output?.documentId;
    final showsData = _tab == OutputTab.output && documentId != null;
    final path = effect == null
        ? null
        : _tab == OutputTab.log
        ? widget.files.logPath(effect.effectId)
        : documentId == null
        ? null
        : widget.files.documentPath(effect.sessionId, documentId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ColumnHead(
          children: [
            // Narrow, the tabs say it.
            if (!narrow || output == null) const SectionLabel('Output'),
            if (effect != null && output != null)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Row(
                  spacing: 2,
                  children: [
                    for (final (which, label) in const [
                      (OutputTab.output, 'Output'),
                      (OutputTab.log, 'Log'),
                    ])
                      _Tab(
                        key: OutputColumn.tabKey(which),
                        label: label,
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
          child: effect == null || output == null
              ? const SizedBox.shrink()
              : _tab == OutputTab.log
              ? _LogTab(
                  key: ValueKey(('log', effect.sessionId, effect.effectId)),
                  files: widget.files,
                  effect: effect,
                )
              : _output(effect, output),
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

  Widget _output(EffectDetails effect, EffectDocument output) {
    final error = effect.error;
    if (error != null) return _Failure(error: error, stack: effect.stack);
    final documentId = output.documentId;
    if (documentId == null) {
      return Align(
        alignment: Alignment.topLeft,
        child: DataNote(output.message ?? ''),
      );
    }
    return DocumentData(
      key: ValueKey(('output', effect.sessionId, documentId)),
      files: widget.files,
      sessionId: effect.sessionId,
      documentId: documentId,
      builder: (context, document) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DataRowBar(
            children: [
              const CheckIcon(
                size: 12,
                color: AppColors.finished,
                strokeWidth: 1.8,
              ),
              Text('returned', style: AppText.fromText),
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

/// The error a failed effect threw, and its stack under it, in monospace.
class _Failure extends StatelessWidget {
  const _Failure({required this.error, required this.stack});

  final String error;
  final String? stack;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DataNote('Failed: $error', color: AppColors.dangerText),
      if (stack case final stack? when stack.isNotEmpty)
        Expanded(
          child: SingleChildScrollView(
            key: OutputColumn.stackKey,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SelectionArea(child: Text(stack, style: AppText.textLine)),
          ),
        ),
    ],
  );
}

/// A tab: underlined when [selected].
class _Tab extends StatelessWidget {
  const _Tab({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
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
        child: Text(label, style: style, maxLines: 1, softWrap: false),
      ),
    );
  }
}

/// The effect's log, holding on to its end while it grows.
class _LogTab extends StatefulWidget {
  const _LogTab({super.key, required this.files, required this.effect});

  final EffectFiles files;
  final EffectDetails effect;

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
  Widget build(BuildContext context) => LogView(
    files: widget.files,
    effect: widget.effect,
    following: _following,
  );
}
