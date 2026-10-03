/// The graph of a package's workflow functions, read from its code with the
/// Dart analyzer and never run: [describePackage] builds the graph file
/// (`nanoflow.graph.json`) the UI draws.
library;

export 'src/describe.dart' show DescribeResult, describePackage;
