import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../platform/home_path.dart';
import '../../platform/shell.dart';
import '../../theme.dart';
import '../../widgets/clickable.dart';
import '../../widgets/copy_button.dart';
import '../../widgets/failure_note.dart';
import '../../widgets/head_cut.dart';

/// [path] as the app shows a file of the storage: from [root], the graph's
/// directory, when it is in it; else from the home directory, `~`.
String shownPath(String path, {required String root}) => p.isWithin(root, path)
    ? p.relative(path, from: root)
    : abbreviateHome(path);

/// The file of the open tab, under the step's details (docs/ui-spec.md
/// «Logs»: «С файловым хранилищем»): its path from the graph's directory,
/// cut from the left when too long and whole in a tooltip; `Finder` shows
/// it, `Editor` opens it, and a button copies its path and says `Copied` for
/// a moment. When Finder, the editor or the clipboard fails, a note says so.
class FileFooter extends StatelessWidget {
  const FileFooter({
    super.key,
    required this.path,
    required this.root,
    required this.shell,
  });

  /// The file.
  final String path;

  /// The directory the shown path starts from: the graph's.
  final String root;

  final Shell shell;

  /// The key of the shown path.
  static const pathKey = ValueKey('file path');

  @override
  Widget build(BuildContext context) {
    final name = p.basename(path);
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.divider)),
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
                style: AppText.filePath,
              ),
            ),
          ),
          _FileButton(
            'Finder',
            onTap: () => openPath(
              context,
              shell.revealInFinder,
              path,
              'Could not reveal $name in Finder',
            ),
          ),
          _FileButton(
            'Editor',
            onTap: () => openPath(
              context,
              shell.openInEditor,
              path,
              'Could not open $name in an editor',
            ),
          ),
          CopyButton(
            copy: () => shell.copyToClipboard(path),
            failure: 'Could not copy the path of $name',
          ),
        ],
      ),
    );
  }
}

/// `Finder`, `Editor`.
class _FileButton extends StatelessWidget {
  const _FileButton(this.label, {required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Clickable(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: CopyButton.box,
      child: Text(label, style: AppText.fileButton),
    ),
  );
}
