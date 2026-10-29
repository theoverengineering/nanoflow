// Starts a session of `review` in the project directory and with the work
// directory its arguments name, prints the session's id and runs it to its
// end. test/resume_test.dart kills it while the effect `inspect` waits.
import 'package:nanoflow/src/flow.dart';

import 'review.dart';

Future<void> main(List<String> args) async {
  final session = await Flow(directory: args[0]).startWorkflow(review, args[1]);
  print(session.id);
  await session.result;
}
