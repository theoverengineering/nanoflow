// A function that is not a graph function and reads a file: the call of it
// from a graph function reaches the read.
import 'dart:io';

/// The configuration in `config.json`.
String loadConfig() => File('config.json').readAsStringSync();
