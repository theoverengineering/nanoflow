import 'dart:convert';
import 'dart:io';

import 'package:nanoflow_describe/nanoflow_describe.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A fixture package under `test/fixtures/`: `lib/`, `bin/`, no pubspec.
String fixture(String name) => p.join('test', 'fixtures', name);

/// The graph file of the fixture [name], whose package is called [name].
Future<Map<String, Object?>> describeFixture(String name) async {
  final result = await describePackage(fixture(name), packageName: name);
  expect(result.errors, isEmpty);
  return result.graph!.toJson();
}

/// The graph file the fixture [name] must give: its sources hashed as the
/// model hashes them, nothing built, the rest as given.
Future<Map<String, Object?>> expectedFile(
  String name, {
  required List<String> workflows,
  required Map<String, Object?> functions,
  List<Object?> warnings = const [],
}) async {
  final dir = fixture(name);
  final sources = await hashSources(dir, await packageSourcePaths(dir));
  return {
    'format': 1,
    'package': name,
    'fingerprint': fingerprintOf(sources),
    'sources': sources,
    'builds': <String, Object?>{},
    'workflows': workflows,
    'functions': functions,
    'warnings': warnings,
  };
}

/// [actual] equals [expected], keys in the same order: the file is written
/// as it iterates.
void expectFile(Map<String, Object?> actual, Map<String, Object?> expected) {
  expect(actual, expected);
  expect(jsonEncode(actual), jsonEncode(expected));
}

void main() {
  test('reads the README review graph from an ordinary function', () async {
    final graph = await describeFixture('review');
    expect((graph['sources']! as Map).keys, [
      'bin/main.dart',
      'lib/review.dart',
    ]);
    expectFile(
      graph,
      await expectedFile(
        'review',
        workflows: ['lib/review.dart#review'],
        functions: {
          'lib/review.dart#review': {
            'name': 'review',
            'place': 'lib/review.dart:35',
            'body': {
              'nodes': [
                {
                  'id': '1',
                  'kind': 'step',
                  'name': 'collect',
                  'place': 'lib/review.dart:36',
                },
                {
                  'id': '2',
                  'kind': 'fork',
                  'label': 'change.path.isEmpty',
                  'place': 'lib/review.dart:37',
                },
                {
                  'id': '3',
                  'kind': 'step',
                  'name': 'discard',
                  'place': 'lib/review.dart:38',
                },
                {
                  'id': '4',
                  'kind': 'step',
                  'name': 'inspect',
                  'place': 'lib/review.dart:42',
                },
                {
                  'id': '5',
                  'kind': 'fork',
                  'label': 'report.findings.isEmpty',
                  'place': 'lib/review.dart:43',
                },
                {
                  'id': '6',
                  'kind': 'step',
                  'name': 'publish',
                  'place': 'lib/review.dart:45',
                },
                {
                  'id': '7',
                  'kind': 'step',
                  'name': 'notify',
                  'place': 'lib/review.dart:46',
                },
                {
                  'id': '8',
                  'kind': 'step',
                  'name': 'fix',
                  'place': 'lib/review.dart:50',
                },
              ],
              'edges': [
                {'from': null, 'to': '1', 'label': null},
                {'from': '1', 'to': '2', 'label': null},
                {'from': '2', 'to': '3', 'label': 'true'},
                {'from': '2', 'to': '4', 'label': 'false'},
                {'from': '3', 'to': null, 'label': null},
                {'from': '4', 'to': '5', 'label': null},
                // publish and notify side by side: two edges, one label.
                {'from': '5', 'to': '6', 'label': 'true'},
                {'from': '5', 'to': '7', 'label': 'true'},
                {'from': '5', 'to': '8', 'label': 'false'},
                {'from': '6', 'to': null, 'label': null},
                {'from': '7', 'to': null, 'label': null},
                // while (true) is no fork: fix goes straight back.
                {'from': '8', 'to': '4', 'label': null},
              ],
            },
          },
        },
      ),
    );
  });

  test('draws a loop over data, a call and a switch on an enum', () async {
    expectFile(
      await describeFixture('release'),
      await expectedFile(
        'release',
        // Passed to both Flow.start and Flow.resume: listed once.
        workflows: ['lib/release.dart#release'],
        functions: {
          'lib/publish.dart#publish': {
            'name': 'publish',
            'place': 'lib/publish.dart:11',
            'body': {
              'nodes': [
                {
                  'id': '1',
                  'kind': 'step',
                  'name': 'upload',
                  'place': 'lib/publish.dart:12',
                },
                {
                  'id': '2',
                  'kind': 'step',
                  'name': 'verify',
                  'place': 'lib/publish.dart:13',
                },
                {
                  'id': '3',
                  'kind': 'fork',
                  'label': '!ok',
                  'place': 'lib/publish.dart:14',
                },
                {
                  'id': '4',
                  'kind': 'step',
                  'name': 'rollback',
                  'place': 'lib/publish.dart:14',
                },
              ],
              'edges': [
                {'from': null, 'to': '1', 'label': null},
                {'from': '1', 'to': '2', 'label': null},
                {'from': '2', 'to': '3', 'label': null},
                {'from': '3', 'to': '4', 'label': 'true'},
                {'from': '3', 'to': null, 'label': 'false'},
                {'from': '4', 'to': null, 'label': null},
              ],
            },
          },
          'lib/release.dart#release': {
            'name': 'release',
            'place': 'lib/release.dart:15',
            'body': {
              'nodes': [
                {
                  'id': '1',
                  'kind': 'step',
                  'name': 'plan',
                  'place': 'lib/release.dart:16',
                },
                {
                  'id': '2',
                  'kind': 'fork',
                  'label': 'for pkg in plan.packages',
                  'place': 'lib/release.dart:17',
                },
                {
                  'id': '3',
                  'kind': 'step',
                  'name': 'build',
                  'place': 'lib/release.dart:18',
                },
                {
                  'id': '4',
                  'kind': 'fork',
                  'label': 'pkg.isPublic',
                  'place': 'lib/release.dart:19',
                },
                {
                  'id': '5',
                  'kind': 'call',
                  'functions': ['lib/publish.dart#publish'],
                  'place': 'lib/release.dart:19',
                },
                {
                  'id': '6',
                  'kind': 'fork',
                  'label': 'switch (plan.channel)',
                  'place': 'lib/release.dart:21',
                },
                {
                  'id': '7',
                  'kind': 'step',
                  'name': 'announce',
                  'place': 'lib/release.dart:23',
                },
                {
                  'id': '8',
                  'kind': 'step',
                  'name': 'notify-testers',
                  'place': 'lib/release.dart:26',
                },
              ],
              'edges': [
                {'from': null, 'to': '1', 'label': null},
                {'from': '1', 'to': '2', 'label': null},
                {'from': '2', 'to': '3', 'label': 'each'},
                {'from': '2', 'to': '6', 'label': 'done'},
                {'from': '3', 'to': '4', 'label': null},
                {'from': '4', 'to': '5', 'label': 'true'},
                // Every way out of the loop body goes back to the loop.
                {'from': '4', 'to': '2', 'label': 'false'},
                {'from': '5', 'to': '2', 'label': null},
                // Every value of the enum has a case: no default.
                {'from': '6', 'to': '7', 'label': 'Channel.stable'},
                {'from': '6', 'to': '8', 'label': 'Channel.beta'},
                {'from': '6', 'to': '8', 'label': 'Channel.dev'},
                {'from': '7', 'to': null, 'label': null},
                {'from': '8', 'to': null, 'label': null},
              ],
            },
          },
        },
      ),
    );
  });

  test('draws copies side by side written in place, and a loop', () async {
    expectFile(
      await describeFixture('inline'),
      await expectedFile(
        'inline',
        workflows: [
          'lib/inline.dart#inPlace',
          'lib/inline.dart#sequential',
          'lib/inline.dart#viaCall',
          'lib/inline.dart#viaMap',
        ],
        functions: {
          // A for element whose body is an async closure called in place.
          'lib/inline.dart#inPlace': {
            'name': 'inPlace',
            'place': 'lib/inline.dart:6',
            'body': {
              'nodes': [
                {
                  'id': '1',
                  'kind': 'copies',
                  'label': 'pkg in packages',
                  'place': 'lib/inline.dart:8',
                  'body': {
                    'nodes': [
                      {
                        'id': '1',
                        'kind': 'step',
                        'name': 'upload',
                        'place': 'lib/inline.dart:10',
                      },
                      {
                        'id': '2',
                        'kind': 'step',
                        'name': 'verify',
                        'place': 'lib/inline.dart:11',
                      },
                      {
                        'id': '3',
                        'kind': 'step',
                        'name': 'tag',
                        'place': 'lib/inline.dart:12',
                      },
                    ],
                    'edges': [
                      {'from': null, 'to': '1', 'label': null},
                      {'from': '1', 'to': '2', 'label': null},
                      {'from': '2', 'to': '3', 'label': null},
                      {'from': '3', 'to': null, 'label': null},
                    ],
                  },
                },
                {
                  'id': '2',
                  'kind': 'step',
                  'name': 'announce',
                  'place': 'lib/inline.dart:15',
                },
              ],
              'edges': [
                {'from': null, 'to': '1', 'label': null},
                // All copies done: one edge on.
                {'from': '1', 'to': '2', 'label': null},
                {'from': '2', 'to': null, 'label': null},
              ],
            },
          },
          'lib/inline.dart#publish': {
            'name': 'publish',
            'place': 'lib/inline.dart:46',
            'body': {
              'nodes': [
                {
                  'id': '1',
                  'kind': 'step',
                  'name': 'upload',
                  'place': 'lib/inline.dart:47',
                },
                {
                  'id': '2',
                  'kind': 'step',
                  'name': 'verify',
                  'place': 'lib/inline.dart:48',
                },
                {
                  'id': '3',
                  'kind': 'step',
                  'name': 'tag',
                  'place': 'lib/inline.dart:49',
                },
              ],
              'edges': [
                {'from': null, 'to': '1', 'label': null},
                {'from': '1', 'to': '2', 'label': null},
                {'from': '2', 'to': '3', 'label': null},
                {'from': '3', 'to': null, 'label': null},
              ],
            },
          },
          // An ordinary for: one package after another.
          'lib/inline.dart#sequential': {
            'name': 'sequential',
            'place': 'lib/inline.dart:36',
            'body': {
              'nodes': [
                {
                  'id': '1',
                  'kind': 'fork',
                  'label': 'for pkg in packages',
                  'place': 'lib/inline.dart:38',
                },
                {
                  'id': '2',
                  'kind': 'step',
                  'name': 'upload',
                  'place': 'lib/inline.dart:39',
                },
                {
                  'id': '3',
                  'kind': 'step',
                  'name': 'verify',
                  'place': 'lib/inline.dart:40',
                },
                {
                  'id': '4',
                  'kind': 'step',
                  'name': 'tag',
                  'place': 'lib/inline.dart:41',
                },
                {
                  'id': '5',
                  'kind': 'step',
                  'name': 'announce',
                  'place': 'lib/inline.dart:43',
                },
              ],
              'edges': [
                {'from': null, 'to': '1', 'label': null},
                {'from': '1', 'to': '2', 'label': 'each'},
                {'from': '1', 'to': '5', 'label': 'done'},
                {'from': '2', 'to': '3', 'label': null},
                {'from': '3', 'to': '4', 'label': null},
                {'from': '4', 'to': '1', 'label': null},
                {'from': '5', 'to': null, 'label': null},
              ],
            },
          },
          // A for element whose body is a call: a body of one call node.
          'lib/inline.dart#viaCall': {
            'name': 'viaCall',
            'place': 'lib/inline.dart:29',
            'body': {
              'nodes': [
                {
                  'id': '1',
                  'kind': 'copies',
                  'label': 'pkg in packages',
                  'place': 'lib/inline.dart:31',
                  'body': {
                    'nodes': [
                      {
                        'id': '1',
                        'kind': 'call',
                        'functions': ['lib/inline.dart#publish'],
                        'place': 'lib/inline.dart:31',
                      },
                    ],
                    'edges': [
                      {'from': null, 'to': '1', 'label': null},
                      {'from': '1', 'to': null, 'label': null},
                    ],
                  },
                },
                {
                  'id': '2',
                  'kind': 'step',
                  'name': 'announce',
                  'place': 'lib/inline.dart:33',
                },
              ],
              'edges': [
                {'from': null, 'to': '1', 'label': null},
                // All copies done: one edge on.
                {'from': '1', 'to': '2', 'label': null},
                {'from': '2', 'to': null, 'label': null},
              ],
            },
          },
          // map with an async closure.
          'lib/inline.dart#viaMap': {
            'name': 'viaMap',
            'place': 'lib/inline.dart:18',
            'body': {
              'nodes': [
                {
                  'id': '1',
                  'kind': 'copies',
                  'label': 'pkg in packages',
                  'place': 'lib/inline.dart:20',
                  'body': {
                    'nodes': [
                      {
                        'id': '1',
                        'kind': 'step',
                        'name': 'upload',
                        'place': 'lib/inline.dart:21',
                      },
                      {
                        'id': '2',
                        'kind': 'step',
                        'name': 'verify',
                        'place': 'lib/inline.dart:22',
                      },
                      {
                        'id': '3',
                        'kind': 'step',
                        'name': 'tag',
                        'place': 'lib/inline.dart:23',
                      },
                    ],
                    'edges': [
                      {'from': null, 'to': '1', 'label': null},
                      {'from': '1', 'to': '2', 'label': null},
                      {'from': '2', 'to': '3', 'label': null},
                      {'from': '3', 'to': null, 'label': null},
                    ],
                  },
                },
                {
                  'id': '2',
                  'kind': 'step',
                  'name': 'announce',
                  'place': 'lib/inline.dart:26',
                },
              ],
              'edges': [
                {'from': null, 'to': '1', 'label': null},
                // All copies done: one edge on.
                {'from': '1', 'to': '2', 'label': null},
                {'from': '2', 'to': null, 'label': null},
              ],
            },
          },
        },
      ),
    );
  });

  test(
    'calls every implementation of an interface method that has steps',
    () async {
      expectFile(
        await describeFixture('interfaces'),
        await expectedFile(
          'interfaces',
          workflows: ['lib/deploy.dart#deploy'],
          // QuietNotifier.notify takes no step: not a function with steps.
          functions: {
            'lib/deploy.dart#ChatNotifier.notify': {
              'name': 'notify',
              'place': 'lib/deploy.dart:11',
              'body': {
                'nodes': [
                  {
                    'id': '1',
                    'kind': 'step',
                    'name': 'post',
                    'place': 'lib/deploy.dart:12',
                  },
                ],
                'edges': [
                  {'from': null, 'to': '1', 'label': null},
                  {'from': '1', 'to': null, 'label': null},
                ],
              },
            },
            'lib/deploy.dart#MailNotifier.notify': {
              'name': 'notify',
              'place': 'lib/deploy.dart:18',
              'body': {
                'nodes': [
                  {
                    'id': '1',
                    'kind': 'step',
                    'name': 'find-owners',
                    'place': 'lib/deploy.dart:19',
                  },
                  {
                    'id': '2',
                    'kind': 'step',
                    'name': 'send-mail',
                    'place': 'lib/deploy.dart:20',
                  },
                ],
                'edges': [
                  {'from': null, 'to': '1', 'label': null},
                  {'from': '1', 'to': '2', 'label': null},
                  {'from': '2', 'to': null, 'label': null},
                ],
              },
            },
            'lib/deploy.dart#deploy': {
              'name': 'deploy',
              'place': 'lib/deploy.dart:30',
              'body': {
                'nodes': [
                  {
                    'id': '1',
                    'kind': 'step',
                    'name': 'roll-out',
                    'place': 'lib/deploy.dart:31',
                  },
                  {
                    'id': '2',
                    'kind': 'call',
                    'functions': [
                      'lib/deploy.dart#ChatNotifier.notify',
                      'lib/deploy.dart#MailNotifier.notify',
                    ],
                    'place': 'lib/deploy.dart:32',
                  },
                ],
                'edges': [
                  {'from': null, 'to': '1', 'label': null},
                  {'from': '1', 'to': '2', 'label': null},
                  {'from': '2', 'to': null, 'label': null},
                ],
              },
            },
          },
        ),
      );
    },
  );

  test('draws a recursive call as a call to the same function', () async {
    expectFile(
      await describeFixture('recursion'),
      await expectedFile(
        'recursion',
        workflows: ['lib/crawl.dart#crawl', 'lib/crawl.dart#deploy'],
        // backoff calls itself but takes no step: not a function with steps.
        functions: {
          'lib/crawl.dart#crawl': {
            'name': 'crawl',
            'place': 'lib/crawl.dart:22',
            'body': {
              'nodes': [
                {
                  'id': '1',
                  'kind': 'step',
                  'name': 'fetch',
                  'place': 'lib/crawl.dart:23',
                },
                {
                  'id': '2',
                  'kind': 'fork',
                  'label': 'for link in links',
                  'place': 'lib/crawl.dart:24',
                },
                {
                  'id': '3',
                  'kind': 'call',
                  'functions': ['lib/crawl.dart#visit'],
                  'place': 'lib/crawl.dart:25',
                },
              ],
              'edges': [
                {'from': null, 'to': '1', 'label': null},
                {'from': '1', 'to': '2', 'label': null},
                {'from': '2', 'to': '3', 'label': 'each'},
                {'from': '2', 'to': null, 'label': 'done'},
                {'from': '3', 'to': '2', 'label': null},
              ],
            },
          },
          'lib/crawl.dart#deploy': {
            'name': 'deploy',
            'place': 'lib/crawl.dart:6',
            'body': {
              'nodes': [
                {
                  'id': '1',
                  'kind': 'step',
                  'name': 'try-deploy',
                  'place': 'lib/crawl.dart:7',
                },
                {
                  'id': '2',
                  'kind': 'fork',
                  'label': '!ok',
                  'place': 'lib/crawl.dart:8',
                },
                {
                  'id': '3',
                  'kind': 'call',
                  'functions': ['lib/crawl.dart#deploy'],
                  'place': 'lib/crawl.dart:10',
                },
              ],
              'edges': [
                {'from': null, 'to': '1', 'label': null},
                {'from': '1', 'to': '2', 'label': null},
                {'from': '2', 'to': '3', 'label': 'true'},
                {'from': '2', 'to': null, 'label': 'false'},
                {'from': '3', 'to': null, 'label': null},
              ],
            },
          },
          // No step of its own: a function with steps through crawl.
          'lib/crawl.dart#visit': {
            'name': 'visit',
            'place': 'lib/crawl.dart:31',
            'body': {
              'nodes': [
                {
                  'id': '1',
                  'kind': 'fork',
                  'label': "url.endsWith('/')",
                  'place': 'lib/crawl.dart:32',
                },
                {
                  'id': '2',
                  'kind': 'call',
                  'functions': ['lib/crawl.dart#crawl'],
                  'place': 'lib/crawl.dart:32',
                },
              ],
              'edges': [
                {'from': null, 'to': '1', 'label': null},
                {'from': '1', 'to': '2', 'label': 'true'},
                {'from': '1', 'to': null, 'label': 'false'},
                {'from': '2', 'to': null, 'label': null},
              ],
            },
          },
        },
      ),
    );
  });

  test('warns where it cannot draw, at the place in the code', () async {
    final graph = await describeFixture('warnings');
    // other/ is not under lib/ or bin/: not a source.
    expect((graph['sources']! as Map).keys, [
      'bin/main.dart',
      'lib/migrate.dart',
    ]);
    expectFile(
      graph,
      await expectedFile(
        'warnings',
        workflows: ['lib/migrate.dart#check', 'lib/migrate.dart#migrate'],
        functions: {
          // A workflow has a graph even when none of its steps can be
          // drawn: the body is left as it is entered.
          'lib/migrate.dart#check': {
            'name': 'check',
            'place': 'lib/migrate.dart:26',
            'body': {
              'nodes': <Object?>[],
              'edges': [
                {'from': null, 'to': null, 'label': null},
              ],
            },
          },
          'lib/migrate.dart#migrate': {
            'name': 'migrate',
            'place': 'lib/migrate.dart:8',
            'body': {
              'nodes': [
                {
                  'id': '1',
                  'kind': 'fork',
                  'label': 'for table in tables',
                  'place': 'lib/migrate.dart:9',
                },
                {
                  'id': '2',
                  'kind': 'step',
                  'name': r"'copy-$table'",
                  'place': 'lib/migrate.dart:10',
                },
                {
                  'id': '3',
                  'kind': 'step',
                  'name': 'switch-over',
                  'place': 'lib/migrate.dart:18',
                },
              ],
              'edges': [
                {'from': null, 'to': '1', 'label': null},
                {'from': '1', 'to': '2', 'label': 'each'},
                {'from': '1', 'to': '3', 'label': 'done'},
                {'from': '2', 'to': '1', 'label': null},
                {'from': '3', 'to': null, 'label': null},
              ],
            },
          },
        },
        warnings: [
          {
            'place': 'lib/migrate.dart:10',
            'message': 'step name is not a string literal',
          },
          {
            'place': 'lib/migrate.dart:12',
            'message': 'steps in a local function are not drawn',
          },
          {
            'place': 'lib/migrate.dart:19',
            'message': 'catch clauses are not drawn',
          },
          {
            'place': 'lib/migrate.dart:22',
            'message':
                'steps of notifyTeam are not drawn: '
                'it is outside the package sources',
          },
          {
            'place': 'lib/migrate.dart:27',
            'message': 'steps in a closure passed on are not drawn',
          },
        ],
      ),
    );
  });

  test('draws the rest of the control flow and leaves out what decides '
      'nothing', () async {
    expectFile(
      await describeFixture('control'),
      await expectedFile(
        'control',
        workflows: [],
        functions: {
          // A switch with no default: the flow goes on after it when no case
          // matches.
          'lib/backup.dart#compress': {
            'name': 'compress',
            'place': 'lib/backup.dart:28',
            'body': {
              'nodes': [
                {
                  'id': '1',
                  'kind': 'fork',
                  'label': 'switch (format)',
                  'place': 'lib/backup.dart:29',
                },
                {
                  'id': '2',
                  'kind': 'step',
                  'name': 'zip',
                  'place': 'lib/backup.dart:31',
                },
                {
                  'id': '3',
                  'kind': 'step',
                  'name': 'tar',
                  'place': 'lib/backup.dart:33',
                },
                {
                  'id': '4',
                  'kind': 'step',
                  'name': 'checksum',
                  'place': 'lib/backup.dart:35',
                },
              ],
              'edges': [
                {'from': null, 'to': '1', 'label': null},
                {'from': '1', 'to': '2', 'label': "'zip'"},
                {'from': '1', 'to': '3', 'label': "'tar'"},
                {'from': '1', 'to': '4', 'label': 'default'},
                {'from': '2', 'to': '4', 'label': null},
                {'from': '3', 'to': '4', 'label': null},
                {'from': '4', 'to': null, 'label': null},
              ],
            },
          },
          // ?:, then || whose right side is an && with a step on its right.
          'lib/backup.dart#report': {
            'name': 'report',
            'place': 'lib/backup.dart:67',
            'body': {
              'nodes': [
                {
                  'id': '1',
                  'kind': 'fork',
                  'label': 'quiet',
                  'place': 'lib/backup.dart:68',
                },
                {
                  'id': '2',
                  'kind': 'step',
                  'name': 'summarize',
                  'place': 'lib/backup.dart:68',
                },
                {
                  'id': '3',
                  'kind': 'fork',
                  'label': 'urgent',
                  'place': 'lib/backup.dart:69',
                },
                {
                  'id': '4',
                  'kind': 'fork',
                  'label': 'text.isNotEmpty',
                  'place': 'lib/backup.dart:69',
                },
                {
                  'id': '5',
                  'kind': 'step',
                  'name': 'ask',
                  'place': 'lib/backup.dart:69',
                },
                {
                  'id': '6',
                  'kind': 'fork',
                  'label':
                      'urgent || text.isNotEmpty && '
                      "await f.step('ask', () => true)",
                  'place': 'lib/backup.dart:69',
                },
                {
                  'id': '7',
                  'kind': 'step',
                  'name': 'mail',
                  'place': 'lib/backup.dart:70',
                },
              ],
              'edges': [
                {'from': null, 'to': '1', 'label': null},
                {'from': '1', 'to': '2', 'label': 'false'},
                {'from': '1', 'to': '3', 'label': 'true'},
                {'from': '2', 'to': '3', 'label': null},
                // || evaluates its right side when the left is false.
                {'from': '3', 'to': '4', 'label': 'false'},
                {'from': '3', 'to': '6', 'label': 'true'},
                // && evaluates its right side when the left is true.
                {'from': '4', 'to': '5', 'label': 'true'},
                {'from': '4', 'to': '6', 'label': 'false'},
                {'from': '5', 'to': '6', 'label': null},
                {'from': '6', 'to': '7', 'label': 'true'},
                {'from': '6', 'to': null, 'label': 'false'},
                {'from': '7', 'to': null, 'label': null},
              ],
            },
          },
          // The loop without steps is not drawn, nor is the last if: either
          // way the body ends. try draws its body, then finally. A label
          // the formatter wrapped is on one line.
          'lib/backup.dart#rotate': {
            'name': 'rotate',
            'place': 'lib/backup.dart:74',
            'body': {
              'nodes': [
                {
                  'id': '1',
                  'kind': 'fork',
                  'label':
                      "files.every((file) => file.endsWith('.gz') || "
                      "file.endsWith('.zip') || file.endsWith('.xz'))",
                  'place': 'lib/backup.dart:80',
                },
                {
                  'id': '2',
                  'kind': 'step',
                  'name': 'lock',
                  'place': 'lib/backup.dart:87',
                },
                {
                  'id': '3',
                  'kind': 'step',
                  'name': 'unlock',
                  'place': 'lib/backup.dart:89',
                },
              ],
              'edges': [
                {'from': null, 'to': '1', 'label': null},
                {'from': '1', 'to': null, 'label': 'true'},
                {'from': '1', 'to': '2', 'label': 'false'},
                {'from': '2', 'to': '3', 'label': null},
                {'from': '3', 'to': null, 'label': null},
              ],
            },
          },
          'lib/backup.dart#schedule': {
            'name': 'schedule',
            'place': 'lib/backup.dart:38',
            'body': {
              'nodes': [
                {
                  'id': '1',
                  'kind': 'fork',
                  'label': "config case {'every': final int hours}",
                  'place': 'lib/backup.dart:39',
                },
                {
                  'id': '2',
                  'kind': 'step',
                  'name': 'schedule',
                  'place': 'lib/backup.dart:40',
                },
              ],
              'edges': [
                {'from': null, 'to': '1', 'label': null},
                {'from': '1', 'to': '2', 'label': 'true'},
                {'from': '1', 'to': null, 'label': 'false'},
                {'from': '2', 'to': null, 'label': null},
              ],
            },
          },
          // continue goes to the next round, break out of the loop.
          'lib/backup.dart#sendParts': {
            'name': 'sendParts',
            'place': 'lib/backup.dart:58',
            'body': {
              'nodes': [
                {
                  'id': '1',
                  'kind': 'fork',
                  'label': 'for (; i < parts.length;)',
                  'place': 'lib/backup.dart:59',
                },
                {
                  'id': '2',
                  'kind': 'fork',
                  'label': 'parts[i].isEmpty',
                  'place': 'lib/backup.dart:60',
                },
                {
                  'id': '3',
                  'kind': 'step',
                  'name': 'send',
                  'place': 'lib/backup.dart:61',
                },
                {
                  'id': '4',
                  'kind': 'fork',
                  'label': '!sent',
                  'place': 'lib/backup.dart:62',
                },
                {
                  'id': '5',
                  'kind': 'step',
                  'name': 'close',
                  'place': 'lib/backup.dart:64',
                },
              ],
              'edges': [
                {'from': null, 'to': '1', 'label': null},
                {'from': '1', 'to': '2', 'label': 'true'},
                {'from': '1', 'to': '5', 'label': 'false'},
                {'from': '2', 'to': '1', 'label': 'true'},
                {'from': '2', 'to': '3', 'label': 'false'},
                {'from': '3', 'to': '4', 'label': null},
                {'from': '4', 'to': '1', 'label': 'false'},
                {'from': '4', 'to': '5', 'label': 'true'},
                {'from': '5', 'to': null, 'label': null},
              ],
            },
          },
          // A switch on a sealed class has a case for every subclass: no
          // default.
          'lib/backup.dart#store': {
            'name': 'store',
            'place': 'lib/backup.dart:19',
            'body': {
              'nodes': [
                {
                  'id': '1',
                  'kind': 'fork',
                  'label': 'switch (target)',
                  'place': 'lib/backup.dart:20',
                },
                {
                  'id': '2',
                  'kind': 'step',
                  'name': 'copy',
                  'place': 'lib/backup.dart:22',
                },
                {
                  'id': '3',
                  'kind': 'step',
                  'name': 'upload',
                  'place': 'lib/backup.dart:24',
                },
              ],
              'edges': [
                {'from': null, 'to': '1', 'label': null},
                {'from': '1', 'to': '2', 'label': 'Disk(:final path)'},
                {'from': '1', 'to': '3', 'label': 'Bucket(:final name)'},
                {'from': '2', 'to': null, 'label': null},
                {'from': '3', 'to': null, 'label': null},
              ],
            },
          },
          // break leaves the while for the do; do runs its body before it
          // asks.
          'lib/backup.dart#waitForHost': {
            'name': 'waitForHost',
            'place': 'lib/backup.dart:44',
            'body': {
              'nodes': [
                {
                  'id': '1',
                  'kind': 'fork',
                  'label': 'while (tries < 3)',
                  'place': 'lib/backup.dart:46',
                },
                {
                  'id': '2',
                  'kind': 'step',
                  'name': 'is-up',
                  'place': 'lib/backup.dart:47',
                },
                {
                  'id': '3',
                  'kind': 'fork',
                  'label': 'up',
                  'place': 'lib/backup.dart:48',
                },
                {
                  'id': '4',
                  'kind': 'step',
                  'name': 'ping',
                  'place': 'lib/backup.dart:53',
                },
                {
                  'id': '5',
                  'kind': 'step',
                  'name': 'is-busy',
                  'place': 'lib/backup.dart:54',
                },
                {
                  'id': '6',
                  'kind': 'fork',
                  'label': 'while (busy)',
                  'place': 'lib/backup.dart:55',
                },
              ],
              'edges': [
                {'from': null, 'to': '1', 'label': null},
                {'from': '1', 'to': '2', 'label': 'true'},
                {'from': '1', 'to': '4', 'label': 'false'},
                {'from': '2', 'to': '3', 'label': null},
                {'from': '3', 'to': '1', 'label': 'false'},
                {'from': '3', 'to': '4', 'label': 'true'},
                {'from': '4', 'to': '5', 'label': null},
                {'from': '5', 'to': '6', 'label': null},
                {'from': '6', 'to': '4', 'label': 'true'},
                {'from': '6', 'to': null, 'label': 'false'},
              ],
            },
          },
        },
      ),
    );
  });

  test('writes the same file every time', () async {
    final first = await describePackage(fixture('release'), packageName: 'x');
    final second = await describePackage(fixture('release'), packageName: 'x');
    expect(
      jsonEncode(second.graph!.toJson()),
      jsonEncode(first.graph!.toJson()),
    );
  });

  group('a package of its own', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('nanoflow_describe_test');
    });

    tearDown(() async {
      await dir.delete(recursive: true);
    });

    Future<void> write(String path, String text) async {
      final file = File(p.joinAll([dir.path, ...path.split('/')]));
      await file.parent.create(recursive: true);
      await file.writeAsString(text);
    }

    test('is named by its pubspec.yaml', () async {
      await write('pubspec.yaml', 'name: tiny_app # the app\n');
      await write('lib/tiny.dart', 'int answer() => 42;\n');
      final result = await describePackage(dir.path);
      expect(result.errors, isEmpty);
      final sources = {
        'lib/tiny.dart': sourceHash(utf8.encode('int answer() => 42;\n')),
      };
      expectFile(result.graph!.toJson(), {
        'format': 1,
        'package': 'tiny_app',
        'fingerprint': fingerprintOf(sources),
        'sources': sources,
        'builds': <String, Object?>{},
        'workflows': <Object?>[],
        'functions': <String, Object?>{},
        'warnings': <Object?>[],
      });
    });

    test('has no graph while it does not compile', () async {
      await write('lib/fine.dart', 'int answer() => 42;\n');
      await write('lib/broken.dart', "int answer() => 'forty-two';\n");
      final result = await describePackage(dir.path, packageName: 'broken');
      expect(result.graph, isNull);
      expect(result.errors, [
        allOf(startsWith('lib/broken.dart:1:17: '), contains("'String'")),
      ]);
    });

    test('has no graph without a name', () async {
      await write('lib/tiny.dart', 'int answer() => 42;\n');
      final result = await describePackage(dir.path);
      expect(result.graph, isNull);
      expect(result.errors, [
        '${p.join(dir.path, 'pubspec.yaml')}: no package name',
      ]);
    });
  });
}
