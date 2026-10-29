// Nodes the graphs share, and more of them through the export.
import 'package:nanoflow/nanoflow.dart';

export 'more_nodes.dart';

final survey = node('survey', (String topic) async => topic);

final shorten = node('shorten', (String idea) async => idea);

const _rank = 'rank';

// Named by a constant: a warning in no graph's declaration.
final rank = node(_rank, (String idea) async => idea.length);
