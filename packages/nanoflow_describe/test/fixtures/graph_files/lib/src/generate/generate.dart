// A graph that calls compressIdea, with a part of its library.
import 'package:nanoflow/nanoflow.dart';

import '../compress/compress.dart';
import '../nodes.dart';

part 'ideas.dart';

/// Thinks up an idea and makes it shorter.
final generateIdeas = Graph<String, String>('generateIdeas', [
  Graph.start(survey).next((topic) => compressIdea(Idea(topic).text)),
]);
