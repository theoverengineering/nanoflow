import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'platform/shell.dart';
import 'start/recent_graphs.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final recent = RecentGraphs(await SharedPreferences.getInstance());
  runApp(NanoflowApp(recent: recent, shell: Shell()));
}
