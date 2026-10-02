import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_ui/start/recent_graphs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const review = '/Users/me/Projects/review/review.yaml';
  const release = '/Users/me/work/deploy/release.yaml';
  const index = '/Users/me/sandbox/index.yaml';
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
      (path: review, openedAt: wednesday),
      (path: release, openedAt: tuesday),
      (path: index, openedAt: monday),
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
        (path: index, openedAt: wednesday),
        (path: release, openedAt: tuesday),
      ]);
    },
  );

  test('remove takes the graph off the list', () async {
    final recent = RecentGraphs(await preferences());
    await recent.opened(index, monday);
    await recent.opened(release, tuesday);
    await recent.remove(index);
    expect(recent.graphs, [(path: release, openedAt: tuesday)]);
  });

  test('the list is kept across restarts', () async {
    final prefs = await preferences();
    final recent = RecentGraphs(prefs);
    await recent.opened(index, monday);
    await recent.opened(release, tuesday);
    await recent.opened(review, wednesday);
    await recent.remove(release);
    expect(RecentGraphs(prefs).graphs, [
      (path: review, openedAt: wednesday),
      (path: index, openedAt: monday),
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
      '{"path": "/a.yaml"}',
      '[{"path": "/a.yaml"}]',
      '[{"path": "/a.yaml", "openedAt": "yesterday"}]',
    ]) {
      final recent = RecentGraphs(await preferences({'recentGraphs': stored}));
      expect(recent.graphs, isEmpty, reason: stored);
      await recent.opened(index, monday);
      expect(recent.graphs, [(path: index, openedAt: monday)]);
    }
  });
}
