import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../platform/home_path.dart';
import '../theme.dart';
import 'clickable.dart';
import 'copy_button.dart';
import 'head_cut.dart';

/// [path] as the app shows a file of the storage: from [root], the graph's
/// directory, when it is in it; else from the home directory, `~`.
String shownPath(String path, {required String root}) => p.isWithin(root, path)
    ? p.relative(path, from: root)
    : abbreviateHome(path);

/// A bar under what shows a file or a directory of the storage: its path
/// from [root], the graph's directory, cut from the left when too long and
/// whole in a tooltip, then [buttons] — `Finder`, `Editor`, copy.
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

  /// At the left and the right.
  final double padding;

  /// The path's; by default [AppText.filePath].
  final TextStyle? style;
  final Color? color;

  /// The line over the bar.
  final Color border;

  /// The key of the shown path.
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

/// A small button by a path: `Finder`, `Editor`, `Open in editor`,
/// `Reveal in Finder`.
class FileButton extends StatelessWidget {
  const FileButton(
    this.label, {
    super.key,
    required this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    this.style,
  });

  final String label;
  final VoidCallback onTap;
  final EdgeInsets padding;

  /// By default [AppText.fileButton].
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Clickable(
    onTap: onTap,
    child: Container(
      padding: padding,
      decoration: CopyButton.box,
      child: Text(
        label,
        style: style ?? AppText.fileButton,
        maxLines: 1,
        softWrap: false,
      ),
    ),
  );
}
