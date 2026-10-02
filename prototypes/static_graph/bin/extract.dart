// Prints the graph of a workflow function in the README graph format.
//
//   dart run bin/extract.dart <file.dart> <function>
//
// What could not be drawn goes to stderr, a line each.
import 'dart:convert';
import 'dart:io';

import 'package:static_graph/extract.dart';

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln('usage: dart run bin/extract.dart <file.dart> <function>');
    exitCode = 2;
    return;
  }
  try {
    final (:graph, :warnings) = await extractGraph(args[0], args[1]);
    warnings.forEach(stderr.writeln);
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(graph));
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    exitCode = 1;
  }
}
