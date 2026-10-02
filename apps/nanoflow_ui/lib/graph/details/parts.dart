import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets/clickable.dart';
import '../../widgets/head_cut.dart';
import '../logs/file_footer.dart' show shownPath;

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

/// A button of the window: `Finder`, `Open in editor`, `Reveal in Finder`.
class WindowButton extends StatelessWidget {
  const WindowButton(
    this.label, {
    super.key,
    required this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    this.style,
  });

  final String label;
  final VoidCallback onTap;
  final EdgeInsets padding;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Clickable(
    onTap: onTap,
    child: Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.control,
        border: Border.all(color: AppColors.controlBorder),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: style ?? AppText.fileButton,
        maxLines: 1,
        softWrap: false,
      ),
    ),
  );
}

/// The bar at the bottom of a column: a file's path from the graph's
/// directory [root], cut from the left when too long and whole in a
/// tooltip, then [buttons].
class PathBar extends StatelessWidget {
  const PathBar({
    super.key,
    required this.path,
    required this.root,
    required this.buttons,
    this.height = 36,
    this.padding = 16,
    this.style,
    this.color,
    this.border = AppColors.divider,
    this.pathKey,
  });

  final String path;
  final String root;
  final List<Widget> buttons;
  final double height;
  final double padding;
  final TextStyle? style;
  final Color? color;
  final Color border;
  final Key? pathKey;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    padding: EdgeInsets.symmetric(horizontal: padding),
    decoration: BoxDecoration(
      color: color,
      border: Border(top: BorderSide(color: border)),
    ),
    child: Row(
      spacing: 8,
      children: [
        Expanded(
          child: Tooltip(
            message: path,
            child: HeadCut(
              shownPath(path, root: root),
              key: pathKey,
              style: style ?? AppText.filePath,
            ),
          ),
        ),
        ...buttons,
      ],
    ),
  );
}
