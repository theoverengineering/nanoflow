import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:path/path.dart' as p;

import '../platform/home_path.dart';
import '../state/store_place.dart';
import '../theme.dart';
import '../widgets/clickable.dart';
import '../widgets/dashed_border.dart';
import '../widgets/failure_note.dart';
import 'icons.dart';
import 'recent_graphs.dart';
import 'relative_time.dart';

/// Asks the user for a graph file; null when they cancel.
typedef PickFile = Future<String?> Function();

/// Opens the graph file [path], its sessions read from [store]: by default
/// `runs/` in its project directory.
typedef OpenGraph = void Function(String path, {StorePlace? store});

/// The system open dialog for a graph file, `*.graph.json`: it
/// offers JSON files, since macOS tells files apart by their last extension
/// only.
Future<String?> pickGraphFile() async {
  final file = await openFile(
    acceptedTypeGroups: const [
      XTypeGroup(label: 'nanoflow graph', extensions: ['json']),
    ],
  );
  return file?.path;
}

/// How the start screen names the graph file at [path]: by the name of its
/// graph, without `.graph.json`.
String graphTitle(String path) {
  final name = p.basename(path);
  return name.substring(0, name.length - graphFileSuffix.length);
}

/// Said when the file chosen in the open dialog is not a graph file.
String notAGraphFile(String path) =>
    '${p.basename(path)} is not a graph file: open a *.graph.json file';

/// Said when the file chosen in the open dialog is the graph file of a
/// whole package (`isPackageGraphFile`).
String packageGraphFile(String path) =>
    '${p.basename(path)} has the graphs of a whole package: run '
    'nanoflow_describe to write a file for each graph';

/// Whether a file is still at [path].
bool fileExists(String path) => File(path).existsSync();

/// The screen the app starts on: `Open graph` and the graphs opened before
/// (docs/ui-spec.md «Стартовый экран», docs/design/start.html; spec §9
/// «Открыть»).
///
/// It opens graph files only ([isGraphFile]); another file chosen in the
/// open dialog gets a note instead.
class StartScreen extends StatefulWidget {
  const StartScreen({
    super.key,
    required this.recent,
    required this.onOpen,
    required this.pickFile,
    required this.exists,
    required this.now,
  });

  final RecentGraphs recent;

  /// Opens a graph file: one picked, or one of the list with its store.
  final OpenGraph onOpen;
  final PickFile pickFile;
  final bool Function(String path) exists;
  final DateTime Function() now;

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  late final Timer _clock;

  @override
  void initState() {
    super.initState();
    // Keeps `Opened 5 minutes ago` true while the screen stays open.
    _clock = Timer.periodic(const Duration(minutes: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _clock.cancel();
    super.dispose();
  }

  Future<void> _openFromDialog() async {
    final path = await widget.pickFile();
    if (path == null || !mounted) return;
    if (isGraphFile(path)) {
      widget.onOpen(path);
    } else {
      showFailureNote(
        context,
        isPackageGraphFile(path) ? packageGraphFile(path) : notAGraphFile(path),
      );
    }
  }

  void _openRecent(String path, StorePlace? store) {
    if (widget.exists(path)) {
      widget.onOpen(path, store: store);
    } else {
      // Gone since the list was drawn: show it as missing instead.
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Padding(
      padding: const EdgeInsets.fromLTRB(56, 40, 56, 0),
      child: ListenableBuilder(
        listenable: widget.recent,
        builder: (context, _) {
          final graphs = widget.recent.graphs;
          final now = widget.now();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Title(onOpen: _openFromDialog),
              if (graphs.isNotEmpty) ...[
                const SizedBox(height: 34),
                Row(
                  children: [
                    Text('Recently opened', style: AppText.sectionTitle),
                    const SizedBox(width: 10),
                    Text('${graphs.length}', style: AppText.count),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.only(bottom: 40),
                    itemCount: graphs.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final (:path, :store, :openedAt) = graphs[i];
                      return widget.exists(path)
                          ? _RecentCard(
                              path: path,
                              store: store,
                              opened: openedAgo(openedAt, now),
                              onTap: () => _openRecent(path, store),
                            )
                          : _MissingCard(
                              path: path,
                              store: store,
                              onRemove: () => unawaited(
                                widget.recent.remove(path, store: store),
                              ),
                            );
                    },
                  ),
                ),
              ],
            ],
          );
        },
      ),
    ),
  );
}

/// `Graphs`, the line about what to open, and `Open graph`.
class _Title extends StatelessWidget {
  const _Title({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Graphs', style: AppText.pageTitle),
            const SizedBox(height: 6),
            Text(
              'Open a graph file to watch its sessions live.',
              style: AppText.pageHint,
            ),
          ],
        ),
      ),
      const SizedBox(width: 16),
      Clickable(
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.accent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const FolderIcon(color: AppColors.onAccent),
              const SizedBox(width: 8),
              Text('Open graph', style: AppText.primaryButton),
            ],
          ),
        ),
      ),
    ],
  );
}

/// A graph whose file is there: a click opens it.
class _RecentCard extends StatelessWidget {
  const _RecentCard({
    required this.path,
    required this.store,
    required this.opened,
    required this.onTap,
  });

  final String path;
  final StorePlace? store;
  final String opened;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Clickable.hover(
    onTap: onTap,
    builder: (context, hovered) => Container(
      padding: _cardPadding,
      decoration: BoxDecoration(
        color: hovered ? AppColors.accentSurface : AppColors.card,
        border: Border.all(
          color: hovered ? AppColors.accentBorder : AppColors.cardBorder,
        ),
        borderRadius: BorderRadius.circular(_cardRadius),
      ),
      child: Row(
        children: [
          Container(
            width: _tileSize,
            height: _tileSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.tile,
              border: Border.all(color: AppColors.tileBorder),
              borderRadius: BorderRadius.circular(_tileRadius),
            ),
            child: const GraphIcon(color: AppColors.textSecondary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _NameAndPath(
              name: Text(
                graphTitle(path),
                style: AppText.cardTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              path: path,
              store: store,
              pathStyle: AppText.cardPath,
            ),
          ),
          const SizedBox(width: 14),
          Text(opened, style: AppText.cardMeta),
        ],
      ),
    ),
  );
}

/// A graph whose file is gone: dimmed, struck through, `Missing`; a click
/// does nothing, `Remove` takes it off the list.
class _MissingCard extends StatelessWidget {
  const _MissingCard({
    required this.path,
    required this.store,
    required this.onRemove,
  });

  final String path;
  final StorePlace? store;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => DashedBorder(
    color: AppColors.controlBorder,
    radius: _cardRadius,
    child: Padding(
      // The dashed line takes the 1 px a border would.
      padding: _cardPadding.add(const EdgeInsets.all(1)),
      child: Row(
        children: [
          const DashedBorder(
            color: AppColors.tileBorder,
            radius: _tileRadius,
            child: SizedBox.square(
              dimension: _tileSize,
              child: Center(
                child: GraphIcon(color: AppColors.textDim, linked: false),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _NameAndPath(
              name: Row(
                children: [
                  Flexible(
                    child: Text(
                      graphTitle(path),
                      style: AppText.cardTitle.copyWith(
                        color: AppColors.textFaint,
                        decoration: TextDecoration.lineThrough,
                        decorationColor: AppColors.textFaint,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.dangerSurface,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'Missing',
                      style: AppText.badge.copyWith(
                        color: AppColors.dangerText,
                      ),
                    ),
                  ),
                ],
              ),
              path: path,
              store: store,
              pathStyle: AppText.cardPath.copyWith(color: AppColors.textFaint),
            ),
          ),
          const SizedBox(width: 14),
          Clickable(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.control,
                border: Border.all(color: AppColors.controlBorder),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text('Remove', style: AppText.button),
            ),
          ),
        ],
      ),
    ),
  );
}

/// The graph's name over the full path of its file, `~` for the home
/// directory, and the store it was opened with, if any.
class _NameAndPath extends StatelessWidget {
  const _NameAndPath({
    required this.name,
    required this.path,
    required this.store,
    required this.pathStyle,
  });

  final Widget name;
  final String path;
  final StorePlace? store;
  final TextStyle pathStyle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      name,
      const SizedBox(height: 3),
      Text(
        switch (store) {
          final store? =>
            '${abbreviateHome(path)}  ·  '
                '${store.scheme}:${abbreviateHome(store.path)}',
          null => abbreviateHome(path),
        },
        style: pathStyle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ],
  );
}

const _cardPadding = EdgeInsets.symmetric(horizontal: 16, vertical: 14);
const _cardRadius = 10.0;
// start.html's 40 px tile has its 1 px border outside.
const _tileSize = 42.0;
const _tileRadius = 9.0;
