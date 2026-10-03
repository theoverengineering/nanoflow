import 'package:flutter/material.dart';

import '../state/copies.dart';
import '../theme.dart';
import '../widgets/clickable.dart';
import '../widgets/dot.dart';
import '../widgets/icons.dart';

/// The copy switcher in the header of a copies frame (decision 11;
/// docs/design/code-first/copy-switcher.html): `all · 1 ✓ · 2 ● · 3 ●`, the
/// copies numbered in the order they started, each with how it stands, the
/// one shown filled; over a number, what the copy's first step gave
/// (`core:uploaded`), to tell the copies apart without the code.
///
/// More than [chipLimit] copies do not fit as chips: one chip names the copy
/// shown, and opens a list of them with a search and a filter by how they
/// stand.
class CopySwitcher extends StatelessWidget {
  const CopySwitcher({
    super.key,
    required this.copies,
    required this.selected,
    required this.hintOf,
    required this.onSelect,
  });

  final List<Copy> copies;

  /// The copy shown; `null` for all.
  final Copy? selected;

  /// What the first step of [copy] gave; `null` while it is not known.
  final String? Function(Copy copy) hintOf;

  /// Shows the copy of this id; every copy for `null`.
  final ValueChanged<String?> onSelect;

  /// The most copies shown as chips.
  static const chipLimit = 12;

  /// The key of the chip of the copy [number]; `all` for `null`.
  static Key chipKey(int? number) => ValueKey(('copy chip', number));

  /// The key of the chip that opens the list, with more than [chipLimit].
  static const listKey = ValueKey('copy list');

  /// The keys of the list's search and of its filter by [status].
  static const searchKey = ValueKey('copy search');
  static Key filterKey(CopyStatus status) => ValueKey(('copy filter', status));

  /// The key of the copy [number]'s row in the list; `all` for `null`.
  static Key rowKey(int? number) => ValueKey(('copy row', number));

  /// How tall the switcher is.
  static const height = _Chip.height;

  static const _gap = 6.0;

  /// How wide the switcher of [copies], [selected] shown, is drawn: the
  /// frame keeps room for it.
  static double widthOf(List<Copy> copies, Copy? selected) {
    if (copies.length > chipLimit) {
      return _Chip.widthOf(_listText(selected), icon: true) +
          _gap +
          _textWidth(_countText(copies.length), _Chip.textStyle);
    }
    return [
          _Chip.widthOf('all', icon: false),
          for (final copy in copies)
            _Chip.widthOf('${copy.number}', icon: true),
        ].fold(0.0, (sum, w) => sum + w) +
        _gap * copies.length;
  }

  static String _listText(Copy? selected) =>
      selected == null ? 'all' : 'copy ${selected.number}';

  static String _countText(int copies) => '$copies copies';

  @override
  Widget build(BuildContext context) {
    if (copies.length > chipLimit) return _list(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: _gap,
      children: [
        _Chip(
          key: chipKey(null),
          text: 'all',
          selected: selected == null,
          onTap: () => onSelect(null),
        ),
        for (final copy in copies)
          _hinted(
            copy,
            _Chip(
              key: chipKey(copy.number),
              text: '${copy.number}',
              status: copy.status,
              selected: copy.id == selected?.id,
              onTap: () => onSelect(copy.id),
            ),
          ),
      ],
    );
  }

  Widget _hinted(Copy copy, Widget chip) => switch (hintOf(copy)) {
    final hint? => Tooltip(message: hint, child: chip),
    null => chip,
  };

  /// One chip naming the copy shown, which opens the list; how many there
  /// are.
  Widget _list(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    spacing: _gap,
    children: [
      Builder(
        builder: (context) => _Chip(
          key: listKey,
          text: _listText(selected),
          selected: selected != null,
          menu: true,
          onTap: () => _openList(context),
        ),
      ),
      Text(
        _countText(copies.length),
        style: _Chip.textStyle,
        textScaler: TextScaler.noScaling,
      ),
    ],
  );

  Future<void> _openList(BuildContext context) async {
    final box = context.findRenderObject()! as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final at = box.localToGlobal(
      Offset(0, box.size.height + 4),
      ancestor: overlay,
    );
    final chosen = await showMenu<({String? id})>(
      context: context,
      color: AppColors.control,
      constraints: const BoxConstraints.tightFor(width: _CopyList.width),
      position: RelativeRect.fromLTRB(
        at.dx,
        at.dy,
        overlay.size.width - at.dx,
        0,
      ),
      items: [
        PopupMenuItem(
          enabled: false,
          padding: EdgeInsets.zero,
          child: _CopyList(copies: copies, selected: selected, hintOf: hintOf),
        ),
      ],
    );
    if (chosen != null) onSelect(chosen.id);
  }
}

double _textWidth(String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.noScaling,
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

/// A copy's chip: its number and how it stands, or `all`; filled when
/// selected; a chevron when it opens a [menu].
class _Chip extends StatelessWidget {
  const _Chip({
    super.key,
    required this.text,
    required this.selected,
    required this.onTap,
    this.status,
    this.menu = false,
  });

  final String text;
  final bool selected;
  final VoidCallback onTap;
  final CopyStatus? status;
  final bool menu;

  static const height = 20.0;
  static const _padding = 9.0;
  static const _icon = 8.0;
  static const _iconGap = 4.0;

  static const textStyle = TextStyle(
    inherit: false,
    fontFamily: AppText.sans,
    fontSize: 11,
    height: 1.3,
    leadingDistribution: TextLeadingDistribution.even,
    color: AppColors.textMuted,
  );

  /// How wide the chip of [text] is, with a sign or chevron after it when
  /// [icon]; a hair more, so that it is not cut.
  static double widthOf(String text, {required bool icon}) =>
      _textWidth(text, textStyle.copyWith(fontWeight: FontWeight.w600)) +
      2 * _padding +
      (icon ? _iconGap + _icon : 0) +
      2 +
      1;

  @override
  Widget build(BuildContext context) => Clickable(
    onTap: onTap,
    child: Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: _padding),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF3A3550) : null,
        border: Border.all(
          color: selected ? const Color(0xFF9B87F5) : const Color(0xFF5A5A62),
        ),
        borderRadius: const BorderRadius.all(Radius.circular(height / 2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: _iconGap,
        children: [
          Text(
            text,
            style: selected
                ? textStyle.copyWith(
                    color: AppColors.onAccent,
                    fontWeight: FontWeight.w600,
                  )
                : textStyle,
            textScaler: TextScaler.noScaling,
          ),
          if (status case final status?) _StatusSign(status),
          if (menu)
            const ChevronIcon(
              size: _icon,
              down: true,
              color: AppColors.textMuted,
            ),
        ],
      ),
    ),
  );
}

/// How a copy stands: a check done, a dot running, a cross failed.
class _StatusSign extends StatelessWidget {
  const _StatusSign(this.status);

  final CopyStatus status;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: _Chip._icon,
    child: Center(
      child: switch (status) {
        CopyStatus.finished => const CheckIcon(
          size: _Chip._icon,
          color: AppColors.finished,
          strokeWidth: 2.2,
        ),
        CopyStatus.running => const Dot(AppColors.running),
        CopyStatus.failed => const CloseIcon(size: 7, color: AppColors.failed),
      },
    ),
  );
}

/// The copies as a list: a search through their numbers and hints, a
/// filter by how they stand, and `all` first; a click on a row shows it.
class _CopyList extends StatefulWidget {
  const _CopyList({
    required this.copies,
    required this.selected,
    required this.hintOf,
  });

  final List<Copy> copies;
  final Copy? selected;
  final String? Function(Copy copy) hintOf;

  static const width = 300.0;
  static const _rows = 280.0;

  @override
  State<_CopyList> createState() => _CopyListState();
}

class _CopyListState extends State<_CopyList> {
  String _search = '';
  CopyStatus? _filter;

  bool _shown(Copy copy) {
    if (_filter != null && copy.status != _filter) return false;
    final search = _search.trim().toLowerCase();
    if (search.isEmpty) return true;
    return '${copy.number}'.startsWith(search) ||
        (widget.hintOf(copy)?.toLowerCase().contains(search) ?? false);
  }

  void _choose(String? id) => Navigator.of(context).pop((id: id));

  @override
  Widget build(BuildContext context) {
    final shown = widget.copies.where(_shown).toList();
    return SizedBox(
      width: _CopyList.width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
            child: TextField(
              key: CopySwitcher.searchKey,
              autofocus: true,
              style: AppText.button.copyWith(color: AppColors.textPrimary),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search copies',
                hintStyle: AppText.button.copyWith(color: AppColors.textDim),
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
              onChanged: (text) => setState(() => _search = text),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
            child: Row(
              spacing: 6,
              children: [
                for (final (status, label) in const [
                  (CopyStatus.running, 'running'),
                  (CopyStatus.failed, 'failed'),
                  (CopyStatus.finished, 'done'),
                ])
                  _Chip(
                    key: CopySwitcher.filterKey(status),
                    text: label,
                    selected: _filter == status,
                    onTap: () => setState(
                      () => _filter = _filter == status ? null : status,
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.divider),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: _CopyList._rows),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              children: [
                _row(null, 'all', null, null),
                for (final copy in shown)
                  _row(
                    copy,
                    'copy ${copy.number}',
                    copy.status,
                    widget.hintOf(copy),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(Copy? copy, String text, CopyStatus? status, String? hint) {
    final selected = copy?.id == widget.selected?.id;
    return Clickable(
      key: CopySwitcher.rowKey(copy?.number),
      onTap: () => _choose(copy?.id),
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        // Filled, so that a click anywhere on the row is the row's.
        color: selected ? AppColors.accentSurface : Colors.transparent,
        child: Row(
          spacing: 8,
          children: [
            Text(
              text,
              style: AppText.button.copyWith(
                color: selected ? AppColors.accentText : AppColors.textPrimary,
              ),
            ),
            if (status case final status?) _StatusSign(status),
            if (hint case final hint?)
              Expanded(
                child: Text(
                  hint,
                  style: AppText.button.copyWith(color: AppColors.textFaint),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
