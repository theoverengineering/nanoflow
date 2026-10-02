import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../platform/shell.dart';
import '../../state/step_files.dart';
import '../../state/visit_details.dart';
import '../../theme.dart';
import '../../widgets/copy_button.dart';
import '../../widgets/failure_note.dart';
import '../../widgets/icons.dart';
import '../../widgets/path_bar.dart';
import 'parts.dart';

/// The node column of the step details window (docs/ui-spec.md «Окно
/// деталей шага»): the node's command — a fork's `decide` — the types of its
/// `in` and `out` with their fields, where it sends the run, and the facts
/// of the step: `Started`, `Finished`, `Exit code`, every start, those the
/// engine's stopping interrupted marked. The step's directory is at the
/// bottom, with `Reveal in Finder` and a copy button.
class NodeColumn extends StatelessWidget {
  const NodeColumn({
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

  /// The key of what the column says of the node and the step, above the
  /// directory.
  static const descriptionKey = ValueKey('node description');

  /// The key of the step's directory.
  static const pathKey = ValueKey('step path');

  @override
  Widget build(BuildContext context) {
    final description = details.description;
    final facts = details.facts;
    final visit = details.visit;
    final path = visit == null ? null : files.stepPath(visit.stepId);
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.control,
        border: Border.symmetric(
          vertical: BorderSide(color: AppColors.panelBorder),
        ),
        boxShadow: [BoxShadow(color: Color(0x59000000), blurRadius: 30)],
      ),
      // Inside the borders, as CSS lays out a box's content.
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 20,
                ),
                child: Column(
                  key: descriptionKey,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (description == null)
                      Text(
                        'The graph has no node ${details.node}',
                        style: AppText.commandNote,
                      )
                    else
                      ..._describe(description),
                    if (facts != null) ...[
                      const SizedBox(height: 26),
                      const SectionLabel('This step'),
                      const SizedBox(height: 8),
                      _Facts(facts),
                    ],
                  ],
                ),
              ),
            ),
            if (path != null)
              PathBar(
                path: path,
                root: p.dirname(graphFile),
                height: 44,
                padding: 22,
                style: AppText.stepPath,
                color: AppColors.card,
                border: AppColors.panelBorder,
                pathKey: pathKey,
                buttons: [
                  FileButton(
                    'Reveal in Finder',
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    style: AppText.smallButton,
                    onTap: () => openPath(
                      context,
                      shell.revealInFinder,
                      path,
                      'Could not reveal ${p.basename(path)} in Finder',
                    ),
                  ),
                  CopyButton(
                    copy: () => shell.copyToClipboard(path),
                    failure: 'Could not copy the path of ${p.basename(path)}',
                    width: 28,
                    height: 26,
                    iconSize: 12,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _describe(NodeDescription node) => [
    SectionLabel(node.runTitle),
    const SizedBox(height: 8),
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.backdrop,
        border: Border.all(color: AppColors.panelBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectionArea(child: Text(node.run, style: AppText.commandBox)),
    ),
    // The YAML program runs commands through `sh -c` in the graph file's
    // directory (README «Программа графа»); a function runs in the graph
    // program itself.
    if (!node.function) ...[
      const SizedBox(height: 6),
      Text.rich(
        TextSpan(
          children: [
            const TextSpan(text: 'Runs through '),
            TextSpan(text: 'sh -c', style: AppText.commandNoteCode),
            const TextSpan(text: " in the graph's directory."),
          ],
        ),
        style: AppText.commandNote,
      ),
    ],
    const SizedBox(height: 22),
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        Expanded(child: _TypeCard('in', node.input)),
        Expanded(
          child: node.fork
              ? const SizedBox.shrink()
              : _TypeCard('out', node.output),
        ),
      ],
    ),
    const SizedBox(height: 14),
    if (node.fork) ...[
      const SectionLabel('Outcomes'),
      const SizedBox(height: 8),
      for (final way in node.ways)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _WayRow(way, outcome: way.outcome),
        ),
    ] else
      for (final way in node.ways) _WayRow(way, title: 'Then'),
  ];
}

/// `IN #/Change { id, path }`; `—` and `none` when the node declares none.
class _TypeCard extends StatelessWidget {
  const _TypeCard(this.title, this.type);

  final String title;
  final TypeCard? type;

  @override
  Widget build(BuildContext context) {
    final type = this.type;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.typeCard,
        border: Border.all(color: AppColors.panelBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            spacing: 8,
            children: [
              SectionLabel(title),
              Flexible(
                child: Text(
                  type?.label ?? '—',
                  style: type == null
                      ? AppText.cardType.copyWith(color: AppColors.textDim)
                      : AppText.cardType,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (type == null || type.fields != null) ...[
            const SizedBox(height: 7),
            Text(
              type == null ? 'none' : type.fields!,
              style: type == null
                  ? AppText.cardFields.copyWith(color: AppColors.textDim)
                  : AppText.cardFields,
            ),
          ],
        ],
      ),
    );
  }
}

/// `THEN → verdict` after a worker; `accepted → publish notify` for an
/// outcome of a fork; `run ends` where it leads nowhere.
class _WayRow extends StatelessWidget {
  const _WayRow(this.way, {this.title, this.outcome});

  final Way way;

  /// `Then`, for a worker.
  final String? title;

  /// The outcome's key, for a fork.
  final String? outcome;

  @override
  Widget build(BuildContext context) => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 10,
    runSpacing: 6,
    children: [
      if (title case final title?) SectionLabel(title),
      if (outcome case final outcome?) Text(outcome, style: AppText.outcomeKey),
      Text(
        '→',
        style: AppText.target.copyWith(fontSize: 16, color: AppColors.textDim),
      ),
      if (way.targets.isEmpty)
        Text('run ends', style: AppText.commandNote)
      else
        for (final target in way.targets)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.tile,
              border: Border.all(color: AppColors.controlBorder),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 7,
              children: [
                NodeIcon(
                  fork: target.fork,
                  size: 13,
                  color: AppColors.textAreaText,
                  strokeWidth: 2,
                ),
                Text(target.name, style: AppText.target),
              ],
            ),
          ),
    ],
  );
}

/// `Started`, `Finished` and how long it took, `Exit code`, `Starts`.
class _Facts extends StatelessWidget {
  const _Facts(this.facts);

  final StepFacts facts;

  static const _labelWidth = 110.0;

  /// A row 34 high, and the line under it but for the [last]; a [value]
  /// too long for its line goes on to the next.
  Widget _row(String label, Widget value, {bool last = false}) => Container(
    constraints: BoxConstraints(minHeight: last ? 34 : 35),
    padding: EdgeInsets.symmetric(horizontal: 12, vertical: last ? 9 : 0),
    decoration: last
        ? null
        : const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
          ),
    child: Row(
      crossAxisAlignment: last
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: _labelWidth,
          child: Text(label, style: AppText.factLabel),
        ),
        Expanded(child: value),
      ],
    ),
  );

  static Widget _none() =>
      Text('—', style: AppText.factValue.copyWith(color: AppColors.textDim));

  @override
  Widget build(BuildContext context) {
    final code = facts.exitCode;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.panelBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _row('Started', Text(facts.started, style: AppText.factValue)),
          _row('Finished', switch (facts.finished) {
            final finished? => Wrap(
              spacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(finished, style: AppText.factValue),
                Text(facts.took!, style: AppText.factNote),
              ],
            ),
            null => _none(),
          }),
          _row(
            'Exit code',
            code == null
                ? _none()
                : Text(
                    '$code',
                    style: AppText.factValue.copyWith(
                      color: code == 0
                          ? AppColors.finishedText
                          : AppColors.dangerText,
                    ),
                  ),
          ),
          _row(
            'Starts',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 4,
              children: [
                for (final start in facts.starts)
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(start.time, style: AppText.factValue),
                      if (start.interrupted)
                        Text(
                          'interrupted — engine stopped',
                          style: AppText.factNote.copyWith(
                            color: AppColors.noteText,
                          ),
                        ),
                    ],
                  ),
              ],
            ),
            last: true,
          ),
        ],
      ),
    );
  }
}
