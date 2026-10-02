import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../platform/home_path.dart';
import '../../platform/shell.dart';
import '../../theme.dart';
import '../../widgets/clickable.dart';
import '../../widgets/failure_note.dart';

/// The file of the open tab, under the step's details (docs/ui-spec.md
/// «Logs»: «С файловым хранилищем»): its path from the graph's directory,
/// cut from the left when too long and whole in a tooltip; `Finder` shows
/// it, `Editor` opens it, and a button copies its path. When Finder or the
/// editor fails, a note says so.
class FileFooter extends StatelessWidget {
  const FileFooter({
    super.key,
    required this.path,
    required this.root,
    required this.shell,
  });

  /// The file.
  final String path;

  /// The directory the shown path starts from: the graph's.
  final String root;

  final Shell shell;

  /// The key of the shown path.
  static const pathKey = ValueKey('file path');

  String get _shown => p.isWithin(root, path)
      ? p.relative(path, from: root)
      : abbreviateHome(path);

  Future<void> _open(
    BuildContext context,
    Future<bool> Function(String path) open,
    String failure,
  ) async {
    if (await open(path) || !context.mounted) return;
    showFailureNote(context, failure);
  }

  @override
  Widget build(BuildContext context) {
    final name = p.basename(path);
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        spacing: 8,
        children: [
          Expanded(
            child: Tooltip(
              message: path,
              child: _HeadCut(_shown, key: pathKey, style: AppText.filePath),
            ),
          ),
          _FileButton(
            'Finder',
            onTap: () => _open(
              context,
              shell.revealInFinder,
              'Could not reveal $name in Finder',
            ),
          ),
          _FileButton(
            'Editor',
            onTap: () => _open(
              context,
              shell.openInEditor,
              'Could not open $name in an editor',
            ),
          ),
          Tooltip(
            message: 'Copy path',
            child: Clickable(
              onTap: () => shell.copyToClipboard(path),
              child: Container(
                width: 24,
                height: 22,
                alignment: Alignment.center,
                decoration: _buttonBox,
                child: CustomPaint(
                  size: const Size.square(11),
                  painter: _CopyIconPainter(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final _buttonBox = BoxDecoration(
  color: AppColors.control,
  border: Border.all(color: AppColors.controlBorder),
  borderRadius: BorderRadius.circular(6),
);

/// One line of [text] that, when it does not fit, loses its start to `…`:
/// the end of a path tells more than its start.
class _HeadCut extends StatelessWidget {
  const _HeadCut(this.text, {super.key, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scaler = MediaQuery.textScalerOf(context);
      final painter = TextPainter(
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      );
      bool fits(String line) {
        painter
          ..text = TextSpan(text: line, style: style)
          ..layout();
        return painter.width <= constraints.maxWidth;
      }

      var shown = text;
      if (!fits(text)) {
        // The most characters of the end that fit after `…`.
        var low = 0;
        var high = text.length;
        while (low < high) {
          final mid = (low + high + 1) ~/ 2;
          if (fits('…${text.substring(text.length - mid)}')) {
            low = mid;
          } else {
            high = mid - 1;
          }
        }
        shown = '…${text.substring(text.length - low)}';
      }
      painter.dispose();
      return Text(shown, style: style, maxLines: 1, softWrap: false);
    },
  );
}

/// `Finder`, `Editor`.
class _FileButton extends StatelessWidget {
  const _FileButton(this.label, {required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Clickable(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: _buttonBox,
      child: Text(label, style: AppText.fileButton),
    ),
  );
}

/// Two sheets, one over the other: the mockup's SVG, 16 units.
class _CopyIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 16);
    final stroke = Paint()
      ..color = AppColors.textSecondary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(5.4, 5.4, 8.2, 8.2),
          const Radius.circular(1.6),
        ),
        stroke,
      )
      ..drawPath(
        Path()
          ..moveTo(10.6, 5.4)
          ..lineTo(10.6, 3.8)
          ..arcToPoint(
            const Offset(9.2, 2.4),
            radius: const Radius.circular(1.4),
            clockwise: false,
          )
          ..lineTo(3.8, 2.4)
          ..arcToPoint(
            const Offset(2.4, 3.8),
            radius: const Radius.circular(1.4),
            clockwise: false,
          )
          ..lineTo(2.4, 9.2)
          ..arcToPoint(
            const Offset(3.8, 10.6),
            radius: const Radius.circular(1.4),
            clockwise: false,
          )
          ..lineTo(5.4, 10.6),
        stroke,
      );
  }

  @override
  bool shouldRepaint(_CopyIconPainter old) => false;
}
