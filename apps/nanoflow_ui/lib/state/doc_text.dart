/// The doc comment of a function or an effect, as the app shows it
/// (docs/superpowers/specs/2026-10-10-node-docs-design.md, §4.1): a small
/// part of Markdown — paragraphs, list items, fenced code; `code`, Dart
/// references `[name]`, links, **strong** and *emphasis* — and the rest as
/// written. Pure.
library;

/// How a run of a doc's text looks.
enum DocStyle { plain, code, strong, emphasis }

/// A run of a doc's text in one style.
typedef DocRun = ({String text, DocStyle style});

/// A block of a doc: a paragraph, an item of a list, or a fenced code block.
final class DocBlock {
  const DocBlock(this.runs, {this.marker, this.isCode = false});

  final List<DocRun> runs;

  /// What a list item starts with: `•`, or its number as written (`1.`);
  /// `null` for a paragraph or code.
  final String? marker;

  /// Whether the block is fenced code, its lines as they are.
  final bool isCode;

  @override
  bool operator ==(Object other) =>
      other is DocBlock &&
      other.marker == marker &&
      other.isCode == isCode &&
      other.runs.length == runs.length &&
      [for (var i = 0; i < runs.length; i++) other.runs[i] == runs[i]]
          .every((same) => same);

  @override
  int get hashCode => Object.hash(marker, isCode, Object.hashAll(runs));

  @override
  String toString() => 'DocBlock($runs, marker: $marker, isCode: $isCode)';
}

final _item = RegExp(r'^\s*([-*+]|\d+[.)])\s+(.*)$');
final _fence = RegExp(r'^\s*```');

/// The blocks of [doc]: lines of a paragraph or of a list item run on with a
/// space; a blank line ends them, a list item starts a block of its own;
/// fenced code keeps its lines.
List<DocBlock> parseDoc(String doc) {
  final blocks = <DocBlock>[];
  // The paragraph or item being read: its marker and its lines.
  String? marker;
  final lines = <String>[];
  void end() {
    if (lines.isNotEmpty) {
      blocks.add(DocBlock(_runs(lines.join(' ')), marker: marker));
    }
    lines.clear();
    marker = null;
  }

  final all = doc.split('\n');
  for (var i = 0; i < all.length; i++) {
    final line = all[i];
    if (_fence.hasMatch(line)) {
      end();
      final code = <String>[];
      while (++i < all.length && !_fence.hasMatch(all[i])) {
        code.add(all[i]);
      }
      blocks.add(
        DocBlock([(text: code.join('\n'), style: DocStyle.code)], isCode: true),
      );
    } else if (line.trim().isEmpty) {
      end();
    } else if (_item.firstMatch(line) case final item?) {
      end();
      final sign = item[1]!;
      marker = const {'-', '*', '+'}.contains(sign) ? '•' : sign;
      lines.add(item[2]!.trim());
    } else {
      lines.add(line.trim());
    }
  }
  end();
  return blocks;
}

/// The runs of [text], one line: `code`, `[reference]` as code, a link as
/// its text, `**strong**`, `*emphasis*`; a mark without its pair is text.
List<DocRun> _runs(String text) {
  final runs = <DocRun>[];
  final plain = StringBuffer();
  void add(String text, DocStyle style) {
    if (style == DocStyle.plain) {
      plain.write(text);
      return;
    }
    if (plain.isNotEmpty) {
      runs.add((text: plain.toString(), style: DocStyle.plain));
      plain.clear();
    }
    runs.add((text: text, style: style));
  }

  var i = 0;
  while (i < text.length) {
    final rest = text.substring(i);
    if (_mark(rest) case (final shown, final style, final length)) {
      add(shown, style);
      i += length;
    } else {
      add(text[i], DocStyle.plain);
      i++;
    }
  }
  if (plain.isNotEmpty) {
    runs.add((text: plain.toString(), style: DocStyle.plain));
  }
  return runs;
}

final _code = RegExp(r'^`([^`]+)`');
final _link = RegExp(r'^\[([^\]]+)\]\([^)\s]*\)');
final _reference = RegExp(r'^\[([^\]\s][^\]]*)\]');
final _strong = RegExp(r'^\*\*(\S(?:.*?\S)?)\*\*');
final _emphasis = RegExp(r'^\*(\S(?:[^*]*?\S)?)\*');

/// The mark [text] starts with: what it shows, how, and how long it is;
/// `null` when [text] starts with none.
(String, DocStyle, int)? _mark(String text) {
  for (final (pattern, style) in [
    (_code, DocStyle.code),
    (_link, DocStyle.plain),
    (_reference, DocStyle.code),
    (_strong, DocStyle.strong),
    (_emphasis, DocStyle.emphasis),
  ]) {
    if (pattern.firstMatch(text) case final match?) {
      return (match[1]!, style, match[0]!.length);
    }
  }
  return null;
}
