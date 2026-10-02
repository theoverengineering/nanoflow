// Graphs that compile but do not build.
import 'package:nanoflow/nanoflow.dart';

import 'twin_a.dart' as a;
import 'twin_b.dart' as b;

final first = node((Object? x) {});
final second = node((Object? x) {});
final third = node((Object? x) {});
final check = fork((Object? x) => true);
final choose = fork((Object? x) => 'left');

final noStart = Graph([Graph.part(first).next(second)]);

final nextTwice = Graph([
  Graph.start(first).next(second),
  Graph.part(first).next(third),
]);

final thenTwice = Graph.start(check).then(first).then(second);

final otherwiseTwice = Graph([
  Graph.start(check).otherwise(first),
  Graph.part(check).otherwise(second),
]);

final outcomeTwice = Graph([
  Graph.start(choose).then({'left': first}),
  Graph.part(choose).then({'right': second, 'left': third}),
]);

final notTopLevel = Graph.start(first).next(node((Object? x) {}));

final held = node((Object? x) {});
final alsoHeld = held;
final heldTwice = Graph.start(held);

final sameName = Graph([Graph.start(a.twin), Graph.start(b.twin)]);

final severalErrors = Graph([
  Graph.part(first).next(second),
  Graph.part(first).next(third),
]);

final lost = node((Object? x) {});

/// A part that no arrow leads to, as a refactoring that drops the only
/// arrow to it leaves one: its nodes are unreachable, while `second`, which
/// a start leads to as well, is not.
final unreachable = Graph([
  Graph.start(first).next(second),
  Graph.part(third).next(check).then(second).otherwise(lost),
  Graph.part(lost).next(third),
]);

class Opaque {}

class OnlyFromJson {
  OnlyFromJson.fromJson(Object? json);
}

/// Its toJson is static: a value has none to call.
class OnlyStaticToJson {
  OnlyStaticToJson.fromJson(Object? json);

  static Object? toJson(OnlyStaticToJson value) => null;
}

final takesSet = node((Set<int> s) {});
final givesOpaque = node((Object? x) => Opaque());
final takesOnlyFromJson = node((OnlyFromJson o) {});
final takesOnlyStaticToJson = node((OnlyStaticToJson o) {});
final takesIntKeys = node((Map<int, String> m) {});
final takesAnyList = node((List<dynamic> l) {});

final unsupported = Graph([
  Graph.start(takesSet),
  Graph.start(givesOpaque),
  Graph.start(takesOnlyFromJson),
  Graph.start(takesOnlyStaticToJson),
  Graph.start(takesIntKeys),
  Graph.start(takesAnyList),
]);

class Report {
  Report.fromJson(Object? json);

  Object? toJson() => null;
}

final takesNullable = node((Report? r) {});
final givesNullable = node((Object? x) async => x is String ? x : null);
final decidesOnNullable = fork((String? s) => s == null);
final takesNullableItems = node((List<String?> l) {});
final givesNullableValues = node((Object? x) => <String, List<int?>>{});
final takesObject = node((Object o) {});
final givesObject = node((Object? x) => Object());

final nullable = Graph([
  Graph.start(takesNullable),
  Graph.start(givesNullable),
  Graph.start(decidesOnNullable),
  Graph.start(takesNullableItems),
  Graph.start(givesNullableValues),
  Graph.start(takesObject),
  Graph.start(givesObject),
]);
