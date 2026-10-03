import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../platform/shell.dart';
import '../../state/step_files.dart';
import '../../state/visit_details.dart';
import '../../state/visits.dart' show StartOutcome;
import '../../theme.dart';
import '../../widgets/copy_button.dart';
import '../../widgets/failure_note.dart';
import '../../widgets/path_bar.dart';
import 'parts.dart';

/// The step column of the step details window (docs/ui-spec.md «Окно
/// деталей шага»; spec §9 «Окно шага»): where in the code the step was
/// called, `lib/review.dart:49`, with a button that copies it; and the
/// facts of the step: `Started`, `Finished`, every start and how it ended.
/// The step's directory is at the bottom, with `Reveal in Finder` and a
/// copy button.
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

  /// The key of what the column says of the step, above the directory.
  static const descriptionKey = ValueKey('node description');

  /// The key of the step's directory.
  static const pathKey = ValueKey('step path');

  /// The key of the button that copies the place.
  static const copyPlaceKey = ValueKey('copy place');

  @override
  Widget build(BuildContext context) {
    final facts = details.facts;
    final visit = details.visit;
    final place = details.place;
    final path = visit == null ? null : files.stepPath(visit.stepId);
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.control,
        border: Border(right: BorderSide(color: AppColors.panelBorder)),
        boxShadow: [BoxShadow(color: Color(0x59000000), blurRadius: 30)],
      ),
      // Inside the border, as CSS lays out a box's content.
      child: Padding(
        padding: const EdgeInsets.only(right: 1),
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
                    const SectionLabel('Place in code'),
                    const SizedBox(height: 8),
                    _Place(place: place, shell: shell),
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
}

/// `lib/review.dart:49` in a box, and a button that copies it: the place
/// pasted into an editor's «go to file» opens the line. The editor the app
/// opens files in is given no line, so the app does not open it there.
class _Place extends StatelessWidget {
  const _Place({required this.place, required this.shell});

  final String? place;
  final Shell shell;

  @override
  Widget build(BuildContext context) {
    final place = this.place;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: AppColors.backdrop,
        border: Border.all(color: AppColors.panelBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        spacing: 8,
        children: [
          Expanded(
            child: SelectionArea(
              child: Text(
                place ?? 'Not known: the step recorded no place',
                style: place == null ? AppText.placeNote : AppText.placeBox,
              ),
            ),
          ),
          if (place != null)
            CopyButton(
              key: NodeColumn.copyPlaceKey,
              copy: () => shell.copyToClipboard(place),
              failure: 'Could not copy the place',
              tooltip: 'Copy place',
              width: 28,
              height: 26,
              iconSize: 12,
            ),
        ],
      ),
    );
  }
}

/// `Started`, `Finished` and how long it took, `Starts`.
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

  /// What a start's outcome adds after its time: nothing for one that
  /// finished.
  static Widget? _outcome(StartOutcome outcome) {
    final (text, color) = switch (outcome) {
      StartOutcome.finished => (null, null),
      StartOutcome.running => ('running', AppColors.running),
      StartOutcome.failed => ('failed', AppColors.dangerText),
      // As docs/design/step-details.html has it.
      StartOutcome.interrupted => (
        'interrupted — the process stopped',
        AppColors.noteText,
      ),
    };
    return text == null
        ? null
        : Text(text, style: AppText.factNote.copyWith(color: color));
  }

  @override
  Widget build(BuildContext context) => Container(
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
                    ?_outcome(start.outcome),
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
