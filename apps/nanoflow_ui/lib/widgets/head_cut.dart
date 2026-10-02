import 'package:flutter/widgets.dart';

/// One line of [text] that, when it does not fit, loses its start to `…`:
/// the end of a path tells more than its start.
class HeadCut extends StatelessWidget {
  const HeadCut(this.text, {super.key, required this.style});

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
