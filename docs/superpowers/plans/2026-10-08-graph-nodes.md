# Граф из узлов — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** граф из независимых узлов «вход → выход» рядом с функцией
воркфлоу: объявление `Graph`, исполнение в сессии с журналом, извлечение
`describe` в нынешний формат файла графа.

**Architecture:** `Graph` в `package:nanoflow` проверяет объявление и строит
форму (`GraphShape`); исполнитель обходит форму кодом, который ждёт узлы как
написанная рукой функция (`await` эффекта, `Future.wait` ветвей), поэтому
ключи эффектов и `after` — прежние. Узел-функция — эффект, её выход
кодируется по типу функции (кодеки спрашивают «подтип ли?»). `describe`
рисует граф телом из прежних узлов `effect`/`fork`/`call`; UI не меняется.

**Tech Stack:** Dart 3.13 pub workspace, `package:analyzer` 14, `package:test`.

**Spec:** `docs/superpowers/specs/2026-10-08-graph-nodes-design.md`

## Global Constraints

- Формат файла графа остаётся `2`; новых видов узлов и полей нет.
- `nanoflow` не зависит от `analyzer`; UI импортирует только
  `nanoflow_model` и `nanoflow_reader`.
- Публичная точка пакета — `lib/<имя>.dart`, остальное в `lib/src/`;
  непубличное для тестов — из `src/` (как `startWithSaved`).
- Комментарии и документы — в стиле репозитория: полные предложения, «why»;
  README и спеки по-русски, код и комментарии в коде по-английски.
- Коммиты: заголовок объясняет «зачем», повелительное наклонение, в конце
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- `dart format` и `dart analyze --fatal-infos` чистые; CI — `tool/ci.sh`.
- Без `sleep` больше 10 с в командах.

## Review Focus

1. Узел-функция возвращает класс без кодека: эффект падает вживую с
   `CodecException`, а не пишет карту, которую дальше не прочесть.
2. `resume` посреди графа: выходы узлов из журнала раскодируются в
   `sealed`, перечисление и запись, и ветвление идёт той же дорогой.
3. Схождение, у которого один источник так и не дал выхода: граф
   кончается, а не висит.
4. Узел бросает в одной из параллельных веток: сессия падает с его ошибкой
   после того, как кончились остальные; ожидающие схождения не вешают её.
5. Замыкание узлом, два узла с одним именем, `next` после карты: понятный
   `ArgumentError` при создании графа, а не ошибка посреди сессии.

---

### Task 1: Кодеки — перечисления, записи из двух полей, тип выхода функции

**Files:**
- Modify: `packages/nanoflow/lib/src/codecs.dart`
- Modify: `packages/nanoflow/lib/src/flow.dart` (`addEnum`)
- Test: `packages/nanoflow/test/codecs_test.dart`

**Interfaces:**
- Produces:
  - `void Codecs.addEnum<T extends Enum>(List<T> values)`;
    `void Flow.addEnum<T extends Enum>(List<T> values)`.
  - `final class TypeCodec { Type get type; Object? encode(Object? value);
    Object? decode(Object? json); bool get canDecode; }`.
  - `TypeCodec Codecs.of<T>()` — то же, что `encode<T>`/`decode<T>`.
  - `TypeCodec Codecs.resultOf(Function node)` — для функции одного
    параметра: тип её результата по вопросам `node is FutureOr<X>
    Function(Never)`.

- [ ] **Step 1: Failing tests** в `codecs_test.dart`:

```dart
enum Verdict { pass, fail }

sealed class Shape {
  static Shape fromJson(Map<String, Object?> json) =>
      json['r'] == null ? Square(json['a']! as int) : Circle(json['r']! as int);
  Map<String, Object?> toJson();
}
final class Square extends Shape {
  Square(this.a);
  final int a;
  @override
  Map<String, Object?> toJson() => {'a': a};
}
final class Circle extends Shape {
  Circle(this.r);
  final int r;
  @override
  Map<String, Object?> toJson() => {'r': r};
}

Future<Shape> makeShape(int n) async => Square(n);
Future<Verdict> judge(String s) async => Verdict.pass;
Future<(Verdict, List<String>)> judgeWith(String s) async => (Verdict.pass, [s]);
Future<List<Shape>> shapes(int n) async => [Square(n)];
Future<void> nothing(int n) async {}
Future<Object> anything(int n) async => 1;
String name(int n) => '$n';

group('enums', () {
  test('an enum with addEnum is written by name and read back', () {
    final codecs = Codecs()..addEnum(Verdict.values);
    expect(codecs.encode<Verdict>(Verdict.fail), 'fail');
    expect(codecs.decode<Verdict>('fail'), Verdict.fail);
    expect(codecs.decode<List<Verdict?>>(['pass', null]), [Verdict.pass, null]);
  });
  test('an enum without addEnum is a CodecException', () {
    expect(() => Codecs().encode<Verdict>(Verdict.fail),
        throwsA(isA<CodecException>()));
  });
  test('an unknown name does not decode', () {
    final codecs = Codecs()..addEnum(Verdict.values);
    expect(() => codecs.decode<Verdict>('maybe'), throwsA(isA<CodecException>()));
  });
});

group('records of two fields', () {
  test('are written as a list and read back with their field types', () {
    final codecs = Codecs()..addEnum(Verdict.values);
    final json = codecs.encode<(Verdict, List<String>)>((Verdict.pass, ['a']));
    expect(json, ['pass', ['a']]);
    final back = codecs.decode<(Verdict, List<String>)>(json);
    expect(back, (Verdict.pass, ['a']));
    expect(back.$2, isA<List<String>>());
  });
});

group('resultOf', () {
  late Codecs codecs;
  setUp(() => codecs = Codecs()
    ..addCodec(Shape.fromJson)
    ..addEnum(Verdict.values));

  test('decodes by the type the function returns', () {
    expect(codecs.resultOf(makeShape).decode({'r': 2}), isA<Circle>());
    expect(codecs.resultOf(judge).decode('fail'), Verdict.fail);
    expect(codecs.resultOf(judgeWith).decode(['pass', ['x']]),
        (Verdict.pass, ['x']));
    expect(codecs.resultOf(shapes).decode([{'a': 1}]), isA<List<Shape>>());
    expect(codecs.resultOf(name).decode('7'), '7');
    expect(codecs.resultOf(nothing).decode(null), isNull);
  });
  test('encodes what comes back', () {
    expect(codecs.resultOf(makeShape).encode(Square(3)), {'a': 3});
    expect(codecs.resultOf(judgeWith).encode((Verdict.fail, ['y'])),
        ['fail', ['y']]);
  });
  test('a value JSON only through toJson, returned as Object, is a '
      'CodecException', () {
    expect(() => codecs.resultOf(anything).encode(Square(1)),
        throwsA(isA<CodecException>()));
  });
});
```

- [ ] **Step 2: Run** `cd packages/nanoflow && dart test test/codecs_test.dart` — FAIL: `addEnum`, `resultOf` не определены.

- [ ] **Step 3: Implement** в `codecs.dart`:
  - `_Codec<T>` получает `decode` и, для перечислений, `encodes(Object)`:

```dart
final class _Codec<T> {
  _Codec.ofJson(T Function(Map<String, Object?> json) fromJson)
    : decode = ((json) => fromJson(json! as Map<String, Object?>)),
      _values = null;

  _Codec.ofEnum(List<T> values)
    : decode = ((json) => values.firstWhere(
          (v) => (v as Enum).name == json,
          orElse: () => throw FormatException('no value named $json'),
        )),
      _values = values;

  final Object? Function(Object? json) decode;
  final List<T>? _values;

  _TypeOf<T> get type => _TypeOf<T>();

  /// The name an enum codec writes [value] as; `null` when it is not one of
  /// its values.
  String? nameOf(Object value) =>
      _values != null && _values.contains(value) ? (value as Enum).name : null;
}
```

  - `encode`: `toEncodable` сначала ищет имя у кодеков-перечислений, потом
    запись `(Object?, Object?)` → `[a, b]`, потом `toJson`. Общий код —
    `_encodeWith(_Decoder? decoder, Type type, Object? value)`, его зовут
    `encode<T>` и `TypeCodec`.
  - `_find` получает две функции контекста: `upper` (для «подходит») и
    `lower` (для «равен»); у списка, карты и `?` они одинаковы, у поля
    записи — `(hole, Object?)` и `(hole, Never)`. Ветка записей после карт:

```dart
if (fits(const _TypeOf<(Object?, Object?)>())) {
  final first = _find(
    target,
    (hole) => upper(_pair(hole, const _TypeOf<Object?>())),
    (hole) => lower(_pair(hole, const _TypeOf<Never>())),
    depth + 1,
  );
  if (first == null) return null;
  final second = _find(
    target,
    (hole) => upper(_pair(first.type, hole)),
    (hole) => lower(_pair(first.type, hole)),
    depth + 1,
  );
  if (second == null) return null;
  return (
    type: _pair(first.type, second.type),
    decode: (json) {
      final [a, b] = json! as List<Object?>;
      return (first.decode(a), second.decode(b));
    },
    usesCodec: true,
  );
}

_TypeOf<Object?> _pair(_TypeOf<Object?> a, _TypeOf<Object?> b) =>
    a.pass(<A>() => b.pass(<B>() => _TypeOf<(A, B)>()));
```

  - `resultOf(node)`: обход только по «подходит», самый узкий кодек, иначе
    `Object?` — JSON как есть:

```dart
TypeCodec resultOf(Function node) {
  bool returns(_TypeOf<Object?> type) =>
      type.pass(<T>() => node is FutureOr<T> Function(Never));
  final decoder =
      _fitting(returns, (hole) => hole, 0) ??
      (type: const _TypeOf<Object?>(), decode: _same, usesCodec: false);
  return TypeCodec._(this, decoder);
}

/// The decoder of the narrowest type made of JSON types and types with a
/// codec that [returns] says the result is a subtype of, put in the hole
/// of [context]; `null` when there is none narrower than `Object?`.
_Decoder? _fitting(
  bool Function(_TypeOf<Object?> type) returns,
  _TypeOf<Object?> Function(_TypeOf<Object?> hole) context,
  int depth,
) {
  bool fits(_TypeOf<Object?> hole) => returns(context(hole));
  if (depth > _maxDepth || fits(const _TypeOf<Never>())) return null;
  if (!fits(const _TypeOf<Object>())) {
    if (fits(const _TypeOf<Null>())) {
      return (type: const _TypeOf<Null>(), decode: _same, usesCodec: false);
    }
    final inner = _fitting(returns, (hole) => context(hole.nullable), depth + 1);
    if (inner == null) return null;
    return (
      type: inner.type.nullable,
      decode: (json) => json == null ? null : inner.decode(json),
      usesCodec: inner.usesCodec,
    );
  }
  _Codec<Object?>? narrowest;
  for (final codec in _codecs) {
    if (fits(codec.type) &&
        (narrowest == null || codec.type.isSubtypeOf(narrowest.type))) {
      narrowest = codec;
    }
  }
  if (narrowest != null) {
    return (type: narrowest.type, decode: narrowest.decode, usesCodec: true);
  }
  for (final type in _leaves.skip(1)) {
    if (fits(type)) return (type: type, decode: _same, usesCodec: false);
  }
  _Decoder raw(_Decoder? d) =>
      d ?? (type: const _TypeOf<Object?>(), decode: _same, usesCodec: false);
  if (fits(const _TypeOf<List<Object?>>())) {
    final element = raw(_fitting(returns, (h) => context(h.list), depth + 1));
    return _listOf(element);
  }
  if (fits(const _TypeOf<Map<String, Object?>>())) {
    final value = raw(_fitting(returns, (h) => context(h.map), depth + 1));
    return _mapOf(value);
  }
  if (fits(const _TypeOf<(Object?, Object?)>())) {
    final first = raw(_fitting(
      returns, (h) => context(_pair(h, const _TypeOf<Object?>())), depth + 1));
    final second = raw(_fitting(
      returns, (h) => context(_pair(first.type, h)), depth + 1));
    return _pairOf(first, second);
  }
  return (type: const _TypeOf<Object>(), decode: _same, usesCodec: false);
}
```

    (`_listOf`, `_mapOf`, `_pairOf` — вынесенные из `_find` сборщики
    декодеров списка, карты и записи.)
  - `TypeCodec`:

```dart
/// How the values of one type become JSON and come back: the type a
/// workflow or an effect declares, or the one a node function returns.
final class TypeCodec {
  TypeCodec._(this._codecs, this._decoder, this.type);

  final Codecs _codecs;
  final _Decoder? _decoder;

  /// The type, for the [CodecException]s.
  final Type type;

  bool get canDecode => _decoder != null;
  Object? encode(Object? value) => _codecs._encodeWith(_decoder, type, value);
  Object? decode(Object? json) => _codecs._decodeWith(_decoder, type, json);
}
```

    `of<T>()` проверяет при раскодировании `value is T`, как `decode<T>`.
  - `Flow.addEnum<T extends Enum>(List<T> values) => _codecs.addEnum(values);`
    с doc-комментарием о записи по имени.

- [ ] **Step 4: Run** `dart test test/codecs_test.dart` — PASS; весь `dart test` пакета — PASS.

- [ ] **Step 5: Commit** — `Let sessions keep enums and pairs, and find the type a function returns, so a graph node's output can be journaled without declaring its type twice`.

### Task 2: Объявление графа и его проверки

**Files:**
- Create: `packages/nanoflow/lib/src/graph.dart`
- Modify: `packages/nanoflow/lib/src/project.dart` (`staticNameOf`)
- Modify: `packages/nanoflow/lib/nanoflow.dart` (экспорт `Graph`, `Part`, `Exit`)
- Test: `packages/nanoflow/test/graph_test.dart`

**Interfaces:**
- Consumes: `staticNameOf(Function)` (новый, из `project.dart`).
- Produces (из `src/graph.dart`, не экспортируются, кроме `Graph`, `Part`,
  `Exit`):

```dart
final class Graph<I, O> {
  Graph(String name, List<Part> parts);
  final String name;
  static Part start(Object node);
  static Part part(Object node);
  static Part join(List<Object> nodes);
  Future<O> call(Flow f, I input);          // Task 3
}
final class Part { Part next(Object target, {Object? otherwise}); }
abstract class Exit<T> { const Exit(this.value); final T value; }

enum NodeKind { function, workflow, graph }
final class GraphShape { String name; List<ShapeNode> starts; List<ShapeNode> nodes; }
final class ShapeNode {
  Object node; String name; NodeKind kind;
  Routes? routes;                // null — no arrows
  List<ShapeJoin> joins;         // the joins it is a source of
}
sealed class Routes {}
final class AllRoutes extends Routes { List<ShapeNode> targets; }
final class CaseRoutes extends Routes {
  List<({Object? key, List<ShapeNode> targets})> cases;
  List<ShapeNode> otherwise;
}
final class ShapeJoin { List<ShapeNode> sources; List<ShapeNode> targets; }
GraphShape shapeOf(Graph<Object?, Object?> graph);
Graph<Object?, Object?>? graphOfCall(Function function);  // registry
```

- [ ] **Step 1: Failing tests** `graph_test.dart` — проверки создания:

```dart
Future<int> one(String s) async => 1;
Future<int> two(int n) async => n + 1;
Future<String> three(int n) async => '$n';
Future<int> wf(Flow f, int n) async => n;
Future<String> both((String, int) pair) async => '${pair.$1}${pair.$2}';

Matcher rejects(String part) => throwsA(
  isA<ArgumentError>().having((e) => '${e.message}', 'message', contains(part)),
);

void main() {
  test('builds the shape: starts, routes, joins', () {
    final g = Graph<String, String>('g', [
      Graph.start(one).next({1: two}, otherwise: three),
      Graph.part(two).next({three, wf}),
      Graph.join([three, wf]).next(both),
    ]);
    final shape = shapeOf(g);
    expect([for (final n in shape.nodes) n.name],
        ['one', 'two', 'three', 'wf', 'both']);
    expect([for (final n in shape.nodes) n.kind], [
      NodeKind.function, NodeKind.function, NodeKind.function,
      NodeKind.workflow, NodeKind.function,
    ]);
    expect(shape.starts.single.name, 'one');
    final routes = shape.nodes.first.routes! as CaseRoutes;
    expect(routes.cases.single.key, 1);
    expect(routes.cases.single.targets.single.name, 'two');
    expect(routes.otherwise.single.name, 'three');
    final join = shape.nodes[2].joins.single;
    expect([for (final n in join.sources) n.name], ['three', 'wf']);
    expect(join.targets.single.name, 'both');
  });

  test('rejects what is not a graph', () {
    expect(() => Graph('g', [Graph.start((String s) => 1)]),
        rejects('top-level function or a static method'));
    expect(() => Graph('g', [Graph.start(42)]), rejects('is not a node'));
    expect(() => Graph('g', []), rejects('no start'));
    expect(() => Graph('g', [Graph.start(one).next(two), Graph.part(one).next(three)]),
        rejects('the arrows of one are declared twice'));
    expect(() => Graph('g', [Graph.start(one), Graph.part(two)]),
        rejects('two cannot be reached'));
    expect(() => Graph('g', [Graph.start(one).next(two), Graph.join([two]).next(three)]),
        rejects('a join takes 2 to 6 different nodes'));
    expect(() => Graph('g', [Graph.start(one).next(two, otherwise: three)]),
        rejects('otherwise goes with a map'));
    expect(() => Graph('g', [Graph.start(one).next({two}).next(three)]),
        rejects('after a set or a map'));
  });
  test('a graph is found by its call', () {
    final g = Graph<String, int>('g', [Graph.start(one)]);
    Future<int> Function(Flow, String) call = g;
    expect(graphOfCall(call), same(g));
  });
}
```

  Каждый отказ — отдельный `expect` с подстрокой сообщения:
  `is not a node`, `top-level function or a static method`,
  `two nodes are named`, `arrows of two are declared twice`, `no start`,
  `cannot be reached`, `a join takes 2 to 6 different nodes`,
  `otherwise goes with a map`, `after a set or a map`.

- [ ] **Step 2: Run** `dart test test/graph_test.dart` — FAIL (нет `Graph`).

- [ ] **Step 3: Implement** `graph.dart`:
  - `staticNameOf(Function f)` в `project.dart` — регулярка
    `_staticFunction`; `workflowNameOf` = `graphOfCall(w)?.name ??
    staticNameOf(w) ?? throw ArgumentError(…)`.
  - Вид узла: `Graph` → `graph`; `node is Object? Function(Flow, Never)` →
    `workflow`; `node is Object? Function(Never)` → `function`; иначе
    ошибка `is not a node: a node is a function of one parameter, a workflow
    function of a Flow and an input, or a Graph`.
  - `Part` хранит общий `_Chain` (голова: старт, кусок или схождение;
    список стрелок; найденные ошибки) и `_at` — узел или схождение, на
    котором кусок стоит; `null` после множества или карты. `next` дописывает
    стрелку `(_at, target, otherwise)` и ошибку, если `_at == null` или
    `otherwise` без карты.
  - Конструктор `Graph`: собирает узлы по `==` значения, проверяет всё по
    списку спека §7, достижимость — обходом от стартов (цели схождения
    достижимы, когда достижимы все его источники), бросает
    `ArgumentError('graph "$name":\n- …')` со всеми ошибками; кладёт себя в
    `_graphs` (`graphOfCall` сравнивает `g.call == function`).
  - Цель стрелки: узел → `AllRoutes([n])`; множество → `AllRoutes(nodes)`;
    карта → `CaseRoutes(cases в порядке карты, otherwise)`; у схождения
    цель — узел или множество, карта — ошибка `a join leads to a node or a
    set`.

- [ ] **Step 4: Run** — PASS.

- [ ] **Step 5: Commit** — `Let a graph of nodes be declared and checked as a whole, so a node is a function the graph refers to rather than a place in the code`.

### Task 3: Исполнение графа в сессии

**Files:**
- Create: `packages/nanoflow/lib/src/graph_run.dart`
- Modify: `packages/nanoflow/lib/src/flow.dart` (`nodeEffect`, снимок графа
  в `_Session`, `TypeCodec` в эффекте)
- Modify: `packages/nanoflow/lib/src/graph.dart` (`call`)
- Test: `packages/nanoflow/test/graph_run_test.dart`

**Interfaces:**
- Consumes: `GraphShape`, `ShapeNode`, `Routes`, `ShapeJoin` (Task 2);
  `Codecs.resultOf`, `TypeCodec` (Task 1).
- Produces: `Future<Object?> runGraph(GraphShape shape, Flow flow, Object?
  input)`; `Future<Object?> nodeEffect(Flow flow, GraphShape graph,
  ShapeNode node, Object? input)` в `flow.dart`.

- [ ] **Step 1: Failing tests** `graph_run_test.dart` (каталог проекта —
  `tempDir()`, сессия — `Flow(directory: dir).run(graph, input)`):
  - ветвление: `Exit` по типу (груз в цель), перечисление с парой
    `(Verdict, Report)`, `null`-ключ у `T?`, `bool`, `otherwise` целиком,
    неразобранный выход кончает ветку и становится результатом;
  - множество: оба узла выполняются, эффекты с `after` узла до них;
  - схождение: цель получает запись выходов в порядке списка; в петле —
    по разу на набор; неполное — граф кончается;
  - петля `inspect → fix → inspect` с выходом;
  - узел — функция воркфлоу (её эффекты в журнале), узел — граф;
  - граф из функции воркфлоу: `await sub(f, x)`;
  - `start`/`resume`: сессия падает на втором узле (узел бросает, пока
    не открыт флаг), `resume` берёт первый узел из журнала (не выполняет
    его снова) и раскодирует его выход `sealed`/перечислением/записью;
    `unfinished(graph)` находит сессию; имя сессии — имя графа;
  - результат: последний неушедший выход; `TypeError`, когда его нет, а
    `O` не допускает `null`;
  - место эффекта узла: с файлом графа, где у графа `g` узел `one` в
    `lib/g.dart:3`, эффект `one` пишет `place: lib/g.dart:3`; без файла —
    `null`;
  - ошибка узла в одной ветке множества: сессия падает с ней, вторая ветка
    дописана; схождение с упавшим источником не вешает сессию;
  - ключи: граф с узлами, ждущими `pause()`, — 20 запусков с разными
    `Random` дают одинаковые ключи и `after`.

- [ ] **Step 2: Run** — FAIL.

- [ ] **Step 3: Implement.**
  - `flow.dart`: `_Session` получает снимок графа (`Map<String, Object?>?`)
    и лениво — `GraphFile` (`FormatException` → `null`);
    `String? placeOfNode(String graph, String node)` — `place` узла
    `effect` с именем `node` в теле функции файла с `name == graph`.
    `_Session.effect<T>` принимает `TypeCodec codec` и
    `String? Function() place` вместо `trace`; `Flow.effect` даёт
    `_codecs.of<T>()` и `placeOf(trace, …)`. Новая:

```dart
/// Runs [node], a function of one parameter of [graph], on [input] as an
/// effect of the session this is called in: named after the node, at the
/// place the graph file gives the node, its result journaled by the type
/// the function returns.
Future<Object?> nodeEffect(
  Flow flow,
  GraphShape graph,
  ShapeNode node,
  Object? input,
) {
  final session = flow._sessionHere(node.name);
  return session.effect<Object?>(
    node.name,
    () => (node.node as dynamic)(input) as FutureOr<Object?>,
    codec: flow._codecs.resultOf(node.node as Function),
    place: () => session.placeOfNode(graph.name, node.name),
  );
}
```

  - `graph_run.dart` — исполнитель:

```dart
Future<Object?> runGraph(GraphShape shape, Flow flow, Object? input) =>
    _Run(shape, flow).run(input);

final class _Run {
  _Run(this._shape, this._flow);

  final GraphShape _shape;
  final Flow _flow;

  /// Branches that run now: neither ended nor waiting for their next.
  int _running = 0;

  final _joins = Map<ShapeJoin, _JoinState>.identity();

  /// The last output that went nowhere.
  ({Object? value})? _result;

  Future<Object?> run(Object? input) async {
    await Future.wait([for (final start in _shape.starts) _branch(start, input)]);
    return _result?.value;
  }

  /// Runs [first] on [input] and what follows it, in place while one node
  /// follows, in branches side by side when several do.
  Future<void> _branch(ShapeNode first, Object? input) async {
    _running++;
    var waiting = false;
    try {
      var node = first;
      var value = input;
      while (true) {
        final output = await _call(node, value);
        final next = _routes(node, output);
        final more = <Future<void> Function()>[];
        for (final join in node.joins) {
          final state = _joins[join] ??= _JoinState(this, join);
          if (identical(join.sources.first, node)) {
            more.add(() => _lead(state, output));
          } else {
            state.deposit(node, output);
          }
        }
        if (next.isEmpty && node.joins.isEmpty) _result = (value: output);
        if (more.isEmpty && next.length == 1) {
          (node, value) = next.single;
          continue;
        }
        if (more.isEmpty && next.isEmpty) return;
        final started = [
          for (final (n, v) in next) _branch(n, v),
          for (final start in more) start(),
        ];
        waiting = true;
        _ran();
        await Future.wait(started);
        return;
      }
    } finally {
      if (!waiting) _ran();
    }
  }

  Future<Object?> _call(ShapeNode node, Object? value) => switch (node.kind) {
    NodeKind.function => nodeEffect(_flow, _shape, node, value),
    NodeKind.workflow || NodeKind.graph => _awaited(
      (node.node as dynamic)(_flow, value),
    ),
  };

  /// Goes on from the join [state] after its first node gave [output]: once
  /// every other node of the join has given one too, runs its targets on the
  /// record of the outputs; ends when the graph has nothing else to run.
  Future<void> _lead(_JoinState state, Object? output) async {
    final outputs = await state.arrive(output);
    if (outputs == null) return;
    final started = [
      for (final target in state.join.targets) _branch(target, outputs),
    ];
    _ran();
    await Future.wait(started);
  }

  /// A branch stopped running; when none runs, no join can fill up any more.
  void _ran() {
    _running--;
    if (_running == 0) {
      for (final state in _joins.values) {
        state.abandon();
      }
    }
  }
  …
}
```

    `_routes(node, output)`: `AllRoutes` — каждой цели выход целиком;
    `CaseRoutes` — предмет и груз (`(k, p)` → `k`/`p`; `Exit` → `v`/`v.value`;
    иначе `v`/`v`), первый ключ, где `key is Type ? subject.runtimeType ==
    key : subject == key`, — целям груз; не нашлось — целям `otherwise` выход
    целиком. `_JoinState`: очередь выходов на каждый не первый источник,
    очередь ждущих первых (`Completer<Record?>`); `_fire` при полном наборе
    увеличивает `_running` и отдаёт запись (`(a, b)` … `(a, b, c, d, e, f)`);
    `abandon` отдаёт `null` всем ждущим.
  - `Graph.call(Flow f, I input) async => await runGraph(_shape, f, input) as O;`

- [ ] **Step 4: Run** `dart test` пакета — PASS.

- [ ] **Step 5: Commit** — `Run a graph in its session as a hand-written function would, so its nodes get the same keys on every run and a resumed session takes them from the journal`.

### Task 4: Модель — воркфлоу по имени

**Files:**
- Modify: `packages/nanoflow_model/lib/src/graph_file.dart` (`workflowNamed`)
- Test: `packages/nanoflow_model/test/graph_file_test.dart`

- [ ] **Step 1: Failing test:** файл с `workflows: ['lib/g.dart#reviewGraph']`
  и функцией с этим id и `name: 'review'` — `workflowNamed('review')` даёт
  её, `workflowNamed('reviewGraph')` — `null`; прежние случаи (`#name`,
  `.name` у метода) по-прежнему находятся.
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement:** `workflowNamed` берёт функцию из `workflows`,
  у которой `name == name`.
- [ ] **Step 4: Run** — PASS; `cd apps/nanoflow_ui && flutter test` — PASS.
- [ ] **Step 5: Commit** — `Find a session's workflow by its name rather than by the end of its id, since a graph's name need not be its variable's`.

### Task 5: `describe` читает графы

**Files:**
- Create: `packages/nanoflow_describe/lib/src/graphs.dart` (`part of 'extract.dart'`)
- Modify: `packages/nanoflow_describe/lib/src/extract.dart`
- Create: `packages/nanoflow_describe/test/fixtures/graphs/lib/graphs.dart`,
  `…/bin/main.dart`
- Test: `packages/nanoflow_describe/test/extract_test.dart`

**Interfaces:**
- Consumes: формат §6.1, `GraphFunction`/`GraphBody`/`EffectNode`/
  `ConditionNode`/`CallNode`/`GraphEdge`.
- Produces: в `Extracted.functions` — графы по id `путь#<переменная>`;
  `workflows` — и графы.

- [ ] **Step 1: Fixture** `test/fixtures/graphs/lib/graphs.dart`: ревью графом
  (как в спеке §2, с `Exit`, множеством и схождением), граф с
  перечислением в паре и `bool`, граф-узел внутри графа, функция воркфлоу
  узлом, функция, вызывающая граф `await review(f, x)`; `bin/main.dart` —
  `flow.run(review, …)`.
- [ ] **Step 2: Failing test** `reads graphs into bodies of effects, forks and calls`:
  ожидаемый JSON целиком для `review`: узлы `1 collect` (effect, place —
  строка переменной), `2 switch (collect)` (fork, place — строка карты), `3
  discard`, `4 inspect`, `5 switch (inspect)`, `6 publish`, `7 notify`, `8
  fix`, `9 report`; рёбра: `null→1`, `1→2`, `2→3 Empty`, `2→4 Found`,
  `4→5`, `5→6 Clean`, `5→7 Clean`, `5→8 Findings`, `8→4`, `6→9`, `7→9`,
  `3→null`, `9→null` (исчерпывающие карты — без `otherwise` в конец).
  Отдельные проверки: неисчерпывающая карта — ребро `otherwise` в конец;
  `otherwise:` — ребро с подписью `otherwise`; граф-узел и функция
  воркфлоу — `call` с их id, функция-узел без эффектов есть в `functions`;
  функция с `await review(f, x)` — в `functions`, в её теле `call`
  `['lib/graphs.dart#review']`; `workflows` содержит граф.
- [ ] **Step 3: Run** — FAIL.
- [ ] **Step 4: Implement** `graphs.dart`:
  - `_index` находит `TopLevelVariableDeclaration`, чей инициализатор —
    `InstanceCreationExpression` класса `Graph` из `package:nanoflow/`:
    `_GraphDeclaration(id, name, place, variable, creation)`; имя — литерал
    первого аргумента, иначе имя переменной и предупреждение.
  - Вызов графа (`review(f, x)`, `review.call(f, x)`) — цель вызова для
    `_callTargets` и `_findWithEffects`; аргумент `Flow.start/run/resume`,
    ссылающийся на граф (в том числе `ImplicitCallReference`), — воркфлоу.
  - `_GraphBody(package, declaration).build()` — обход списка кусков и
    цепочек `.next`; узлы по элементу, id по порядку появления; `fork`
    на каждую карту; рёбра выхода у узлов без стрелок и не в схождении;
    исчерпываемость — `bool`, перечисление, `sealed` (все неабстрактные
    подклассы среди ключей-типов), первое поле пары.
  - В `_extract`: тела графов строятся до функций (собирают функции
    воркфлоу-узлы в `drawn`); `bodies` — только функции.
- [ ] **Step 5: Run** `dart test` пакета — PASS.
- [ ] **Step 6: Commit** — `Draw a graph of nodes in the graph file with the nodes the UI already draws, so the UI shows it without a change`.

### Task 6: `describe` предупреждает о графе

**Files:**
- Modify: `packages/nanoflow_describe/lib/src/graphs.dart`
- Modify: fixture `warnings` или новая `graph_warnings`
- Test: `packages/nanoflow_describe/test/extract_test.dart`

- [ ] **Step 1: Failing test** — предупреждения с местом:
  `graph name is not a string literal`; `a graph outside a top-level
  variable is not drawn`; `graph part not drawn: <исходник>`; `graph node is
  not a top-level function, a static method or a graph: <исходник>`;
  `inspect takes Change, not the Report of fix`; `key Square never matches:
  switch (judge) takes Verdict`; `report takes (String, int), not the String
  of notify` (поле записи схождения).
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement:** тип выхода (`Future`/`FutureOr` снимаются,
  у графа — `O`), тип входа (первый параметр; у функции воркфлоу — второй;
  у графа — `I`), груз по правилам §5, `typeSystem.isAssignableTo`;
  `dynamic` и неизвестное не проверяются.
- [ ] **Step 4: Run** — PASS.
- [ ] **Step 5: Commit** — `Warn where a graph's arrows carry what their targets do not take, since the compiler cannot check a map of targets`.

### Task 7: Пример и e2e

**Files:**
- Create: `examples/review/lib/review_graph.dart`, `examples/review/bin/graph.dart`
- Modify: `examples/review/nanoflow.graph.json` (пишет `describe`),
  `examples/review/README.md`
- Test: `tests/e2e/test/review_example_test.dart` (граф до конца и
  продолжение после SIGKILL — как у функции)

- [ ] **Step 1:** граф ревью из тех же шагов, что `review.dart`
  (`collect`, `inspect` через `exec`, `fix`, `publish`, `notify`,
  `discard`), с выходами `Collected`/`Inspected` (`Exit`) и кодеками.
- [ ] **Step 2: Failing e2e test** — `bin/graph.dart <branch>` кончается
  кодом 0, сессия `finished`, эффекты по именам узлов; падение и `--resume`.
- [ ] **Step 3: Implement** `bin/graph.dart` (как `bin/main.dart`), файл
  графа — `dart run nanoflow_describe`.
- [ ] **Step 4: Run** e2e и `--check` — PASS.
- [ ] **Step 5: Commit** — `Show the review as a graph of nodes beside the function, and check it survives a crash as the function does`.

### Task 8: Документы

**Files:** `README.md`, `packages/nanoflow/README.md`,
`packages/nanoflow_describe/README.md`,
`docs/superpowers/specs/2026-10-03-code-first-design.md` (§4.1, §4.4, §6.1,
§7.1), `docs/superpowers/specs/2026-10-02-code-first-decisions.md`
(решение 14).

- [ ] **Step 1:** README — раздел «Граф из узлов» после «Пример»: код из
  спека §2, правила ветвления и схождения, ограничения; «Файл графа» —
  граф в `functions`; «Библиотека» — `addEnum`, граф в `start`.
- [ ] **Step 2:** README пакетов и code-first спек — те же правила по их
  разделам; журнал — решение 14 со ссылкой на дизайн и отвергнутым
  (выходы-именованные стрелки внутри узла, условие на связи, отдельный файл
  схемы).
- [ ] **Step 3:** `tool/ci.sh` — PASS.
- [ ] **Step 4: Commit** — `Document graphs of nodes where the workflow function is documented, so a reader finds both ways side by side`.

### Task 9: Итоговая проверка

- [ ] `tool/ci.sh` целиком — PASS.
- [ ] Ревью всей ветки свежим ревьюером (скилл `requesting-code-review`),
  исправления — отдельными коммитами.
