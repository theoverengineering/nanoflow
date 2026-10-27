import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../platform/shell.dart';
import '../theme.dart';

/// How long a note about a failure stays.
const _noteTime = Duration(seconds: 3);

/// Says for a while, at the bottom of the screen, that something the user
/// asked for failed: `Could not reveal nanoflow.graph.json in Finder`.
void showFailureNote(BuildContext context, String text) =>
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          text,
          style: AppText.problemText.copyWith(color: AppColors.dangerText),
        ),
        duration: _noteTime,
        behavior: SnackBarBehavior.floating,
        width: 360,
        backgroundColor: AppColors.dangerSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AppColors.dangerBorder),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );

/// Runs [open] on [path] — reveals it in Finder, opens it in an editor — and
/// says [failure] when that fails.
Future<void> openPath(
  BuildContext context,
  Future<bool> Function(String path) open,
  String path,
  String failure,
) async {
  if (await open(path) || !context.mounted) return;
  showFailureNote(context, failure);
}

/// Opens [place], `lib/review.dart:49` from the package root — the
/// directory of [graphFile] —, at its line in the editor
/// ([Shell.openAtLine]), and says `Could not open review.dart:49` when that
/// fails.
Future<void> openPlace(
  BuildContext context,
  Shell shell,
  String graphFile,
  String place,
) async {
  final colon = place.lastIndexOf(':');
  final line = colon < 0 ? null : int.tryParse(place.substring(colon + 1));
  final file = line == null ? place : place.substring(0, colon);
  final path = p.join(p.dirname(graphFile), file);
  if (await shell.openAtLine(path, line ?? 1) || !context.mounted) return;
  showFailureNote(context, 'Could not open ${p.basename(place)}');
}
