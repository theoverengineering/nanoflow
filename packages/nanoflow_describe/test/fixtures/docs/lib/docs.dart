// Doc comments of functions and effects, and which of them belong to what
// (node docs design §2).
// ignore_for_file: slash_for_doc_comments
import 'package:nanoflow/nanoflow.dart';

/// Ships a release.
///
/// Builds it first: see [Shipper.ship].
Future<String> release(Flow f, List<String> names) async {
  /// Takes the version to ship.
  final version = await f.effect('version', () => '1.0');

  /// Builds it.
  await f.effect('build', () => print('build $version'));

  /// Takes both parts of the version.
  final (major, minor) = await f.effect('parts', () => (1, 0));
  print('$major.$minor');

  /// Over the list, whose effects have their own.
  await Future.wait([
    /// Tags the commit.
    f.effect('tag', () => print('tag')),

    /// Writes the notes,
    /// two lines of them.
    f.effect('notes', () => print('notes')),
  ]);

  /// Over two effects: neither takes it.
  await Future.wait([
    f.effect('mirror', () => print('mirror')),
    f.effect('archive', () => print('archive')),
  ]);

  /// Over an if: not the effect's.
  if (names.isEmpty) {
    await f.effect('skip', () => print('skip'));
  }

  /// Over a loop: not the effect's.
  while (names.length > 3) {
    await f.effect('trim', () => names.removeLast());
  }

  // A plain comment: no doc.
  await f.effect('plain', () => print('plain'));

  /// Broken off by a plain comment, so not this line.
  // a plain comment in between
  /// Only this line.
  await f.effect('tail', () => print('tail'));

  ///
  ///
  await f.effect('blank', () => print('blank'));

  /// Before a blank line.

  /// After it.
  await f.effect('spaced', () => print('spaced'));

  await Shipper().ship(f);

  /// Gives the version.
  return f.effect('result', () => version);
}

/**/
Future<void> bare(Flow f) async {
  /**/
  await f.effect('bare', () => print('bare'));
}

class Shipper {
  /**
   * Ships through a block comment.
   *
   * Second paragraph.
   */
  Future<void> ship(Flow f) async {
    await f.effect('ship', () => print('ship'));
  }
}
