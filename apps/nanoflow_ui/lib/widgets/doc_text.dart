import 'package:flutter/material.dart';

import '../state/doc_text.dart';
import '../theme.dart';

/// [doc], a doc comment, as text (docs/superpowers/specs/2026-10-10-node-docs-design.md,
/// §4.1): paragraphs a blank line apart, list items a line apart with their
/// marker, code and Dart references in mono, strong and emphasis as such.
InlineSpan docSpan(String doc) {
  final blocks = parseDoc(doc);
  return TextSpan(
    style: AppText.doc,
    children: [
      for (final (i, block) in blocks.indexed) ...[
        if (i > 0)
          TextSpan(
            text: block.marker != null && blocks[i - 1].marker != null
                ? '\n'
                : '\n\n',
          ),
        if (block.marker case final marker?) TextSpan(text: '$marker '),
        for (final run in block.runs)
          TextSpan(text: run.text, style: _styleOf(run.style)),
      ],
    ],
  );
}

TextStyle? _styleOf(DocStyle style) => switch (style) {
  DocStyle.plain => null,
  DocStyle.code => AppText.docCode,
  DocStyle.strong => const TextStyle(fontWeight: FontWeight.w600),
  DocStyle.emphasis => const TextStyle(fontStyle: FontStyle.italic),
};

/// The docs of the functions a call goes to: the doc alone for one
/// function; for several, each that has one under its title
/// (`MailNotifier.notify()`), a blank line between them. `null` when none
/// has a doc.
InlineSpan? functionDocsSpan(List<({String title, String? doc})> functions) {
  final documented = [
    for (final function in functions)
      if (function.doc case final doc?) (title: function.title, doc: doc),
  ];
  if (documented.isEmpty) return null;
  if (functions.length == 1) return docSpan(documented.single.doc);
  return TextSpan(
    style: AppText.doc,
    children: [
      for (final (i, function) in documented.indexed) ...[
        if (i > 0) const TextSpan(text: '\n\n'),
        TextSpan(text: function.title, style: AppText.docTitle),
        const TextSpan(text: '\n'),
        docSpan(function.doc),
      ],
    ],
  );
}

/// [doc] in the effect details window: selectable.
class DocText extends StatelessWidget {
  const DocText(this.doc, {super.key});

  final String doc;

  @override
  Widget build(BuildContext context) =>
      SelectionArea(child: Text.rich(docSpan(doc)));
}

/// [child] with [message], a doc, in a tooltip once the pointer has rested
/// on it for [wait]: no wider than 420 px, in the colors of a card, [gap]
/// under the child as it is on the screen — a tile on a zoomed canvas
/// included —, or over it where there is no room below. The child alone
/// without a message.
class DocTooltip extends StatefulWidget {
  const DocTooltip({super.key, required this.message, required this.child});

  /// How long the pointer rests before the doc shows: moving over the graph
  /// does not open one tooltip after another.
  static const wait = Duration(milliseconds: 500);

  /// Between the child and the tooltip.
  static const gap = 6.0;

  final InlineSpan? message;
  final Widget child;

  @override
  State<DocTooltip> createState() => _DocTooltipState();
}

class _DocTooltipState extends State<DocTooltip> {
  final _child = GlobalKey();

  /// Half the height of the child on the screen when the pointer last came
  /// over it — before the tooltip shows; `null` until then. Measured then,
  /// as a tooltip is placed during layout, when nothing else may be.
  double? _halfHeight;

  void _measure(PointerEvent _) {
    final box = _child.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final rect = MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
    _halfHeight = rect.height / 2;
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    if (message == null) return widget.child;
    return Tooltip(
      richMessage: message,
      waitDuration: DocTooltip.wait,
      // Clicks go through to what is under it.
      ignorePointer: true,
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      textStyle: AppText.doc,
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.cardBorder),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [BoxShadow(color: Color(0x59000000), blurRadius: 20)],
      ),
      positionDelegate: (place) => positionDependentBox(
        size: place.overlaySize,
        childSize: place.tooltipSize,
        target: place.target,
        verticalOffset:
            (_halfHeight ?? place.targetSize.height / 2) + DocTooltip.gap,
        preferBelow: true,
      ),
      child: MouseRegion(
        key: _child,
        hitTestBehavior: HitTestBehavior.deferToChild,
        onEnter: _measure,
        onHover: _measure,
        child: widget.child,
      ),
    );
  }
}
