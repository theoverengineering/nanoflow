import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../state/json_data.dart';
import '../../state/step_files.dart';
import '../../theme.dart';
import '../../widgets/clickable.dart';
import '../../widgets/icons.dart';
import '../logs/mono_lines.dart';
import 'parts.dart';

/// How the data of `Output` is shown (docs/ui-spec.md «Окно
/// деталей шага»: «Данные»).
enum DataMode { schema, json }

/// `Schema` | `JSON`: the view shown is filled.
class ModeToggle extends StatelessWidget {
  const ModeToggle({super.key, required this.mode, required this.onChanged});

  final DataMode mode;
  final ValueChanged<DataMode> onChanged;

  static Key keyOf(DataMode mode) => ValueKey(('data mode', mode));

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(2),
    decoration: BoxDecoration(
      color: AppColors.card,
      border: Border.all(color: AppColors.panelBorder),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (which, label) in const [
          (DataMode.schema, 'Schema'),
          (DataMode.json, 'JSON'),
        ])
          Clickable(
            key: keyOf(which),
            onTap: () => onChanged(which),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: which == mode
                  ? BoxDecoration(
                      color: AppColors.controlBorder,
                      borderRadius: BorderRadius.circular(5),
                    )
                  : null,
              child: Text(
                label,
                style: which == mode
                    ? AppText.toggle.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      )
                    : AppText.toggle,
              ),
            ),
          ),
      ],
    ),
  );
}

/// A document's value as read, and its size, measured once when first asked
/// for: the window is built again every second.
final class LoadedDocument {
  LoadedDocument(this.value);

  final Object? value;

  /// How many bytes the value's JSON takes: `214 B`.
  late final String size = sizeText(byteSize(value));
}

/// The value of a document, read once: [builder] shows it; until it is read,
/// nothing; a note when it cannot be.
class DocumentData extends StatefulWidget {
  const DocumentData({
    super.key,
    required this.files,
    required this.sessionId,
    required this.documentId,
    required this.builder,
  });

  final StepFiles files;
  final String sessionId;
  final String documentId;
  final Widget Function(BuildContext context, LoadedDocument document) builder;

  @override
  State<DocumentData> createState() => _DocumentDataState();
}

class _DocumentDataState extends State<DocumentData> {
  late final Future<LoadedDocument> _document = widget.files
      .documentValue(widget.sessionId, widget.documentId)
      .then(LoadedDocument.new);

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _document,
    builder: (context, snapshot) {
      if (snapshot.error case final error?) {
        return DataNote(
          'Could not read the document: $error',
          color: AppColors.dangerText,
        );
      }
      final document = snapshot.data;
      return document == null
          ? const SizedBox.shrink()
          : widget.builder(context, document);
    },
  );
}

/// [value] in [mode].
class DataView extends StatelessWidget {
  const DataView({super.key, required this.value, required this.mode});

  final Object? value;
  final DataMode mode;

  @override
  Widget build(BuildContext context) => switch (mode) {
    DataMode.schema => SchemaView(value: value),
    DataMode.json => JsonView(value: value),
  };
}

/// The color of a value of [type] in data.
Color _valueColor(String type) => switch (type) {
  'string' => AppColors.noteText,
  'number' => AppColors.jsonNumber,
  _ => AppColors.jsonLiteral,
};

/// `Schema`: a row for each field — its name, its JSON type, its value —
/// nested objects and arrays under their row, which opens and closes them;
/// those deeper than the first level start closed. Rows are built as they
/// come into view.
class SchemaView extends StatefulWidget {
  const SchemaView({super.key, required this.value});

  final Object? value;

  /// The key of the row of the field at [path] (a JSON Pointer).
  static Key rowKey(String path) => ValueKey(('data row', path));

  @override
  State<SchemaView> createState() => _SchemaViewState();
}

class _SchemaViewState extends State<SchemaView> {
  final Set<String> _toggled = {};

  /// The rows shown, whether any of them opens, and the width of their
  /// names in [_scaler]: measured once per rows, not on every build — the
  /// window is built again every second.
  late List<SchemaRow> _rows;
  late bool _chevrons;
  double? _nameWidth;
  TextScaler? _scaler;

  static const _rowHeight = 30.0;
  static const _gap = 4.0;
  static const _indent = 16.0;
  static const _leastName = 64.0;
  static const _mostName = 200.0;

  @override
  void initState() {
    super.initState();
    _show(schemaRows(widget.value));
  }

  @override
  void didUpdateWidget(SchemaView old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _toggled.clear();
      _show(schemaRows(widget.value));
    }
  }

  void _toggle(String path) => setState(() {
    if (!_toggled.remove(path)) _toggled.add(path);
    _show(schemaRows(widget.value, toggled: _toggled));
  });

  void _show(List<SchemaRow> rows) {
    _rows = rows;
    _chevrons = rows.any((row) => row.container);
    _nameWidth = null;
  }

  /// The width of the names: the longest one's, within limits.
  double _measure(TextScaler scaler) {
    var longest = '';
    for (final row in _rows) {
      if (row.name.length > longest.length) longest = row.name;
    }
    final painter = TextPainter(
      text: TextSpan(text: longest, style: AppText.dataName),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width.clamp(_leastName, _mostName);
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    if (rows.isEmpty) {
      return DataNote(widget.value is List ? 'An empty array' : 'No fields');
    }
    final scaler = MediaQuery.textScalerOf(context);
    if (scaler != _scaler) _nameWidth = null;
    _scaler = scaler;
    final nameWidth = _nameWidth ??= _measure(scaler);
    final chevrons = _chevrons;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemExtent: _rowHeight + _gap,
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final row = rows[i];
        final content = Container(
          key: SchemaView.rowKey(row.path),
          height: _rowHeight,
          margin: EdgeInsets.only(left: row.depth * _indent, bottom: _gap),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            spacing: 10,
            children: [
              if (chevrons)
                SizedBox(
                  width: 10,
                  child: row.container
                      ? Transform.rotate(
                          angle: row.open ? math.pi / 2 : 0,
                          child: const ChevronIcon(
                            size: 10,
                            color: AppColors.textMuted,
                            right: true,
                          ),
                        )
                      : null,
                ),
              SizedBox(
                width: nameWidth,
                child: Text(
                  row.name,
                  style: AppText.dataName,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.selectedTab,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(row.type, style: AppText.dataType),
              ),
              Expanded(
                child: Text(
                  row.text,
                  style: row.container
                      ? AppText.factNote
                      : AppText.dataValue.copyWith(
                          color: _valueColor(row.type),
                        ),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
        return row.container
            ? Clickable(onTap: () => _toggle(row.path), child: content)
            : content;
      },
    );
  }
}

/// `JSON`: the data indented by two spaces, keys, strings, numbers, `true`,
/// `false` and `null` in their colors; large data, its first
/// [previewLines] lines until `Show all`.
class JsonView extends StatefulWidget {
  const JsonView({super.key, required this.value});

  final Object? value;

  @override
  State<JsonView> createState() => _JsonViewState();
}

class _JsonViewState extends State<JsonView> {
  late List<String> _lines = jsonLines(widget.value);
  bool _all = false;

  /// What of the data is shown, once found.
  TextStart? _start;

  @override
  void didUpdateWidget(JsonView old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _lines = jsonLines(widget.value);
      _all = false;
      _start = null;
    }
  }

  static Color _colorOf(JsonPart part) => switch (part) {
    JsonPart.key => AppColors.link,
    JsonPart.string => AppColors.noteText,
    JsonPart.number => AppColors.jsonNumber,
    JsonPart.literal => AppColors.jsonLiteral,
    JsonPart.punctuation => AppColors.textSubtle,
    JsonPart.space => AppColors.textAreaText,
  };

  static InlineSpan _spanOf(String line) => TextSpan(
    children: [
      for (final token in jsonTokens(line))
        TextSpan(
          text: token.text,
          style: TextStyle(color: _colorOf(token.part)),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final lines = _lines;
    final start = _start ??= textStart(lines, all: _all);
    return MonoLines(
      count: start.count,
      lineAt: (i) => shownLine(lines[i], whole: _all),
      widest: shownLine(start.widest, whole: _all),
      style: AppText.jsonLine,
      spanOf: _spanOf,
      background: AppColors.backdrop,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
  }
}
