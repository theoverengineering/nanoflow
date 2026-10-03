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
          // `case _` matches every value: no default.
          'lib/backup.dart#alert': {
            'name': 'alert',
            'place': 'lib/backup.dart:130',
            'body': {
              'nodes': [
                {
                  'id': '1',
                  'kind': 'fork',
                  'label': 'switch (level)',
                  'place': 'lib/backup.dart:131',
                },
                {
                  'id': '2',
                  'kind': 'step',
                  'name': 'page',
                  'place': 'lib/backup.dart:133',
                },
                {
                  'id': '3',
                  'kind': 'step',
                  'name': 'log',
                  'place': 'lib/backup.dart:135',
                },
              ],
              'edges': [
                {'from': null, 'to': '1', 'label': null},
                {'from': '1', 'to': '2', 'label': "'error'"},
                {'from': '1', 'to': '3', 'label': '_'},
                {'from': '2', 'to': null, 'label': null},
                {'from': '3', 'to': null, 'label': null},
              ],
            },
          },
          // A switch with no default: the flow goes on after it when no case
          // matches.
          'lib/backup.dart#compress': {
            'name': 'compress',
            'place': 'lib/backup.dart:30',
            'body': {
              'nodes': [
                {
                  'id': '1',
                  'kind': 'fork',
                  'label': 'switch (format)',
                  'place': 'lib/backup.dart:31',
                },
                {
                  'id': '2',
                  'kind': 'step',
                  'name': 'zip',
                  'place': 'lib/backup.dart:33',
                },
                {
                  'id': '3',
                  'kind': 'step',
                  'name': 'tar',
                  'place': 'lib/backup.dart:35',
                },
                {
                  'id': '4',
                  'kind': 'step',
                  'name': 'checksum',
                  'place': 'lib/backup.dart:37',
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
          // A return in try goes through finally first: finally is drawn
          // once for the way through and once for the return.
          'lib/backup.dart#deployLocked': {
            'name': 'deployLocked',
            'place': 'lib/backup.dart:105',
            'body': {
              'nodes': [
                {
                  'id': '1',
                  'kind': 'step',
                  'name': 'lock',
                  'place': 'lib/backup.dart:107',
                },
                {
                  'id': '2',
                  'kind': 'fork',
                  'label': 'early',
                  'place': 'lib/backup.dart:108',
                },
                {
                  'id': '3',
                  'kind': 'step',
                  'name': 'work',
                  'place': 'lib/backup.dart:109',
                },
                {
                  'id': '4',
                  'kind': 'step',
                  'name': 'unlock',
                  'place': 'lib/backup.dart:111',
                },
                {
                  'id': '5',
                  'kind': 'step',
                  'name': 'unlock',
                  'place': 'lib/backup.dart:111',
                },
                {
                  'id': '6',
                  'kind': 'step',
                  'name': 'report',
                  'place': 'lib/backup.dart:113',
                },
              ],
              'edges': [
                {'from': null, 'to': '1', 'label': null},
                {'from': '1', 'to': '2', 'label': null},
                {'from': '2', 'to': '3', 'label': 'false'},
                {'from': '2', 'to': '5', 'label': 'true'},
                {'from': '3', 'to': '4', 'label': null},
                {'from': '4', 'to': '6', 'label': null},
                {'from': '5', 'to': null, 'label': null},
                {'from': '6', 'to': null, 'label': null},
              ],
            },
          },
          // continue and break in try go through finally too: once for the
          // way through, once for break, once for continue.
          'lib/backup.dart#drain': {
            'name': 'drain',
            'place': 'lib/backup.dart:116',
            'body': {
              'nodes': [
                {
                  'id': '1',
                  'kind': 'fork',
                  'label': 'for queue in queues',
                  'place': 'lib/backup.dart:117',
                },
                {
                  'id': '2',
                  'kind': 'step',
                  'name': 'measure',
                  'place': 'lib/backup.dart:119',
                },
                {
                  'id': '3',
                  'kind': 'fork',
                  'label': 'size == 0',
                  'place': 'lib/backup.dart:120',
                },
                {
                  'id': '4',
                  'kind': 'fork',
                  'label': 'size > 100',
                  'place': 'lib/backup.dart:121',
                },
                {
                  'id': '5',
                  'kind': 'step',
                  'name': 'process',
                  'place': 'lib/backup.dart:122',
                },
                {
                  'id': '6',
                  'kind': 'step',
                  'name': 'release',
                  'place': 'lib/backup.dart:124',
                },
                {
                  'id': '7',
                  'kind': 'step',
                  'name': 'release',
                  'place': 'lib/backup.dart:124',
                },
                {
                  'id': '8',
                  'kind': 'step',
                  'name': 'release',
                  'place': 'lib/backup.dart:124',
                },
                {
                  'id': '9',
                  'kind': 'step',
                  'name': 'done',
                  'place': 'lib/backup.dart:127',
                },
              ],
              'edges': [
                {'from': null, 'to': '1', 'label': null},
                {'from': '1', 'to': '2', 'label': 'each'},
                {'from': '1', 'to': '9', 'label': 'done'},
                {'from': '2', 'to': '3', 'label': null},
                {'from': '3', 'to': '8', 'label': 'true'},
                {'from': '3', 'to': '4', 'label': 'false'},
                {'from': '4', 'to': '5', 'label': 'false'},
                {'from': '4', 'to': '7', 'label': 'true'},
                {'from': '5', 'to': '6', 'label': null},
                {'from': '6', 'to': '1', 'label': null},
                {'from': '7', 'to': '9', 'label': null},
                {'from': '8', 'to': '1', 'label': null},
                {'from': '9', 'to': null, 'label': null},
              ],
            },
          },
          // A record's wait runs its fields side by side.
          'lib/backup.dart#prepare': {
            'name': 'prepare',
            'place': 'lib/backup.dart:145',
            'body': {
              'nodes': [
                {
                  'id': '1',
                  'kind': 'step',
                  'name': 'measure-disk',
                  'place': 'lib/backup.dart:147',
                },
                {
                  'id': '2',
                  'kind': 'step',
                  'name': 'measure-memory',
                  'place': 'lib/backup.dart:148',
                },
                {
                  'id': '3',
                  'kind': 'step',
                  'name': 'plan',
                  'place': 'lib/backup.dart:150',
                },
              ],
              'edges': [
                {'from': null, 'to': '1', 'label': null},
                {'from': null, 'to': '2', 'label': null},
                {'from': '1', 'to': '3', 'label': null},
                {'from': '2', 'to': '3', 'label': null},
                {'from': '3', 'to': null, 'label': null},
              ],
            },
          },
          // ?:, then || whose right side is an && with a step on its right.
          'lib/backup.dart#report': {
            'name': 'report',
            'place': 'lib/backup.dart:69',
            'body': {
              'nodes': [
                {
                  'id': '1',
                  'kind': 'fork',
                  'label': 'quiet',
                  'place': 'lib/backup.dart:70',
                },
                {
                  'id': '2',
                  'kind': 'step',
                  'name': 'summarize',
                  'place': 'lib/backup.dart:70',
                },
                {
                  'id': '3',
                  'kind': 'fork',
                  'label': 'urgent',
                  'place': 'lib/backup.dart:71',
                },
                {
                  'id': '4',
                  'kind': 'fork',
                  'label': 'text.isNotEmpty',
                  'place': 'lib/backup.dart:71',
                },
                {
                  'id': '5',
                  'kind': 'step',
                  'name': 'ask',
                  'place': 'lib/backup.dart:71',
                },
                {
                  'id': '6',
                  'kind': 'fork',
                  'label':
                      'urgent || text.isNotEmpty && '
                      "await f.step('ask', () => true)",
                  'place': 'lib/backup.dart:71',
                },
                {
                  'id': '7',
                  'kind': 'step',
                  'name': 'mail',
                  'place': 'lib/backup.dart:72',
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
          // A throw ends the flow: its way out of the fork has no edge, and
          // the fork stays, since its ways out differ.
          'lib/backup.dart#restore': {
            'name': 'restore',
            'place': 'lib/backup.dart:139',
            'body': {
              'nodes': [
                {
                  'id': '1',
                  'kind': 'step',
                  'name': 'find',
                  'place': 'lib/backup.dart:140',
                },
                {
                  'id': '2',
                  'kind': 'fork',
                  'label': '!found',
                  'place': 'lib/backup.dart:141',
                },
                {
                  'id': '3',
                  'kind': 'step',
                  'name': 'restore',
                  'place': 'lib/backup.dart:142',
                },
              ],
              'edges': [
                {'from': null, 'to': '1', 'label': null},
                {'from': '1', 'to': '2', 'label': null},
                {'from': '2', 'to': '3', 'label': 'false'},
                {'from': '3', 'to': null, 'label': null},
              ],
            },
          },
          // The loop without steps is not drawn, nor is the last if: either
          // way the body ends. try draws its body, then finally. A label
          // the formatter wrapped is on one line.
          'lib/backup.dart#rotate': {
            'name': 'rotate',
            'place': 'lib/backup.dart:76',
            'body': {
              'nodes': [
                {
                  'id': '1',
                  'kind': 'fork',
                  'label':
                      "files.every((file) => file.endsWith('.gz') || "
                      "file.endsWith('.zip') || file.endsWith('.xz'))",
                  'place': 'lib/backup.dart:82',
                },
                {
                  'id': '2',
                  'kind': 'step',
                  'name': 'lock',
                  'place': 'lib/backup.dart:89',
                },
                {
                  'id': '3',
                  'kind': 'step',
                  'name': 'unlock',
                  'place': 'lib/backup.dart:91',
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
            'place': 'lib/backup.dart:40',
            'body': {
              'nodes': [
                {
                  'id': '1',
                  'kind': 'fork',
                  'label': "config case {'every': final int hours}",
                  'place': 'lib/backup.dart:41',
                },
                {
                  'id': '2',
                  'kind': 'step',
                  'name': 'schedule',
                  'place': 'lib/backup.dart:42',
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
            'place': 'lib/backup.dart:60',
            'body': {
              'nodes': [
                {
                  'id': '1',
                  'kind': 'fork',
                  'label': 'for (; i < parts.length;)',
                  'place': 'lib/backup.dart:61',
                },
                {
                  'id': '2',
                  'kind': 'fork',
                  'label': 'parts[i].isEmpty',
                  'place': 'lib/backup.dart:62',
                },
                {
                  'id': '3',
                  'kind': 'step',
                  'name': 'send',
                  'place': 'lib/backup.dart:63',
                },
                {
                  'id': '4',
                  'kind': 'fork',
                  'label': '!sent',
                  'place': 'lib/backup.dart:64',
                },
                {
                  'id': '5',
                  'kind': 'step',
                  'name': 'close',
                  'place': 'lib/backup.dart:66',
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
            'place': 'lib/backup.dart:21',
            'body': {
              'nodes': [
                {
                  'id': '1',
                  'kind': 'fork',
                  'label': 'switch (target)',
                  'place': 'lib/backup.dart:22',
                },
                {
                  'id': '2',
                  'kind': 'step',
                  'name': 'copy',
                  'place': 'lib/backup.dart:24',
                },
                {
                  'id': '3',
                  'kind': 'step',
                  'name': 'upload',
                  'place': 'lib/backup.dart:26',
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
          // A switch expression is a fork; it matches every value.
          'lib/backup.dart#verify': {
            'name': 'verify',
            'place': 'lib/backup.dart:97',
            'body': {
              'nodes': [
                {
                  'id': '1',
                  'kind': 'fork',
                  'label': 'switch (target)',
                  'place': 'lib/backup.dart:98',
                },
                {
                  'id': '2',
                  'kind': 'step',
                  'name': 'stat',
                  'place': 'lib/backup.dart:99',
                },
                {
                  'id': '3',
                  'kind': 'step',
                  'name': 'head',
                  'place': 'lib/backup.dart:100',
                },
                {
                  'id': '4',
                  'kind': 'step',
                  'name': 'record',
                  'place': 'lib/backup.dart:102',
                },
              ],
              'edges': [
                {'from': null, 'to': '1', 'label': null},
                {'from': '1', 'to': '2', 'label': 'Disk(:final path)'},
                {'from': '1', 'to': '3', 'label': 'Bucket()'},
                {'from': '2', 'to': '4', 'label': null},
                {'from': '3', 'to': '4', 'label': null},
                {'from': '4', 'to': null, 'label': null},
              ],
            },
          },
          // break leaves the while for the do; do runs its body before it
          // asks.
          'lib/backup.dart#waitForHost': {
            'name': 'waitForHost',
            'place': 'lib/backup.dart:46',
            'body': {
              'nodes': [
                {
                  'id': '1',
                  'kind': 'fork',
                  'label': 'while (tries < 3)',
                  'place': 'lib/backup.dart:48',
                },
                {
                  'id': '2',
                  'kind': 'step',
                  'name': 'is-up',
                  'place': 'lib/backup.dart:49',
                },
                {
                  'id': '3',
                  'kind': 'fork',
                  'label': 'up',
                  'place': 'lib/backup.dart:50',
                },
                {
                  'id': '4',
                  'kind': 'step',
                  'name': 'ping',
                  'place': 'lib/backup.dart:55',
                },
                {
                  'id': '5',
                  'kind': 'step',
                  'name': 'is-busy',
                  'place': 'lib/backup.dart:56',
                },
                {
                  'id': '6',
                  'kind': 'fork',
                  'label': 'while (busy)',
                  'place': 'lib/backup.dart:57',
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

  test('takes a caught throw on after the try, ends the path of a throw arm '
      'and warns once per place', () async {
    expectFile(
      await describeFixture('throws'),
      await expectedFile(
        'throws',
        workflows: [],
        functions: {
          // finally is drawn twice, its step name warns once.
          'lib/throws.dart#cleanUp': {
            'name': 'cleanUp',
            'place': 'lib/throws.dart:7',
            'body': {
              'nodes': [
                {
                  'id': '1',
                  'kind': 'step',
                  'name': 'acquire',
                  'place': 'lib/throws.dart:9',
                },
                {
                  'id': '2',
                  'kind': 'fork',
                  'label': 'early',
                  'place': 'lib/throws.dart:10',
                },
                {
                  'id': '3',
                  'kind': 'step',
                  'name': 'use',
                  'place': 'lib/throws.dart:11',
                },
                {
                  'id': '4',
                  'kind': 'step',
                  'name': r"'release-$lock'",
                  'place': 'lib/throws.dart:13',
                },
                {
                  'id': '5',
                  'kind': 'step',
                  'name': r"'release-$lock'",
                  'place': 'lib/throws.dart:13',
                },
              ],
              'edges': [
                {'from': null, 'to': '1', 'label': null},
                {'from': '1', 'to': '2', 'label': null},
                {'from': '2', 'to': '3', 'label': 'false'},
                {'from': '2', 'to': '5', 'label': 'true'},
                {'from': '3', 'to': '4', 'label': null},
                {'from': '4', 'to': null, 'label': null},
                {'from': '5', 'to': null, 'label': null},
              ],
            },
          },
          // The throw is in a catch clause, which is not drawn: the loop
          // has no steps and nothing that leaves it, so it is left out.
          'lib/throws.dart#importLines': {
            'name': 'importLines',
            'place': 'lib/throws.dart:17',
            'body': {
              'nodes': [
                {
                  'id': '1',
                  'kind': 'step',
                  'name': 'import',
                  'place': 'lib/throws.dart:25',
                },
              ],
              'edges': [
                {'from': null, 'to': '1', 'label': null},
                {'from': '1', 'to': null, 'label': null},
              ],
            },
          },
          // A throw arm of a switch expression or of ?: has no edge.
          'lib/throws.dart#measure': {
            'name': 'measure',
            'place': 'lib/throws.dart:54',
            'body': {
              'nodes': [
                {
                  'id': '1',
                  'kind': 'fork',
                  'label': 'switch (kind)',
                  'place': 'lib/throws.dart:55',
                },
                {
                  'id': '2',
                  'kind': 'step',
                  'name': 'stat',
                  'place': 'lib/throws.dart:56',
                },
                {
                  'id': '3',
                  'kind': 'fork',
                  'label': 'size > 50',
                  'place': 'lib/throws.dart:59',
                },
                {
                  'id': '4',
                  'kind': 'step',
                  'name': 'unit',
                  'place': 'lib/throws.dart:60',
                },
                {
                  'id': '5',
                  'kind': 'step',
                  'name': 'record',
                  'place': 'lib/throws.dart:62',
                },
              ],
              'edges': [
                {'from': null, 'to': '1', 'label': null},
                {'from': '1', 'to': '2', 'label': "'disk'"},
                {'from': '2', 'to': '3', 'label': null},
                {'from': '3', 'to': '4', 'label': 'true'},
                {'from': '4', 'to': '5', 'label': null},
                {'from': '5', 'to': null, 'label': null},
              ],
            },
          },
          // The throw leaves the inner try through its finally, then the
          // outer catch takes it on after the outer try.
          'lib/throws.dart#mirror': {
            'name': 'mirror',
            'place': 'lib/throws.dart:39',
            'body': {
              'nodes': [
                {
                  'id': '1',
                  'kind': 'step',
                  'name': 'fetch',
                  'place': 'lib/throws.dart:42',
                },
                {
                  'id': '2',
                  'kind': 'fork',
                  'label': '!ok',
                  'place': 'lib/throws.dart:43',
                },
                {
                  'id': '3',
                  'kind': 'step',
                  'name': 'write',
                  'place': 'lib/throws.dart:44',
                },
                {
                  'id': '4',
                  'kind': 'step',
                  'name': 'close',
                  'place': 'lib/throws.dart:46',
                },
                {
                  'id': '5',
                  'kind': 'step',
                  'name': 'close',
                  'place': 'lib/throws.dart:46',
                },
                {
                  'id': '6',
                  'kind': 'step',
                  'name': 'report',
                  'place': 'lib/throws.dart:51',
                },
              ],
              'edges': [
                {'from': null, 'to': '1', 'label': null},
                {'from': '1', 'to': '2', 'label': null},
                {'from': '2', 'to': '3', 'label': 'false'},
                {'from': '2', 'to': '5', 'label': 'true'},
                {'from': '3', 'to': '4', 'label': null},
                {'from': '4', 'to': '6', 'label': null},
                {'from': '5', 'to': '6', 'label': null},
                {'from': '6', 'to': null, 'label': null},
              ],
            },
          },
          // The catch takes the throw on after the try.
          'lib/throws.dart#sync': {
            'name': 'sync',
            'place': 'lib/throws.dart:28',
            'body': {
              'nodes': [
                {
                  'id': '1',
                  'kind': 'step',
                  'name': 'ping',
                  'place': 'lib/throws.dart:30',
                },
                {
                  'id': '2',
                  'kind': 'fork',
                  'label': '!reachable',
                  'place': 'lib/throws.dart:31',
                },
                {
                  'id': '3',
                  'kind': 'step',
                  'name': 'pull',
                  'place': 'lib/throws.dart:32',
                },
                {
                  'id': '4',
                  'kind': 'step',
                  'name': 'log',
                  'place': 'lib/throws.dart:36',
                },
              ],
              'edges': [
                {'from': null, 'to': '1', 'label': null},
                {'from': '1', 'to': '2', 'label': null},
                {'from': '2', 'to': '3', 'label': 'false'},
                {'from': '2', 'to': '4', 'label': 'true'},
                {'from': '3', 'to': '4', 'label': null},
                {'from': '4', 'to': null, 'label': null},
              ],
            },
          },
        },
        warnings: [
          {
            'place': 'lib/throws.dart:13',
            'message': 'step name is not a string literal',
          },
          {
            'place': 'lib/throws.dart:33',
            'message': 'catch clauses are not drawn',
          },
          {
            'place': 'lib/throws.dart:48',
            'message': 'catch clauses are not drawn',
          },
        ],
      ),
    );
  });

  test('takes a throw on after its try only when a catch clause that it '
      'fits can finish normally', () async {
    expectFile(
      await describeFixture('catches'),
      await expectedFile(
        'catches',
        workflows: [],
        functions: {
          // The catch returns: the throw leaves the function.
          'lib/catches.dart#backup': {
            'name': 'backup',
            'place': 'lib/catches.dart:23',
            'body': {
              'nodes': [
                {
                  'id': '1',
                  'kind': 'step',
                  'name': 'measure',
                  'place': 'lib/catches.dart:25',
                },
                {
                  'id': '2',
                  'kind': 'fork',
                  'label': 'free == 0',
                  'place': 'lib/catches.dart:26',
                },
                {
                  'id': '3',
                  'kind': 'step',
                  'name': 'copy',
                  'place': 'lib/catches.dart:27',
                },
                {
                  'id': '4',
                  'kind': 'step',
                  'name': 'verify',
                  'place': 'lib/catches.dart:32',
                },
              ],
              'edges': [
                {'from': null, 'to': '1', 'label': null},
                {'from': '1', 'to': '2', 'label': null},
                {'from': '2', 'to': null, 'label': 'true'},
                {'from': '2', 'to': '3', 'label': 'false'},
                {'from': '3', 'to': '4', 'label': null},
                {'from': '4', 'to': null, 'label': null},
              ],
            },
          },
          // The throw arm of ?: fits `on ArgumentError`.
          'lib/catches.dart#convert': {
            'name': 'convert',
            'place': 'lib/catches.dart:73',
            'body': {
              'nodes': [
                {
                  'id': '1',
                  'kind': 'fork',
                  'label': "unit == 'km'",
                  'place': 'lib/catches.dart:75',
                },
                {
                  'id': '2',
                  'kind': 'step',
                  'name': 'scale',
                  'place': 'lib/catches.dart:76',
                },
                {
                  'id': '3',
                  'kind': 'step',
                  'name': 'apply',
                  'place': 'lib/catches.dart:78',
                },
                {
                  'id': '4',
                  'kind': 'step',
                  'name': 'report',
                  'place': 'lib/catches.dart:82',
                },
              ],
              'edges': [
                {'from': null, 'to': '1', 'label': null},
                {'from': '1', 'to': '2', 'label': 'true'},
                {'from': '1', 'to': '4', 'label': 'false'},
                {'from': '2', 'to': '3', 'label': null},
                {'from': '3', 'to': '4', 'label': null},
                {'from': '4', 'to': null, 'label': null},
              ],
            },
          },
          // A FormatException fits `on Exception`: the caught throw and the
          // end of the body share one finally.
          'lib/catches.dart#deploy': {
            'name': 'deploy',
            'place': 'lib/catches.dart:47',
            'body': {
              'nodes': [
                {
                  'id': '1',
                  'kind': 'step',
                  'name': 'prepare',
                  'place': 'lib/catches.dart:49',
                },
                {
                  'id': '2',
                  'kind': 'fork',
                  'label': '!ready',
                  'place': 'lib/catches.dart:50',
                },
                {
                  'id': '3',
                  'kind': 'step',
                  'name': 'ship',
                  'place': 'lib/catches.dart:51',
                },
                {
                  'id': '4',
                  'kind': 'step',
                  'name': 'unlock',
                  'place': 'lib/catches.dart:55',
                },
                {
                  'id': '5',
                  'kind': 'step',
                  'name': 'announce',
                  'place': 'lib/catches.dart:57',
                },
              ],
              'edges': [
                {'from': null, 'to': '1', 'label': null},
                {'from': '1', 'to': '2', 'label': null},
                {'from': '2', 'to': '3', 'label': 'false'},
                {'from': '2', 'to': '4', 'label': 'true'},
                {'from': '3', 'to': '4', 'label': null},
                {'from': '4', 'to': '5', 'label': null},
                {'from': '5', 'to': null, 'label': null},
              ],
            },
          },
          // A StateError passes `on HttpException` by and ends the path; an
          // HttpException is taken on.
          'lib/catches.dart#fetch': {
            'name': 'fetch',
            'place': 'lib/catches.dart:35',
            'body': {
              'nodes': [
                {
                  'id': '1',
                  'kind': 'step',
                  'name': 'download',
                  'place': 'lib/catches.dart:37',
                },
                {
                  'id': '2',
                  'kind': 'fork',
                  'label': 'page.isEmpty',
                  'place': 'lib/catches.dart:38',
                },
                {
                  'id': '3',
                  'kind': 'fork',
                  'label': "page == 'busy'",
                  'place': 'lib/catches.dart:39',
                },
                {
                  'id': '4',
                  'kind': 'step',
                  'name': 'parse',
                  'place': 'lib/catches.dart:40',
                },
                {
                  'id': '5',
                  'kind': 'step',
                  'name': 'store',
                  'place': 'lib/catches.dart:44',
                },
              ],
              'edges': [
                {'from': null, 'to': '1', 'label': null},
                {'from': '1', 'to': '2', 'label': null},
                {'from': '2', 'to': '3', 'label': 'false'},
                {'from': '3', 'to': '4', 'label': 'false'},
                {'from': '3', 'to': '5', 'label': 'true'},
                {'from': '4', 'to': '5', 'label': null},
                {'from': '5', 'to': null, 'label': null},
              ],
            },
          },
          // A loop without steps, left by a throw its catch rethrows.
          'lib/catches.dart#importAll': {
            'name': 'importAll',
            'place': 'lib/catches.dart:85',
            'body': {
              'nodes': [
                {
                  'id': '1',
                  'kind': 'fork',
                  'label': 'for name in names',
                  'place': 'lib/catches.dart:86',
                },
                {
                  'id': '2',
                  'kind': 'fork',
                  'label': 'name.isEmpty',
                  'place': 'lib/catches.dart:88',
                },
                {
                  'id': '3',
                  'kind': 'step',
                  'name': 'import',
                  'place': 'lib/catches.dart:94',
                },
              ],
              'edges': [
                {'from': null, 'to': '1', 'label': null},
                {'from': '1', 'to': '2', 'label': 'each'},
                {'from': '1', 'to': '3', 'label': 'done'},
                {'from': '2', 'to': '1', 'label': 'false'},
                {'from': '3', 'to': null, 'label': null},
              ],
            },
          },
          // The throw in a closure called in place is caught around it.
          'lib/catches.dart#rotate': {
            'name': 'rotate',
            'place': 'lib/catches.dart:60',
            'body': {
              'nodes': [
                {
                  'id': '1',
                  'kind': 'step',
                  'name': 'read',
                  'place': 'lib/catches.dart:63',
                },
                {
                  'id': '2',
                  'kind': 'fork',
                  'label': 'old.isEmpty',
                  'place': 'lib/catches.dart:64',
                },
                {
                  'id': '3',
                  'kind': 'step',
                  'name': 'replace',
                  'place': 'lib/catches.dart:65',
                },
                {
                  'id': '4',
                  'kind': 'step',
                  'name': 'audit',
                  'place': 'lib/catches.dart:70',
                },
              ],
              'edges': [
                {'from': null, 'to': '1', 'label': null},
                {'from': '1', 'to': '2', 'label': null},
                {'from': '2', 'to': '3', 'label': 'false'},
                {'from': '2', 'to': '4', 'label': 'true'},
                {'from': '3', 'to': '4', 'label': null},
                {'from': '4', 'to': null, 'label': null},
              ],
            },
          },
          // The catch logs and rethrows: the throw ends the path.
          'lib/catches.dart#upload': {
            'name': 'upload',
            'place': 'lib/catches.dart:11',
            'body': {
              'nodes': [
                {
                  'id': '1',
                  'kind': 'step',
                  'name': 'check',
                  'place': 'lib/catches.dart:13',
                },
                {
                  'id': '2',
                  'kind': 'fork',
                  'label': '!ok',
                  'place': 'lib/catches.dart:14',
                },
                {
                  'id': '3',
                  'kind': 'step',
                  'name': 'send',
                  'place': 'lib/catches.dart:15',
                },
                {
                  'id': '4',
                  'kind': 'step',
                  'name': 'confirm',
                  'place': 'lib/catches.dart:20',
                },
              ],
              'edges': [
                {'from': null, 'to': '1', 'label': null},
                {'from': '1', 'to': '2', 'label': null},
                {'from': '2', 'to': '3', 'label': 'false'},
                {'from': '3', 'to': '4', 'label': null},
                {'from': '4', 'to': null, 'label': null},
              ],
            },
          },
        },
        warnings: [
          for (final line in [16, 28, 41, 52, 67, 79])
            {
              'place': 'lib/catches.dart:$line',
              'message': 'catch clauses are not drawn',
            },
        ],
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
