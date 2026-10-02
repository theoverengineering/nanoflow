@TestOn('mac-os')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  /// What test/platform/terminal_probe.dart says when [command], a shell
  /// command around `$PROBE`, runs it.
  Future<String> probe(String command) async {
    final result = await Process.run(
      '/bin/sh',
      ['-c', command],
      environment: {
        'PROBE':
            'dart --packages=.dart_tool/package_config.json '
            'test/platform/terminal_probe.dart',
      },
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return (result.stderr as String).trim();
  }

  test('an app opened from Finder, its stdin /dev/null, is not in a '
      'terminal', () async {
    expect(await probe(r'$PROBE < /dev/null > /dev/null'), 'false');
  });

  test(
    'an app whose stdin and stdout are pipes is not in a terminal',
    () async {
      expect(await probe(r'echo | $PROBE | cat'), 'false');
    },
  );

  test('an app started from a shell in a terminal is in one', () async {
    // script(1) runs the probe on a pseudo-terminal and copies what it
    // prints there to its own stdout, here sent to stderr.
    expect(
      await probe(r'script -q /dev/null $PROBE < /dev/null >&2'),
      endsWith('true'),
    );
  });
}
