// A function that is not a route and reads a file: the call of it from a
// route reaches the read.
import 'dart:io';

/// The configuration in `config.json`.
String loadConfig() => File('config.json').readAsStringSync();
