import 'package:flutter/material.dart';

import '../../theme.dart';

// What the columns of the step details window share
// (docs/design/step-details.html).

/// `INPUT`, `COMMAND`, `THIS STEP`.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text.toUpperCase(), style: AppText.sectionLabel);
}

/// The head of the `Input` and `Output` columns: 46 high, a line under it.
class ColumnHead extends StatelessWidget {
  const ColumnHead({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    height: 46,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.divider)),
    ),
    child: Row(spacing: 10, children: children),
  );
}

/// The row under a column's head: where the data came from, or what it
/// passes; a line under it.
class DataRowBar extends StatelessWidget {
  const DataRowBar({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.divider)),
    ),
    child: Row(spacing: 7, children: children),
  );
}

/// `#/Change`: a type in a pill.
class TypePill extends StatelessWidget {
  const TypePill(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
    decoration: BoxDecoration(
      color: AppColors.accentSurface,
      border: Border.all(color: AppColors.accentBorder),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(label, style: AppText.typePill, maxLines: 1),
  );
}

/// What a column says instead of data: `— This node declares no in…`,
/// `Not yet: the step is still running`, an error in [color].
class DataNote extends StatelessWidget {
  const DataNote(this.text, {super.key, this.dash = false, this.color});

  final String text;

  /// Whether a `—` comes first: the node declares no such data.
  final bool dash;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        if (dash) Text('—', style: AppText.textAreaNote),
        Expanded(
          child: SelectionArea(
            child: Text(
              text,
              style: AppText.textAreaNote.copyWith(color: color),
            ),
          ),
        ),
      ],
    ),
  );
}
