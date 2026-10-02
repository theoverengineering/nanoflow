import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_ui/graph/details/data_view.dart';
import 'package:nanoflow_ui/graph/logs/mono_lines.dart';
import 'package:nanoflow_ui/theme.dart';

import '../../support/golden.dart';
import '../logs/support.dart';

void main() {
  Future<void> pumpData(WidgetTester tester, Widget view) =>
      pumpScreen(tester, Scaffold(body: SizedBox(width: 420, child: view)));

  group('Schema', () {
    testWidgets('lists fields with their type and value, nested ones under '
        'their parent', (tester) async {
      await pumpData(
        tester,
        const SchemaView(
          value: {
            'change': {'id': 'c4f1a9', 'path': 'src/engine/step.ts'},
            'findings': ['one', 'two'],
            'deep': {
              'inner': {'x': 1},
            },
          },
        ),
      );

      expect(
        textIn(tester, find.byType(SchemaView)),
        'change object 2 fields id string c4f1a9 path string '
        'src/engine/step.ts findings array 2 items 0 string one 1 string two '
        'deep object 1 field inner object 1 field',
      );
    });

    testWidgets('opens and closes an object or an array on a click', (
      tester,
    ) async {
      await pumpData(
        tester,
        const SchemaView(
          value: {
            'change': {'id': 'c4f1a9'},
            'deep': {
              'inner': {'x': 1},
            },
          },
        ),
      );

      await tester.tap(find.byKey(SchemaView.rowKey('/change')));
      await tester.tap(find.byKey(SchemaView.rowKey('/deep/inner')));
      await tester.pump();

      expect(
        textIn(tester, find.byType(SchemaView)),
        'change object 1 field deep object 1 field inner object 1 field '
        'x number 1',
      );
    });

    testWidgets('colors values by their type', (tester) async {
      await pumpData(
        tester,
        const SchemaView(
          value: {
            's': 'x',
            'n': 1,
            'b': true,
            'o': {'k': 2, 'l': 3},
          },
        ),
      );
      Color? colorOf(String text) =>
          tester.widget<Text>(find.text(text)).style?.color;
      expect(colorOf('x'), AppColors.noteText);
      expect(colorOf('1'), AppColors.jsonNumber);
      expect(colorOf('true'), AppColors.jsonLiteral);
      expect(colorOf('2 fields'), AppColors.textSubtle);
    });
  });

  group('JSON', () {
    testWidgets('is the data indented, its parts in their colors', (
      tester,
    ) async {
      await pumpData(
        tester,
        const JsonView(
          value: {
            'id': 'c4f1a9',
            'n': [1, true, null],
          },
        ),
      );

      expect(
        textIn(tester, find.byType(JsonView)),
        '{ "id": "c4f1a9", "n": [ 1, true, null ] }',
      );
      final line = tester
          .widgetList<RichText>(
            find.descendant(
              of: find.byType(JsonView),
              matching: find.byType(RichText),
            ),
          )
          .map((text) => text.text)
          .firstWhere((span) => span.toPlainText().contains('"id"'));
      final colors = <String, Color?>{};
      line.visitChildren((span) {
        if (span is TextSpan && span.text != null) {
          colors[span.text!.trim()] = span.style?.color;
        }
        return true;
      });
      expect(colors['"id"'], AppColors.link);
      expect(colors[':'], AppColors.textSubtle);
      expect(colors['"c4f1a9"'], AppColors.noteText);
    });

    testWidgets('of large data shows its beginning until Show all', (
      tester,
    ) async {
      await pumpData(
        tester,
        JsonView(value: [for (var i = 0; i < previewLines; i++) i]),
      );
      expect(
        textIn(tester, find.byKey(MonoLines.cutKey)),
        'Showing the first 1,000 of 1,002 lines Show all',
      );

      await tester.tap(find.text('Show all'));
      await tester.pump();
      expect(find.byKey(MonoLines.cutKey), findsNothing);
    });

    testWidgets('of a line too long to show whole cuts it until Show all', (
      tester,
    ) async {
      final long = 'z' * (previewLineLength + 10);
      await pumpData(tester, JsonView(value: {'diff': long}));
      expect(
        textIn(tester, find.byKey(MonoLines.cutKey)),
        'Lines cut at 2,000 characters Show all',
      );

      await tester.tap(find.text('Show all'));
      await tester.pump();
      expect(find.byKey(MonoLines.cutKey), findsNothing);
      expect(find.textContaining(long), findsOneWidget);
    });
  });

  testWidgets('the toggle tells which view is shown and switches it', (
    tester,
  ) async {
    final chosen = <DataMode>[];
    await pumpData(
      tester,
      ModeToggle(mode: DataMode.schema, onChanged: chosen.add),
    );
    await tester.tap(find.text('JSON'));
    expect(chosen, [DataMode.json]);
    expect(
      tester.widget<Text>(find.text('Schema')).style?.color,
      AppColors.textPrimary,
    );
  });
}
