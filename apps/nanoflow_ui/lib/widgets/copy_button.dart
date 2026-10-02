import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';
import 'clickable.dart';
import 'failure_note.dart';
import 'icons.dart';

/// The button that copies a path: two sheets, `Copy path` in its tooltip;
/// `Copied` with a check for a moment after a copy, a note when copying
/// fails. [width] by [height], its icon [iconSize] across.
class CopyButton extends StatefulWidget {
  const CopyButton({
    super.key,
    required this.copy,
    required this.failure,
    this.width = 24,
    this.height = 22,
    this.iconSize = 11,
  });

  final Future<void> Function() copy;

  /// What the note says when copying fails.
  final String failure;

  final double width;
  final double height;
  final double iconSize;

  /// The look of the small buttons by a path: `Finder`, `Editor`, copy.
  static final box = BoxDecoration(
    color: AppColors.control,
    border: Border.all(color: AppColors.controlBorder),
    borderRadius: BorderRadius.circular(6),
  );

  @override
  State<CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<CopyButton> {
  /// How long `Copied` stays.
  static const _copiedTime = Duration(milliseconds: 1500);

  Timer? _copied;

  @override
  void dispose() {
    _copied?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    try {
      await widget.copy();
    } on Exception {
      if (mounted) showFailureNote(context, widget.failure);
      return;
    }
    if (!mounted) return;
    _copied?.cancel();
    setState(() {
      _copied = Timer(_copiedTime, () => setState(() => _copied = null));
    });
  }

  @override
  Widget build(BuildContext context) => _copied != null
      ? Container(
          height: widget.height,
          padding: const EdgeInsets.symmetric(horizontal: 7),
          decoration: CopyButton.box,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 5,
            children: [
              CheckIcon(size: widget.iconSize, color: AppColors.finished),
              Text('Copied', style: AppText.fileButton),
            ],
          ),
        )
      : Tooltip(
          message: 'Copy path',
          child: Clickable(
            onTap: _copy,
            child: Container(
              width: widget.width,
              height: widget.height,
              alignment: Alignment.center,
              decoration: CopyButton.box,
              child: CopyIcon(
                size: widget.iconSize,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        );
}
