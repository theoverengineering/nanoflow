import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../platform/home_path.dart';
import '../platform/shell.dart';
import '../theme.dart';

/// One graph file's screen (docs/ui-spec.md «Экран графа»). For now only its
/// header: `Graphs` back to the start screen, the file name, its directory.
class GraphScreen extends StatelessWidget {
  const GraphScreen({
    super.key,
    required this.path,
    required this.shell,
    required this.onBack,
  });

  /// The graph file.
  final String path;

  /// How the screen reaches macOS.
  final Shell shell;

  /// Goes back to the start screen.
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: const BoxDecoration(
            color: AppColors.window,
            border: Border(bottom: BorderSide(color: AppColors.divider)),
          ),
          child: Row(
            children: [
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: onBack,
                  child: const Text('Graphs', style: AppText.crumb),
                ),
              ),
              const SizedBox(width: 10),
              const Text('/', style: AppText.crumbSeparator),
              const SizedBox(width: 10),
              Text(p.basename(path), style: AppText.headerTitle),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  abbreviateHome(p.dirname(path)),
                  style: AppText.headerPath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
