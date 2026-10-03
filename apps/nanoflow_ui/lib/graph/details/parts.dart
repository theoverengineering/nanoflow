import 'package:flutter/material.dart';

import '../../theme.dart';

// What the columns of the step details window share
// (docs/design/step-details.html).

/// `PLACE IN CODE`, `THIS STEP`, `OUTPUT`.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text.toUpperCase(), style: AppText.sectionLabel);
}

/// The head of the `Output` column: 46 high, a line under it.
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

/// The row under a column's head: what the data is, and its size; a line
/// under it.
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

/// What a column says instead of data: `Not yet: the step is still
/// running`, an error in [color].
class DataNote extends StatelessWidget {
  const DataNote(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: SelectionArea(
      child: Text(text, style: AppText.textAreaNote.copyWith(color: color)),
    ),
  );
}
