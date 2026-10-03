/// The graph of a package's workflow functions, read from its code with the
/// Dart analyzer and never run: [describePackage] builds the graph file
/// (`nanoflow.graph.json`) the UI draws, and [runDescribe], the
/// `nanoflow_describe` command, writes it and keeps it fresh.
library;

export 'src/command.dart' show runDescribe;
export 'src/describe.dart' show DescribeResult, describePackage;
