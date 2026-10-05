// Records sessions that go on after a call, run by the real library, for the
// UI's tests of the forks a session passed
// (apps/nanoflow_ui/test/state/passes_test.dart): runs the workflows of
// test/fixtures/calls with nanoflow, describes the fixture, and writes the
// fixture's graph file and the sessions as the library wrote them.
//
//   cd tests/e2e
//   dart run tool/record_calls.dart ../../apps/nanoflow_ui/test/state/fixtures/calls
//
// Run it again whenever the library changes how it keys effects or what it
// writes for them (decision D1).

// The fixture is a package without a pubspec (decision D11): its library
// has no package: name to import it by.
// ignore: avoid_relative_lib_imports
import '../test/fixtures/calls/lib/run_all.dart';
import 'recording.dart';

Future<void> main(List<String> args) => recordFixture(args, 'calls', runAll);
