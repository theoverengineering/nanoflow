import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_ui/start/launch.dart';
import 'package:nanoflow_ui/state/store_place.dart';

const _graph = '/Users/me/ideaforge/packages/ideas_flow/nanoflow.graph.json';

void main() {
  group('parseLaunch', () {
    test('no arguments: the start screen', () {
      expect(parseLaunch(const []), isNull);
    });

    test(
      'a graph file alone: its sessions next to it, the newest selected',
      () {
        expect(parseLaunch(const [_graph]), (
          path: _graph,
          store: null,
          session: null,
          currentGraph: false,
        ));
      },
    );

    test('a graph file with a store and a session', () {
      expect(
        parseLaunch(const [
          _graph,
          '--store',
          'sqlite:~/.ideaforge/ideas.db',
          '--session',
          '3f1c2e0a-7a4b-4c1d-9e2f-5a6b7c8d9e0f',
        ], home: '/Users/me'),
        (
          path: _graph,
          store: const StorePlace.sqlite('/Users/me/.ideaforge/ideas.db'),
          session: '3f1c2e0a-7a4b-4c1d-9e2f-5a6b7c8d9e0f',
          currentGraph: false,
        ),
      );
    });

    test('a graph file on Current graph, not on a session', () {
      expect(
        parseLaunch(const [
          _graph,
          '--store',
          'sqlite:/d/ideas.db',
          '--current-graph',
        ])?.currentGraph,
        isTrue,
      );
    });

    test('leaves out what macOS and Xcode add', () {
      expect(
        parseLaunch(const [
          '-psn_0_12345',
          '-NSDocumentRevisionsDebugMode',
          'YES',
          _graph,
        ])?.path,
        _graph,
      );
    });

    test('says what is wrong', () {
      for (final (args, says) in [
        (const ['--store', 'fs:/runs'], 'need a graph file'),
        (const [_graph, '--store'], '--store needs a value'),
        (const [_graph, '--store', 'mysql:/db'], 'unknown store "mysql"'),
        (const [_graph, '--verbose'], 'unknown option --verbose'),
        (const ['/a/notes.json'], 'is not a graph file'),
        (const [_graph, _graph], 'one graph file only'),
        (
          const [_graph, '--session', 's1', '--current-graph'],
          '--session or --current-graph',
        ),
        (const ['--current-graph'], 'need a graph file'),
      ]) {
        expect(
          () => parseLaunch(args),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains(says),
            ),
          ),
          reason: '$args',
        );
      }
    });
  });

  group('StorePlace', () {
    test('reads fs: and sqlite:, ~ as the home directory', () {
      expect(
        StorePlace.parse('fs:~/p/runs', home: '/Users/me'),
        const StorePlace.files('/Users/me/p/runs'),
      );
      expect(
        StorePlace.parse('sqlite:/var/db/../app.db'),
        const StorePlace.sqlite('/var/app.db'),
      );
    });

    test('is written back as it is read', () {
      const place = StorePlace.sqlite('/Users/me/.ideaforge/ideas.db');
      expect('$place', 'sqlite:/Users/me/.ideaforge/ideas.db');
      expect(StorePlace.parse('$place'), place);
    });

    test('needs a scheme and a path', () {
      for (final text in ['/Users/me/runs', 'sqlite:']) {
        expect(() => StorePlace.parse(text), throwsFormatException);
      }
    });

    test('is named in the header by its directory or database file', () {
      expect(const StorePlace.files('/p/runs').name, 'runs/');
      expect(
        const StorePlace.sqlite('/u/.ideaforge/ideas.db').name,
        'ideas.db',
      );
    });

    test('next to a graph file is runs/ there', () {
      expect(
        StorePlace.nextTo('/p/nanoflow.graph.json'),
        const StorePlace.files('/p/runs'),
      );
    });
  });
}
