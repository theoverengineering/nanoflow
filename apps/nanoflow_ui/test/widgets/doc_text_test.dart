import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_ui/theme.dart';
import 'package:nanoflow_ui/widgets/doc_text.dart';

/// The spans of [span] that say [text], whatever is round them.
Iterable<TextSpan> spansSaying(InlineSpan span, String text) sync* {
  if (span is! TextSpan) return;
  if (span.text == text) yield span;
  for (final child in span.children ?? const <InlineSpan>[]) {
    yield* spansSaying(child, text);
  }
}

Widget app(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('docSpan', () {
    test('puts paragraphs a blank line apart and list items a line apart', () {
      expect(
        docSpan('Does:\n- one\n- two\n\nThen ends.').toPlainText(),
        'Does:\n\n• one\n• two\n\nThen ends.',
      );
    });

    test('shows code in mono and the rest in the doc style', () {
      final span = docSpan('Runs `claude -p` **once**.') as TextSpan;
      expect(span.style, AppText.doc);
      expect(spansSaying(span, 'claude -p').single.style, AppText.docCode);
      expect(
        spansSaying(span, 'once').single.style!.fontWeight,
        FontWeight.w600,
      );
    });
  });

  group('functionDocsSpan', () {
    test('is the doc alone for one function', () {
      expect(
        functionDocsSpan([(title: 'publish()', doc: 'Puts it out.')])!
            .toPlainText(),
        'Puts it out.',
      );
    });

    test('puts each documented function of several under its title', () {
      final span = functionDocsSpan([
        (title: 'MailNotifier.notify()', doc: 'Mails the author.'),
        (title: 'SilentNotifier.notify()', doc: null),
        (title: 'SlackNotifier.notify()', doc: 'Posts to the channel.'),
      ])!;
      expect(
        span.toPlainText(),
        'MailNotifier.notify()\nMails the author.\n\n'
        'SlackNotifier.notify()\nPosts to the channel.',
      );
      expect(
        spansSaying(span, 'MailNotifier.notify()').single.style,
        AppText.docTitle,
      );
    });

    test('is null when no function has a doc', () {
      expect(functionDocsSpan([(title: 'a()', doc: null)]), isNull);
      expect(
        functionDocsSpan([
          (title: 'a()', doc: null),
          (title: 'b()', doc: null),
        ]),
        isNull,
      );
      expect(functionDocsSpan(const []), isNull);
    });
  });

  testWidgets('DocText shows the doc, selectable', (tester) async {
    await tester.pumpWidget(app(const DocText('One.\n\nTwo `x`.')));
    expect(find.text('One.\n\nTwo x.', findRichText: true), findsOneWidget);
    expect(find.byType(SelectionArea), findsOneWidget);
  });

  group('DocTooltip', () {
    testWidgets('is the child alone without a message', (tester) async {
      await tester.pumpWidget(
        app(const DocTooltip(message: null, child: Text('tile'))),
      );
      expect(find.byType(Tooltip), findsNothing);
      expect(find.text('tile'), findsOneWidget);
    });

    testWidgets('shows the doc after the pointer rests on the child', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          DocTooltip(
            message: docSpan('Takes the change.'),
            child: const SizedBox.square(dimension: 80),
          ),
        ),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.byType(SizedBox)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Takes the change.', findRichText: true), findsNothing);
      await tester.pump(DocTooltip.wait);
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        find.text('Takes the change.', findRichText: true),
        findsOneWidget,
      );
    });
  });
}
