import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_ui/start/recent_graphs.dart';
import 'package:nanoflow_ui/state/store_place.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const review = '/Users/me/Projects/review/nanoflow.graph.json';
  const release = '/Users/me/work/deploy/nanoflow.graph.json';
  const index = '/Users/me/sandbox/nanoflow.graph.json';
  final monday = DateTime.utc(2026, 9, 21, 9);
  final tuesday = DateTime.utc(2026, 9, 22, 9);
  final wednesday = DateTime.utc(2026, 9, 23, 9);

  Future<SharedPreferences> preferences([
    Map<String, Object> stored = const {},
  ]) async {
    SharedPreferences.setMockInitialValues(stored);
    return SharedPreferences.getInstance();
  }

  test('nothing opened yet is an empty list', () async {
    expect(RecentGraphs(await preferences()).graphs, isEmpty);
  });

  test('the newest opened graph is on top', () async {
    final recent = RecentGraphs(await preferences());
    await recent.opened(index, monday);
    await recent.opened(release, tuesday);
    await recent.opened(review, wednesday);
    expect(recent.graphs, [
      (path: review, store: null, openedAt: wednesday),
      (path: release, store: null, openedAt: tuesday),
      (path: index, store: null, openedAt: monday),
    ]);
  });

  test(
    'opening a listed graph moves it to the top with the new time',
    () async {
      final recent = RecentGraphs(await preferences());
      await recent.opened(index, monday);
      await recent.opened(release, tuesday);
      await recent.opened(index, wednesday);
      expect(recent.graphs, [
        (path: index, store: null, openedAt: wednesday),
        (path: release, store: null, openedAt: tuesday),
      ]);
    },
  );

  test('remove takes the graph off the list', () async {
    final recent = RecentGraphs(await preferences());
    await recent.opened(index, monday);
    await recent.opened(release, tuesday);
    await recent.remove(index);
    expect(recent.graphs, [(path: release, store: null, openedAt: tuesday)]);
  });

  test('the list is kept across restarts', () async {
    final prefs = await preferences();
    final recent = RecentGraphs(prefs);
    await recent.opened(index, monday);
    await recent.opened(release, tuesday);
    await recent.opened(review, wednesday);
    await recent.remove(release);
    expect(RecentGraphs(prefs).graphs, [
      (path: review, store: null, openedAt: wednesday),
      (path: index, store: null, openedAt: monday),
    ]);
  });

  test('changes are announced as soon as they are made', () async {
    final recent = RecentGraphs(await preferences());
    final seen = <List<String>>[];
    recent.addListener(() => seen.add([for (final g in recent.graphs) g.path]));
    final opening = recent.opened(index, monday);
    expect(seen, [
      [index],
    ]);
    await opening;
    await recent.remove(index);
    expect(seen, [
      [index],
      <String>[],
    ]);
  });

  test('a stored list that cannot be read starts empty', () async {
    for (final stored in [
      'not json',
      '{"path": "/a/nanoflow.graph.json"}',
      '[{"path": "/a/nanoflow.graph.json"}]',
      '[{"path": "/a/nanoflow.graph.json", "openedAt": "yesterday"}]',
      '[{"path": 1, "openedAt": "2026-09-21T09:00:00.000Z"}]',
    ]) {
      final recent = RecentGraphs(await preferences({'recentGraphs': stored}));
      expect(recent.graphs, isEmpty, reason: stored);
      await recent.opened(index, monday);
      expect(recent.graphs, [(path: index, store: null, openedAt: monday)]);
    }
  });

  test('graphs opened before graph files were JSON are not listed', () async {
    final prefs = await preferences({
      'recentGraphs':
          '[{"path": "/Users/me/review.yaml", '
          '"openedAt": "2026-09-21T09:00:00.000Z"}, '
          '{"path": "$review", "openedAt": "2026-09-22T09:00:00.000Z"}]',
    });
    expect(RecentGraphs(prefs).graphs, [
      (path: review, store: null, openedAt: tuesday),
    ]);
  });

  test('keeps the store a graph was opened with: each graph with each store '
      'once, read back as saved', () async {
    final prefs = await preferences();
    final recent = RecentGraphs(prefs);
    const ideas = StorePlace.sqlite('/Users/me/.ideaforge/ideas.db');

    await recent.opened(review, monday);
    await recent.opened(review, tuesday, store: ideas);
    await recent.opened(review, wednesday, store: ideas);

    final listed = [
      (path: review, store: ideas, openedAt: wednesday),
      (path: review, store: null, openedAt: monday),
    ];
    expect(recent.graphs, listed);
    expect(RecentGraphs(prefs).graphs, listed);

    await recent.remove(review, store: ideas);
    expect(recent.graphs, [(path: review, store: null, openedAt: monday)]);
  });

  test('a graph file is named *.graph.json', () {
    expect(isGraphFile(review), isTrue);
    expect(isGraphFile('/Users/me/build/review.graph.json'), isTrue);
    expect(isGraphFile('/Users/me/review.yaml'), isFalse);
    expect(isGraphFile('/Users/me/package.json'), isFalse);
    expect(isGraphFile('/Users/me/graph.json'), isFalse);
  });

  test('a list that cannot be saved is reported and still shown', () async {
    final reported = <FlutterErrorDetails>[];
    final onError = FlutterError.onError;
    FlutterError.onError = reported.add;
    addTearDown(() => FlutterError.onError = onError);
    final recent = RecentGraphs(_UnwritablePreferences());

    await recent.opened(index, monday);
    await recent.remove(index);
    await recent.opened(review, tuesday);

    expect(recent.graphs, [(path: review, store: null, openedAt: tuesday)]);
    expect(reported, hasLength(3));
    expect(reported.first.exception, isA<StateError>());
    expect(
      reported.first.context.toString(),
      contains('saving the recently opened graphs'),
    );
  });
}

/// Preferences whose writes fail, as a full disk would make them.
class _UnwritablePreferences implements SharedPreferences {
  @override
  String? getString(String key) => null;

  @override
  Future<bool> setString(String key, String value) async =>
      throw StateError('disk full');

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
