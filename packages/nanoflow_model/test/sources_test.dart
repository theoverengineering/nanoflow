import 'dart:convert';
import 'dart:io';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:test/test.dart';

/// `printf 'lib/a.dart sha256:00\n' | shasum -a 256`
const String _knownFingerprint =
    'sha256:5f5d893fb92b27333d6e7c17a2d904cdc81cf762306a003654651e62cb397f56';

/// `printf 'a.dart sha256:11\nb.dart sha256:22\n' | shasum -a 256`
const String _twoFilesFingerprint =
    'sha256:f9a754dbd736714b9f3b925de91ab1c672eb0edfac4d65a74a2498aab1613d74';

/// `printf 'abc' | shasum -a 256`
const String _abc =
    'sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';

/// `printf 'a\nb' | shasum -a 256`
const String _aNlB =
    'sha256:7e18f737311b2dc3b2f269dd78396b0351f14fb66efa879f768cb23181883c78';

/// `printf 'a\rb' | shasum -a 256`
const String _aCrB =
    'sha256:af9081672dd5ef3247a30c2db5b0dafcc9bcf981a26aefb3c55d210d43fcc14e';

/// `printf '' | shasum -a 256`
const String _empty =
    'sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

List<int> _bytes(String text) => latin1.encode(text);

/// A package directory with [files] (paths with `/`, contents as text) that is
/// removed when the test ends.
Directory _package(Map<String, String> files) {
  final dir = Directory.systemTemp.createTempSync('nanoflow_sources_test');
  addTearDown(() => dir.deleteSync(recursive: true));
  for (final MapEntry(:key, :value) in files.entries) {
    File('${dir.path}/$key')
      ..createSync(recursive: true)
      ..writeAsStringSync(value);
  }
  return dir;
}

void main() {
  group('packageSourcePaths', () {
    test('lists the .dart files under lib/ and bin/, sorted', () async {
      final dir = _package({
        'lib/a.dart': '',
        'lib/.hidden/b.dart': '',
        'lib/build/c.dart': '',
        'bin/main.dart': '',
        'test/t.dart': '',
        'lib/x.txt': '',
      });
      expect(await packageSourcePaths(dir.path), [
        'bin/main.dart',
        'lib/a.dart',
      ]);
    });

    test('goes into nested directories and skips hidden and build ones '
        'at any depth', () async {
      final dir = _package({
        'lib/src/deep/d.dart': '',
        'lib/src/.cache/e.dart': '',
        'lib/src/build/f.dart': '',
        'bin/tools/build/g.dart': '',
        'bin/tools/h.dart': '',
      });
      expect(await packageSourcePaths(dir.path), [
        'bin/tools/h.dart',
        'lib/src/deep/d.dart',
      ]);
    });

    test('skips only directories named build, not other names', () async {
      final dir = _package({
        'lib/build.dart': '',
        'lib/builder/b.dart': '',
        'lib/rebuild/r.dart': '',
      });
      expect(await packageSourcePaths(dir.path), [
        'lib/build.dart',
        'lib/builder/b.dart',
        'lib/rebuild/r.dart',
      ]);
    });

    test('sorts by the characters of the path, capitals first', () async {
      final dir = _package({'lib/a.dart': '', 'lib/Z.dart': ''});
      expect(await packageSourcePaths(dir.path), ['lib/Z.dart', 'lib/a.dart']);
    });

    test('takes a missing lib/ or bin/ as empty', () async {
      expect(await packageSourcePaths(_package({'lib/a.dart': ''}).path), [
        'lib/a.dart',
      ]);
      expect(await packageSourcePaths(_package({'bin/m.dart': ''}).path), [
        'bin/m.dart',
      ]);
      expect(
        await packageSourcePaths(_package({'README.md': ''}).path),
        isEmpty,
      );
    });

    test('does not look at a hidden package directory name', () async {
      final parent = Directory.systemTemp.createTempSync('nanoflow_sources');
      addTearDown(() => parent.deleteSync(recursive: true));
      File('${parent.path}/.pkg/lib/a.dart').createSync(recursive: true);
      expect(await packageSourcePaths('${parent.path}/.pkg'), ['lib/a.dart']);
    });
  });

  test('packageGraphFilePaths lists the graph files under lib/ and bin/, '
      'skipping what packageSourcePaths skips', () async {
    final dir = _package({
      'nanoflow.graph.json': '',
      'lib/src/a.graph.json': '',
      'lib/src/a.dart': '',
      'lib/.hidden/b.graph.json': '',
      'lib/build/c.graph.json': '',
      'bin/main.graph.json': '',
      'lib/graph.json': '',
      'test/t.graph.json': '',
    });
    expect(await packageGraphFilePaths(dir.path), [
      'bin/main.graph.json',
      'lib/src/a.graph.json',
    ]);
  });

  group('hashes', () {
    test('bytesHash is sha256 of the bytes as they are', () {
      expect(bytesHash(_bytes('abc')), _abc);
      expect(bytesHash(_bytes('a\r\nb')), isNot(bytesHash(_bytes('a\nb'))));
      expect(bytesHash(const []), _empty);
    });

    test('sourceHash reads \\r\\n as \\n', () {
      expect(sourceHash(_bytes('a\r\nb')), sourceHash(_bytes('a\nb')));
      expect(sourceHash(_bytes('a\nb')), _aNlB);
      expect(sourceHash(_bytes('abc')), _abc);
      expect(sourceHash(const []), _empty);
    });

    test('sourceHash keeps a \\r that is not followed by \\n', () {
      expect(sourceHash(_bytes('a\rb')), _aCrB);
      expect(sourceHash(_bytes('a\rb')), isNot(sourceHash(_bytes('a\nb'))));
      // Only the pair goes: the first \r stays.
      expect(sourceHash(_bytes('a\r\r\nb')), bytesHash(_bytes('a\r\nb')));
      expect(sourceHash(_bytes('a\r')), bytesHash(_bytes('a\r')));
    });

    test('sourceHash changes with a changed byte', () {
      expect(sourceHash(_bytes('a\nb')), isNot(sourceHash(_bytes('a\nc'))));
    });
  });

  group('hashSources', () {
    test('hashes every file that exists and leaves out the missing', () async {
      final dir = _package({'lib/a.dart': 'abc', 'bin/m.dart': 'a\r\nb'});
      expect(
        await hashSources(dir.path, [
          'lib/a.dart',
          'lib/gone.dart',
          'bin/m.dart',
        ]),
        {'lib/a.dart': _abc, 'bin/m.dart': _aNlB},
      );
    });

    test('is empty for no paths', () async {
      expect(await hashSources(_package({}).path, const []), isEmpty);
    });

    test('hashes what packageSourcePaths finds', () async {
      final dir = _package({
        'lib/a.dart': 'abc',
        'bin/main.dart': 'a\nb',
        'lib/x.txt': 'x',
      });
      final paths = await packageSourcePaths(dir.path);
      expect(await hashSources(dir.path, paths), {
        'bin/main.dart': _aNlB,
        'lib/a.dart': _abc,
      });
    });
  });

  group('fingerprintOf', () {
    test('is the sha256 of the lines "<path> <hash>\\n"', () {
      expect(fingerprintOf({'lib/a.dart': 'sha256:00'}), _knownFingerprint);
      expect(fingerprintOf(const {}), _empty);
    });

    test('sorts the lines by path, so the map order does not matter', () {
      final one = fingerprintOf({'a.dart': 'sha256:11', 'b.dart': 'sha256:22'});
      final other = fingerprintOf({
        'b.dart': 'sha256:22',
        'a.dart': 'sha256:11',
      });
      expect(one, _twoFilesFingerprint);
      expect(other, one);
    });

    test('changes when a hash or a path changes', () {
      final base = fingerprintOf({
        'a.dart': 'sha256:11',
        'b.dart': 'sha256:22',
      });
      expect(
        fingerprintOf({'a.dart': 'sha256:11', 'b.dart': 'sha256:23'}),
        isNot(base),
      );
      expect(
        fingerprintOf({'a.dart': 'sha256:11', 'c.dart': 'sha256:22'}),
        isNot(base),
      );
      expect(fingerprintOf({'a.dart': 'sha256:11'}), isNot(base));
    });
  });
}
