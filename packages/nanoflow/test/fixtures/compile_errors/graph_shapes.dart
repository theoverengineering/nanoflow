// Graphs the compiler must reject. A line ending in `// error: <code>` must
// have an error with that code, the comment above it says what is wrong, and
// no other line may have an error; test/compile_errors_test.dart checks.
import 'package:nanoflow/nanoflow.dart';

enum Verdict { accepted, returned }

final read = node((String s) => s.length);
final count = node((int n) => n > 0);
final show = node((bool b) {});
final word = fork((bool b) => b ? 'yes' : 'no');
final zero = fork((int n) => n == 0);
final grade = fork((bool b) => b ? Verdict.accepted : Verdict.returned);

// The same nodes, written correctly; a set may hold workers and forks.
final ok1 = Graph.start(read).next(count).next({show, word});
final ok2 = Graph.start(zero).then(count).otherwise({count});
final ok3 = Graph.start(word).then({'yes': show, 'no': {}});
final ok4 = Graph.part(grade).then({Verdict.accepted: show});

// A target node that does not take the data.
final g1 = Graph.start(read).next(show); // error: argument_type_not_assignable

// A set with a node that does not take the data.
final g2 = Graph.start(read)
    .next({count, show}); // error: argument_type_not_assignable

// A set of a worker and a fork, one of which does not take the data.
final g3 = Graph.start(count)
    .next({show, zero}); // error: argument_type_not_assignable

// Going on after a set.
final g4 = Graph.start(read)
    .next({count})
    .next(show); // error: undefined_method

// An if target set with a node that does not take the data.
final g5 = Graph.start(zero)
    .then({count, show}); // error: set_element_type_not_assignable

// A switch target that does not take the data.
final g6 = Graph.start(word)
    .then({'yes': read}); // error: map_value_type_not_assignable

// An outcome of the wrong type.
final g7 = Graph.start(word)
    .then({1: show}); // error: map_key_type_not_assignable

// A typo in an enum outcome.
final g8 = Graph.part(grade)
    .then({Verdict.acepted: show}); // error: undefined_enum_constant

// then on a worker.
final g9 = Graph.start(read).then(count); // error: undefined_method

// next on a fork.
final g10 = Graph.start(zero).next(count); // error: undefined_method

// Going on after a fork.
final g11 = Graph.start(zero).then(count).next(show); // error: undefined_method

// A part as a target.
final g12 = Graph.start(read)
    .next(Graph.part(count)); // error: argument_type_not_assignable
