import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../platform/shell.dart';
import '../../state/step_details.dart';
import '../../state/step_files.dart';
import '../../state/visit_details.dart';
import '../../state/visits.dart';
import '../../theme.dart';
import '../../widgets/clickable.dart';
import '../../widgets/failure_note.dart';
import '../../widgets/icons.dart';
import '../../widgets/path_bar.dart';
import 'data_view.dart';
import 'parts.dart';

/// The `Input` column of the step details window (docs/ui-spec.md «Окно
/// деталей шага»): where the input came from — `from fix · 14:08:54`, which
/// goes to that step ([onVisit]), or `launch input` — the type of the node's
/// `in`, and the data as `Schema` or `JSON`; the document's file at the
/// bottom. `—` and why, when the node declares no `in`. Empty for a node's
/// description alone.
class InputColumn extends StatefulWidget {
  const InputColumn({
    super.key,
    required this.details,
    required this.files,
    required this.shell,
    required this.graphFile,
    required this.onVisit,
  });

  final VisitDetails details;
  final StepFiles files;
  final Shell shell;

  /// The graph file: paths are shown from its directory.
  final String graphFile;

  /// Shows another visit: the step the input came from.
  final ValueChanged<Visit> onVisit;

  /// The key of `from fix · 14:08:54`.
  static const fromKey = ValueKey('input from');

  /// What the column says for a node that declares no `in`.
  static const noInput = 'This node declares no in: it gets no data';

  @override
  State<InputColumn> createState() => _InputColumnState();
}

class _InputColumnState extends State<InputColumn> {
  DataMode _mode = DataMode.schema;

  @override
  Widget build(BuildContext context) {
    final details = widget.details;
    final step = details.step;
    final input = step?.input;
    final documentId = input?.documentId;
    final path = documentId == null
        ? null
        : widget.files.documentPath(step!.sessionId, documentId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ColumnHead(
          children: [
            const SectionLabel('Input'),
            const Spacer(),
            if (documentId != null)
              ModeToggle(
                mode: _mode,
                onChanged: (mode) => setState(() => _mode = mode),
              ),
          ],
        ),
        if (step != null && input != null)
          ..._body(details, step, input)
        else
          const Spacer(),
        if (path != null)
          PathBar(
            path: path,
            root: p.dirname(widget.graphFile),
            buttons: [
              FileButton(
                'Finder',
                onTap: () => openPath(
                  context,
                  widget.shell.revealInFinder,
                  path,
                  'Could not reveal ${p.basename(path)} in Finder',
                ),
              ),
            ],
          ),
      ],
    );
  }

  List<Widget> _body(
    VisitDetails details,
    StepDetails step,
    StepDocument input,
  ) {
    if (input.state == DocumentState.undeclared) {
      return [
        const Expanded(
          child: Align(
            alignment: Alignment.topLeft,
            child: DataNote(InputColumn.noInput, dash: true),
          ),
        ),
      ];
    }
    final documentId = input.documentId;
    return [
      DataRowBar(
        children: [
          ..._source(details.source),
          const Spacer(),
          if (details.description?.input case final type?) TypePill(type.label),
        ],
      ),
      Expanded(
        child: documentId == null
            ? Align(
                alignment: Alignment.topLeft,
                child: DataNote(input.message ?? ''),
              )
            : DocumentData(
                key: ValueKey(('input', step.sessionId, documentId)),
                files: widget.files,
                sessionId: step.sessionId,
                documentId: documentId,
                builder: (context, document) =>
                    DataView(value: document.value, mode: _mode),
              ),
      ),
    ];
  }

  /// `from fix · 14:08:54`, `launch input`, or nothing when that is not
  /// known.
  List<Widget> _source(InputSource? source) => switch (source) {
    FromStep(:final visit, :final time) => [
      const LinkIcon(size: 13, color: AppColors.textMuted),
      Text('from', style: AppText.fromText),
      Clickable(
        key: InputColumn.fromKey,
        onTap: () => widget.onVisit(visit),
        child: Text('${visit.node} · $time', style: AppText.fromLink),
      ),
    ],
    LaunchInput() => [
      const LinkIcon(size: 13, color: AppColors.textMuted),
      Text(
        'launch input',
        style: AppText.fromText.copyWith(color: AppColors.textPrimary),
      ),
    ],
    null => const [],
  };
}
