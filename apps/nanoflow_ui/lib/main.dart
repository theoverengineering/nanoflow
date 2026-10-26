import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'platform/shell.dart';
import 'start/launch.dart';
import 'start/recent_graphs.dart';

/// Starts the app, on the graph [args] name when they name one:
/// `nanoflow_ui <graph file> [--store <place>] [--session <id>]`.
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final recent = RecentGraphs(await SharedPreferences.getInstance());
  Launch? launch;
  String? launchError;
  try {
    launch = parseLaunch(args);
  } on FormatException catch (e) {
    launchError = e.message;
  }
  runApp(
    NanoflowApp(
      recent: recent,
      shell: Shell(),
      launch: launch,
      launchError: launchError,
    ),
  );
}
