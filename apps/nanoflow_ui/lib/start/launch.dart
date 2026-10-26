import 'package:path/path.dart' as p;

import '../state/store_place.dart';
import 'recent_graphs.dart';

/// A graph to open as the app starts (storage design §6.8): the graph file,
/// the store of its sessions — `null` for `runs/` next to it — and the
/// session to select once the feed gives it.
typedef Launch = ({String path, StorePlace? store, String? session});

/// What the app was started with:
/// `nanoflow_ui <graph file> [--store <place>] [--session <id>]`; `null` for
/// no graph file, as when it is started from the Dock.
///
/// Leaves out what macOS adds: `-psn_…`, and `-NS…` with its value, as
/// Xcode's `-NSDocumentRevisionsDebugMode YES`. Throws a [FormatException]
/// that says what is wrong with the rest.
Launch? parseLaunch(List<String> args, {String? home}) {
  String? path;
  StorePlace? store;
  String? session;
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg.startsWith('-psn_')) continue;
    if (arg.startsWith('-NS')) {
      i++;
      continue;
    }
    String value() {
      if (i + 1 >= args.length) throw FormatException('$arg needs a value');
      return args[++i];
    }

    switch (arg) {
      case '--store':
        store = StorePlace.parse(value(), home: home);
      case '--session':
        session = value();
      case _ when arg.startsWith('-'):
        throw FormatException('unknown option $arg');
      case _ when path != null:
        throw FormatException('one graph file only, not also $arg');
      default:
        path = p.normalize(p.absolute(arg));
    }
  }
  if (path == null) {
    if (store != null || session != null) {
      throw const FormatException('--store and --session need a graph file');
    }
    return null;
  }
  if (!isGraphFile(path)) {
    throw FormatException('$path is not a graph file (*.graph.json)');
  }
  return (path: path, store: store, session: session);
}
