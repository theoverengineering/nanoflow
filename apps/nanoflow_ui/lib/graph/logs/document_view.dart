import 'dart:convert';

import 'package:flutter/material.dart';

import '../../state/effect_files.dart';
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

  final EffectFiles files;
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

  /// What of the document is shown, once found.
  TextStart? _start;

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
      final start = _start ??= textStart(lines, all: _all);
      return MonoLines(
        count: start.count,
        lineAt: (i) => TextSpan(text: shownLine(lines[i], whole: _all)),
        widest: shownLine(start.widest, whole: _all),
        cut: switch (start.cut) {
          null => null,
          final cut => (
            text: cut,
            showAll: () => setState(() {
              _all = true;
              _start = null;
            }),
          ),
        },
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
