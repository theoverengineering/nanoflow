import 'dart:convert';

import 'package:flutter/material.dart';

import '../../state/step_files.dart';
import '../../state/texts.dart' show thousands;
import '../../theme.dart';
import 'mono_lines.dart';

/// A document's value as JSON, two-space indented: its first
/// [previewLines] lines until `Show all`.
class DocumentView extends StatefulWidget {
  const DocumentView({
    super.key,
    required this.files,
    required this.sessionId,
    required this.documentId,
  });

  final StepFiles files;
  final String sessionId;
  final String documentId;

  @override
  State<DocumentView> createState() => _DocumentViewState();
}

class _DocumentViewState extends State<DocumentView> {
  static const _json = JsonEncoder.withIndent('  ');

  late final Future<List<String>> _lines = widget.files
      .documentValue(widget.sessionId, widget.documentId)
      .then((value) => _json.convert(value).split('\n'));

  bool _all = false;

  /// The longest line shown, once found.
  String? _widest;

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _lines,
    builder: (context, snapshot) {
      final error = snapshot.error;
      if (error != null) {
        return TabNote(
          'Could not read the document: $error',
          color: AppColors.dangerText,
        );
      }
      final lines = snapshot.data;
      if (lines == null) return const TabNote('');
      final cut = !_all && lines.length > previewLines;
      final shown = cut ? previewLines : lines.length;
      final widest = _widest ??= shownLine(
        widestLine(lines, 0, shown),
        whole: _all,
      );
      return MonoLines(
        count: shown,
        lineAt: (i) => shownLine(lines[i], whole: _all),
        widest: widest,
        cut: cut
            ? (
                text:
                    'Showing the first ${thousands(previewLines)} of '
                    '${thousands(lines.length)} lines',
                showAll: () => setState(() {
                  _all = true;
                  _widest = null;
                }),
              )
            : null,
      );
    },
  );
}

/// What a tab says instead of a text: that there is none, or why it cannot
/// be read.
class TabNote extends StatelessWidget {
  const TabNote(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
    color: AppColors.textArea,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    alignment: Alignment.topLeft,
    child: SelectableText(
      text,
      style: AppText.textAreaNote.copyWith(color: color),
    ),
  );
}
