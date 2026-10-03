import 'package:flutter/material.dart';

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
