/// The graphs of nodes of a package, read from its code with the Dart
/// analyzer and never run: [describePackage] builds the graph file of each
/// graph (`<graph>.graph.json`, next to its Dart file) the UI draws, and
/// [runDescribe], the `nanoflow_describe` command, writes them and keeps
/// them fresh.
library;

export 'src/command.dart' show runDescribe;
export 'src/describe.dart' show DescribeResult, describePackage;
