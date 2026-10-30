# Ограничение параллельности узла: `concurrency` — план

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `node('x', body, concurrency: N)` — в процессе одновременно идёт не
больше N эффектов узла, остальные молча ждут по FIFO; describe пишет лимит в
файл графа, плитка показывает `≤N`.

**Architecture:** FIFO-семафор живёт на объекте `Node`; `nodeEffect` отдаёт
его в `_Session.effect`, а `_live` берёт слот после `_running.add` и до
`_started`, отдаёт в `finally`. Эффект из журнала до `_live` не доходит. В
модели `EffectNode.concurrency` — необязательный ключ того же формата 3;
describe читает целочисленный литерал `concurrency:`; UI рисует бейдж из
`EffectNode` узла плитки.

**Tech Stack:** Dart 3 (workspace), `package:test`, analyzer (describe),
Flutter (`apps/nanoflow_ui`).

**Spec:** `docs/superpowers/specs/2026-10-31-node-concurrency-design.md`

## Global Constraints

- `concurrency == null` — без ограничения, поведение прежнее; `concurrency < 1` — `node` бросает `ArgumentError`.
- Очередь строго FIFO по порядку, в котором эффекты узла дошли до ожидания слота.
- Ждущий ничего не пишет: ни записи эффекта, ни `effect-started`, ни лога; ожидание не входит в длительность.
- Ожидание не меняет `key` и `after` ни этого эффекта, ни следующих (ждём в `_outside`).
- Эффект из журнала (resume, `startWithSaved`) слот не берёт и не ждёт.
- Лимит общий для всех сессий процесса и всех графов, где есть узел; не на `Flow`, не на `Graph`, не между процессами.
- Для `flow.stop()` отдельной обработки нет.
- Формат файла графа остаётся 3; ключ `concurrency` пишется, только если задан: старые снимки и фикстуры байт в байт прежние.
- Бейдж `≤N` в одном стиле с `CountBadge`, не сталкивается ни со счётчиком `2×` (справа сверху), ни с бейджем состояния (справа снизу).
- Сторонних пакетов не добавлять. Перед слиянием зелёный `tool/ci.sh`.

## Review Focus

- **Тело узла бросило** — слот всё равно освобождается: следующий запуск того же узла в процессе не виснет. Тест — в задаче 1 (`a node that threw gives its slot back`).
- **`flow.stop()`, пока эффекты стоят в очереди** — сессия кончается `FlowStoppedException`, ждущие ничего не записали, а слоты свободны для другого `Flow` того же процесса. Тест — в задаче 1 (`a stop while effects wait…`).
- **Две сессии одного узла сразу** — лимит один на обе, ждущий из второй сессии молчит. Тест — в задаче 1 (тест 4 спеки ведётся на двух сессиях).
- **`concurrency:` — имя константы, а не литерал** (`concurrency: two`) — describe предупреждает и поля не пишет, а не падает и не пишет мусор. Тест — в задаче 3.
- **Плитка с `≤N`, у которой есть и `2×`** — бейджи не перекрываются. Тест — в задаче 4.

---

### Task 1: Семафор узла в рантайме

**Files:**
- Modify: `packages/nanoflow/lib/src/graph.dart` (`Node`, `node`, `NodeRun`)
- Modify: `packages/nanoflow/lib/src/flow.dart` (`nodeEffect`, `_Session.effect`, `_Session._live`)
- Modify: `README.md` (раздел «Граф из узлов», пункт **Узел**)
- Test: `packages/nanoflow/test/graph_test.dart`, `packages/nanoflow/test/graph_run_test.dart`

**Interfaces:**
- Consumes: —
- Produces:
  - `Node<I, O> node<I, O>(String name, FutureOr<O> Function(I input) body, {int? concurrency})` — бросает `ArgumentError`, если `concurrency != null && concurrency < 1`.
  - `final int? concurrency` на `Node` (публичное, с `///`: сколько эффектов узла идёт в процессе разом; остальные ждут по порядку, ничего не записав).
  - `final class Slots` в `graph.dart` (не экспортируется из `nanoflow.dart`): `Slots(int count)`, `Future<void> take()`, `void release()`. FIFO: счётчик занятых и `Queue<Completer<void>>`; `release` при непустой очереди отдаёт слот первому ждущему, не уменьшая счётчик.
  - `Slots? get slots` в `extension NodeRun` — `null` без лимита; один объект на узел.
  - `_Session.effect<T>(…, {required codec, required place, Slots? slots})`; `nodeEffect` передаёт `node.slots`, `WorkflowFunctions.effect` — нет.

- [ ] **Step 1: Тест на `ArgumentError` и поле в `graph_test.dart`**

```dart
test('a node takes a concurrency of 1 or more, none by default', () {
  expect(node('x', (int n) => n).concurrency, isNull);
  expect(node('x', (int n) => n, concurrency: 1).concurrency, 1);
  expect(() => node('x', (int n) => n, concurrency: 0), throwsArgumentError);
  expect(() => node('x', (int n) => n, concurrency: -1), throwsArgumentError);
});
```

- [ ] **Step 2: Узлы и графы тестов в `graph_run_test.dart`** (верхний уровень, рядом с `paced`)

```dart
final upTo = node('upTo', (int n) async => n);

var running = 0;
var mostRunning = 0;
final entered = <int>[];

final counted = node('counted', (int i) async {
  entered.add(i);
  mostRunning = max(mostRunning, ++running);
  await pause();
  running--;
  return i * 10;
}, concurrency: 3);

final countedAll = Graph<int, Object?>('countedAll', [
  Graph.start(upTo).next((n) => {for (var i = 0; i < n; i++) counted(i)}),
]);

final pacedLimited = node('pacedLimited', (int i) async {
  await pause();
  return i;
}, concurrency: 2);

final pacedLimitedAll = Graph<int, Object?>('pacedLimitedAll', [
  Graph.start(upTo).next((n) => {for (var i = 0; i < n; i++) pacedLimited(i)}),
]);

/// Opened to let [limited] nodes finish.
var limitGate = Completer<void>();

final limited = node('limited', (int i) async {
  entered.add(i);
  await limitGate.future;
  if (i < 0) throw StateError('negative $i');
  return i;
}, concurrency: 3);

final limitedAll = Graph<int, Object?>('limitedAll', [
  Graph.start(upTo).next((n) => {for (var i = 0; i < n; i++) limited(i)}),
]);

/// Runs [limited] once, on -n: its body throws.
final limitedFails = Graph<int, Object?>('limitedFails', [
  Graph.start(upTo).next((n) => limited(-n)),
]);

var heldGate = Completer<void>()..complete();
var atHeld = Completer<void>();

final held = node('held', (String text) async {
  calls.add('held $text');
  if (!atHeld.isCompleted) atHeld.complete();
  await heldGate.future;
  return 'held $text';
}, concurrency: 1);

final heldThenWaits = Graph<String, String>('heldThenWaits', [
  Graph.start(held).next((text) => waits(text)),
]);
```


- [ ] **Step 3: Тесты в `graph_run_test.dart`, группа `group('concurrency', …)`**, с `setUp`, который сбрасывает `running = 0; mostRunning = 0; entered.clear(); limitGate = Completer();`.

1. `'runs at most concurrency effects of a node at once, starting them in the order they were called'`:
   ```dart
   random = Random(1);
   final dir = await tempDir();
   await flowIn(dir).run(countedAll, 10);
   expect(mostRunning, 3);
   expect(entered, [for (var i = 0; i < 10; i++) i]);
   final handle = await onlySession(dir);
   final effects = [
     for (final e in await handle.effects()) if (e.name == 'counted') e,
   ];
   expect(effects, hasLength(10));
   expect(
     [for (final e in effects) await handle.documentValue(e.outputId!)],
     [for (var i = 0; i < 10; i++) i * 10],
   );
   ```
2. `'an effect waiting for a slot writes nothing, whichever session it is of'` — лимит общий на две сессии:
   ```dart
   final dir = await tempDir();
   final flow = flowIn(dir);
   final one = await flow.start(limitedAll, 2);
   final two = await flow.start(limitedAll, 2);
   await until(() => entered.length == 3, 'three limited nodes');
   await Future<void>.delayed(const Duration(milliseconds: 50));
   expect(entered, hasLength(3));
   var written = 0;
   for (final id in [one.id, two.id]) {
     final handle = await openSession(dir, id);
     written += [for (final e in await handle.effects()) if (e.name == 'limited') e].length;
   }
   expect(written, 3);
   limitGate.complete();
   await Future.wait([one.result, two.result]);
   expect(entered, hasLength(4));
   ```
   После этого `effect-started` у каждой записи `limited` ровно один (через `eventsOf`).
3. `'an effect from the journal takes no slot: it gives its result while the slots are taken'`:
   - `gate = Completer(); atGate = Completer();` `first = await flowIn(dir).start(heldThenWaits, 'a')`, `await atGate.future`, `stop()` того flow, `gate.complete()`, `first.result` бросает `FlowStoppedException`.
   - `heldGate = Completer(); atHeld = Completer();` `other = await flowIn(dir).start(heldThenWaits, 'b')`; `await atHeld.future` — единственный слот `held` занят.
   - `gate = Completer()..complete();` `resumed = await flowIn(dir).resume(heldThenWaits, first.id)`; `expect(await resumed.result.timeout(const Duration(seconds: 5)), 'past held a')`.
   - `expect(calls, ['held a', 'waits held a', 'held b', 'waits held a'])`; в событиях сессии `first.id` у записи `held` ровно один `EffectStarted`.
   - `heldGate.complete(); expect(await other.result, 'past held b')`.
4. `'gives the same keys and the same after whatever the timing, with a limit'` — как существующий тест на `paced`, но `pacedLimitedAll` с входом 5: `first` длиной 6, сиды 2…11 дают тот же `key → after`.
5. `'a node that threw gives its slot back'` (Review Focus): `limitGate.complete()`; три раза подряд `await expectLater(flowIn(dir).run(limitedFails, 1), throwsA(isA<StateError>()))` — утечка занимала бы все 3 слота; затем `await flowIn(dir).run(limitedAll, 3).timeout(const Duration(seconds: 5))` проходит, `entered` == `[-1, -1, -1, 0, 1, 2]`.
6. `'a stop while effects wait ends the session, writes nothing for those waiting and leaves the slots free'` (Review Focus): `flow.start(limitedAll, 5)`, `until(entered.length == 3)`, `flow.stop()`, `limitGate.complete()`, результат бросает `FlowStoppedException`; записей `limited` в сессии 3; затем `await flowIn(dir).run(limitedAll, 3).timeout(const Duration(seconds: 5))` проходит.

- [ ] **Step 4: Запустить — тесты падают**

Run: `cd packages/nanoflow && dart test test/graph_test.dart test/graph_run_test.dart`
Expected: FAIL компиляции — `No named parameter with the name 'concurrency'`.

- [ ] **Step 5: `node`, `Node.concurrency`, `Slots`, `NodeRun.slots` в `graph.dart`**

`Node._(this.name, this.body, this.concurrency)` создаёт `Slots(concurrency)` в поле, если лимит задан. Проверка `< 1` — в `node`, `ArgumentError.value(concurrency, 'concurrency', 'must be 1 or more')`. Документация `node` получает пример `node('compress', body, concurrency: 4)`.

- [ ] **Step 6: Слот в `_live` в `flow.dart`**

`nodeEffect` передаёт `slots: node.slots`; `_Session.effect` прокидывает его только в `_live` (ветка «из журнала» не меняется). Порядок в `_live`:

```dart
final ended = Completer<void>();
_running.add(ended.future);
var taken = false;
try {
  await slots?.take();
  taken = true;
  final record = await _started(effect, place);
  … // как сейчас
} finally {
  if (taken) slots?.release();
  _running.remove(ended.future);
  ended.complete();
}
```

Слот освобождается после записи исхода и до `ended.complete()`; `_live` уже идёт в `_outside`, ожидание тоже. Документация `_live` дополняется: ждёт слот узла, ничего не записав.

- [ ] **Step 7: Запустить — тесты проходят**

Run: `cd packages/nanoflow && dart test`
Expected: All tests passed, включая прежний `gives the same keys and the same after whatever the timing`.

- [ ] **Step 8: README**

В `README.md`, пункт **Узел** раздела «Граф из узлов»: `node(name, body, concurrency: 4)` — не больше 4 эффектов узла разом на процесс, общий для всех сессий и графов; остальные ждут по порядку вызова, ничего не записав, и время ожидания не входит в длительность; из журнала — без ожидания. Без `concurrency` — без ограничения.

- [ ] **Step 9: Коммит**

```bash
git add packages/nanoflow README.md
git commit -m "Let a node cap how many of its effects run at once, so a node run once per item of a hundred no longer starts a hundred execs"
```

### Task 2: `concurrency` в модели файла графа

**Files:**
- Modify: `packages/nanoflow_model/lib/src/json_fields.dart`
- Modify: `packages/nanoflow_model/lib/src/graph_file.dart` (`EffectNode`, `GraphNode.fromJson`)
- Modify: `README.md` (формат файла графа, пункт **Узлы:**)
- Test: `packages/nanoflow_model/test/graph_file_test.dart`

**Interfaces:**
- Consumes: —
- Produces:
  - `int? readIntOrNull(Map<String, Object?> json, String key)` — `FormatException('$key: expected an integer or null')` на нецелом.
  - `EffectNode({required id, required place, required name, String? doc, int? concurrency})`, поле `final int? concurrency` (`///`: сколько эффектов узла идёт разом, `null` — без ограничения). Входит в `==`, `hashCode`, `toString`; `toJson` добавляет `if (concurrency != null) 'concurrency': concurrency` последним ключом.

- [ ] **Step 1: Тесты в группе, где `reads the doc of a function and of an effect`**

```dart
test('reads and writes the concurrency of an effect, and none when its key is missing', () {
  const limited = EffectNode(id: '1', place: null, name: 'x', concurrency: 4);
  expect(limited.toJson()['concurrency'], 4);
  expect(GraphNode.fromJson(limited.toJson()), limited);
  const free = EffectNode(id: '1', place: null, name: 'x');
  expect(free.toJson().containsKey('concurrency'), isFalse);
  expect(
    GraphNode.fromJson({'id': '1', 'kind': 'effect', 'name': 'x', 'place': null, 'doc': null}),
    free,
  );
  expect(limited, isNot(free));
  expect('$limited', contains('concurrency: 4'));
});

test('names a concurrency that is not an integer', () {
  expect(
    () => GraphNode.fromJson({'id': '1', 'kind': 'effect', 'name': 'x', 'concurrency': '4'}),
    throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('concurrency'))),
  );
});
```

- [ ] **Step 2: Запустить — падает**

Run: `cd packages/nanoflow_model && dart test test/graph_file_test.dart`
Expected: FAIL компиляции — `No named parameter with the name 'concurrency'`.

- [ ] **Step 3: `readIntOrNull` и поле `EffectNode.concurrency`**

`fromJson` для `'effect'`: `concurrency: readIntOrNull(json, 'concurrency')`.

- [ ] **Step 4: Запустить — проходит**

Run: `cd packages/nanoflow_model && dart test`
Expected: All tests passed (прежние тесты на JSON и порядок ключей не меняются).

- [ ] **Step 5: README**

В пункте **Узлы:** формата файла графа: у `effect` необязательное `concurrency` — лимит узла из `node(…, concurrency: N)`; без лимита ключа нет, номер формата тот же.

- [ ] **Step 6: Коммит**

```bash
git add packages/nanoflow_model README.md
git commit -m "Carry a node's concurrency in the graph file, so describe can hand it to the UI without changing the format"
```

### Task 3: describe читает `concurrency:`

**Files:**
- Modify: `packages/nanoflow_describe/lib/src/graphs.dart` (`_NodeDeclaration`, `_declareNodelike`, `_point`)
- Modify: `packages/nanoflow_describe/lib/src/extract.dart` (`_Effect`)
- Create: `packages/nanoflow_describe/test/fixtures/graph_concurrency/lib/graph_concurrency.dart`
- Test: `packages/nanoflow_describe/test/graphs_test.dart`

**Interfaces:**
- Consumes: `EffectNode(…, concurrency:)` из задачи 2.
- Produces: `_NodeDeclaration(name, variable, doc, made, {int? concurrency})`; `_Effect(name, place, doc, {int? concurrency})`; `int? _concurrencyIn(MethodInvocation made)` рядом с `_nameIn` — значение `IntegerLiteral` именованного аргумента `concurrency`, иначе, если аргумент есть, `_warn(made, 'node concurrency is not an integer literal')` и `null`.

- [ ] **Step 1: Фикстура — ровно этот текст (строки важны для `place`)**

```dart
// Nodes with a limit of effects at once: a literal one goes to the graph
// file; one that is not a literal is warned of and left out.
import 'package:nanoflow/nanoflow.dart';

const two = 2;

final heavy = node('heavy', (int x) async => x, concurrency: 4);
final light = node('light', (int x) async => x);
final counted = node('counted', (int x) async => x, concurrency: two);

final limited = Graph<int, int>('limited', [
  Graph.start(heavy).next((x) => light(x)),
  Graph.part(light).next((x) => counted(x)),
]);
```

- [ ] **Step 2: Тест**

```dart
test('gives an effect the concurrency of its node when it is an integer '
    'literal, and warns of one that is not', () async {
  const file = 'lib/graph_concurrency.dart';
  final graph = await describeFixture('graph_concurrency');
  expect(_effectsOf(graph, '$file#limited'), [
    {'id': '1', 'kind': 'effect', 'name': 'heavy', 'place': '$file:12', 'doc': null, 'concurrency': 4},
    {'id': '2', 'kind': 'effect', 'name': 'light', 'place': '$file:12', 'doc': null},
    {'id': '3', 'kind': 'effect', 'name': 'counted', 'place': '$file:13', 'doc': null},
  ]);
  expect(graph['warnings'], [
    {'place': '$file:9', 'message': 'node concurrency is not an integer literal', 'function': null},
  ]);
});
```

Id и места — по правилу `graph_sets`: узел получает id и место там, где граф впервые его называет (`heavy` и `light` — строка 12, `counted` — 13).

- [ ] **Step 3: Запустить — падает**

Run: `cd packages/nanoflow_describe && dart test test/graphs_test.dart`
Expected: FAIL — у `heavy` нет `concurrency`, предупреждений нет.

- [ ] **Step 4: `_concurrencyIn`, поле в `_NodeDeclaration` и `_Effect`**

`_point` передаёт `node.concurrency` в `_Effect`; `_Effect.node` — в `EffectNode`. Эффекты `f.effect` и вызовы графов поля не получают.

- [ ] **Step 5: Запустить — проходит, прежние фикстуры не меняются**

Run: `cd packages/nanoflow_describe && dart test && cd ../../examples/review && dart run nanoflow_describe --check`
Expected: All tests passed; `--check` без расхождений.

- [ ] **Step 6: Коммит**

```bash
git add packages/nanoflow_describe
git commit -m "Write a node's concurrency into its graph file, so the canvas can show which nodes queue their effects"
```

### Task 4: Бейдж `≤N` на плитке

**Files:**
- Modify: `apps/nanoflow_ui/lib/graph/canvas/tile_marks.dart` (рядом с `CountBadge`)
- Modify: `apps/nanoflow_ui/lib/graph/canvas/node_tile.dart` (`build`, документация класса)
- Test: `apps/nanoflow_ui/test/graph/canvas/node_tile_test.dart`

**Interfaces:**
- Consumes: `EffectNode.concurrency` из задачи 2 через `NodeBox.node` (тот же `GraphNode`, откуда `canvas_bodies.dart` берёт `doc`; новой проводки не нужно).
- Produces: `class LimitBadge extends StatelessWidget { const LimitBadge(this.limit); final int limit; }` — `CountBadge('≤$limit')` по виду (тот же фон, рамка, `CanvasText.badge`). В `NodeTile.build` — над **левым верхним** углом плитки эффекта: `left: tile.left - _overhang`, `top: tile.top - 9`, как `CountBadge` справа; без `marks` тоже рисуется (лимит — свойство узла, не сессии).

- [ ] **Step 1: Тест**

`pumpTile` получает необязательный `GraphLayout? of` (по умолчанию общий `layout`). Новый layout в тесте — `layoutBody` тела из одного `EffectNode(id: 'limited', place: 'lib/a.dart:3', name: 'compress', concurrency: 4)` с рёбрами из начала и в конец, те же `functions: const {}` и `options`.

```dart
testWidgets('an effect of a node with a concurrency says it over its top '
    'left corner, clear of its count and its state', (tester) async {
  await pumpTile(tester, 'limited', of: limitedLayout,
      marks: const NodeMarks(state: NodeState.visited, effects: 2));
  final tile = tileOf(tester, 'limited');
  final limit = tester.getRect(find.byType(LimitBadge));
  expect(find.text('≤4'), findsOneWidget);
  expect(limit.left, lessThan(tile.left));
  expect(limit.top, lessThan(tile.top));
  expect(limit.overlaps(tester.getRect(find.byType(CountBadge))), isFalse);

  await pumpTile(tester, 'effect');
  expect(find.byType(LimitBadge), findsNothing);
});
```

- [ ] **Step 2: Запустить — падает**

Run: `cd apps/nanoflow_ui && flutter test test/graph/canvas/node_tile_test.dart`
Expected: FAIL компиляции — `LimitBadge` не определён.

- [ ] **Step 3: `LimitBadge` и его место в `NodeTile.build`**

Только для `node.kind == NodeKind.effect` и `node.node case EffectNode(:final concurrency?)`. Документация класса `NodeTile` дополняется: `≤4` над левым верхним углом эффекта узла с лимитом.

- [ ] **Step 4: Запустить — проходит, золотые не меняются**

Run: `cd apps/nanoflow_ui && flutter analyze && flutter test`
Expected: No issues found; All tests passed.

- [ ] **Step 5: Посмотреть на плитку**

Отрендерить плитку `compress` с `≤4`, `2×` и бейджем состояния в PNG (временный golden-тест с `matchesGoldenFile` в scratchpad или `--update-goldens` во временный файл, не в `test/goldens`) и открыть скриншот: `≤4` читается, ни с чем не сталкивается, выглядит как `2×`. Временный файл не коммитить.

- [ ] **Step 6: Коммит**

```bash
git add apps/nanoflow_ui
git commit -m "Mark a tile with ≤N when its node caps its effects, so a silent tile reads as queued rather than stuck"
```

### Task 5: Полный прогон

- [ ] **Step 1:** Run: `tool/ci.sh`. Expected: выходит с 0 — формат, анализ, `describe --check`, тесты всех пакетов и UI зелёные.
- [ ] **Step 2:** Если `dart format` что-то поменял — коммит `Keep the concurrency changes formatted, as CI checks`.
