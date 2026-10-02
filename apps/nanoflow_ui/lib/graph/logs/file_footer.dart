import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../platform/shell.dart';
import '../../widgets/copy_button.dart';
import '../../widgets/failure_note.dart';
import '../../widgets/path_bar.dart';

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
    return PathBar(
      path: path,
      root: root,
      height: 30,
      pathKey: pathKey,
      buttons: [
        FileButton(
          'Finder',
          onTap: () => openPath(
            context,
            shell.revealInFinder,
            path,
            'Could not reveal $name in Finder',
          ),
        ),
        FileButton(
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
    );
  }
}
