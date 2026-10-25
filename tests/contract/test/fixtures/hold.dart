// Owns a session of the storage at a place, as the process that runs it does,
// and writes to it what the test asks on stdin. test/contract_test.dart runs
// it.
//
//   hold <place> create        creates a session of `review`, prints its id
//   hold <place> open <id>     opens the session, prints its id, or `busy`
//
// Then, a line each on stdin, each answered with a line once done:
//
//   effect <name>              creates an effect and writes effect-started;
//                              prints the effect's id
//   log <effect id> <text>     adds <text> and a newline to the effect's log
//   finish <effect id>         writes the effect's output and effect-finished
//   end                        writes session-finished and lets the session go
//   release                    lets the session go
//
// It exits when stdin closes, owning the session until then.
import 'dart:convert';
import 'dart:io';

import 'package:nanoflow_model/nanoflow_model.dart';

import '../support/places.dart';

Future<void> main(List<String> args) async {
  final store = storeAt(args[0]);
  final OpenSession session;
  switch (args.sublist(1)) {
    case ['create']:
      session = await store.createSession(
        workflow: 'review',
        graph: null,
        input: (value: 'main'),
        code: null,
        owner: thisProcess(),
      );
    case ['open', final id]:
      try {
        session = (await store.openSession(id, owner: thisProcess()))!;
      } on SessionBusyException {
        print('busy');
        return;
      }
    default:
      throw ArgumentError.value(args, 'args');
  }
  print(session.session.id);
  final effects = <String, Effect>{};
  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    final words = line.split(' ');
    switch (words) {
      case ['effect', final name]:
        final effect = await session.createEffect(
          name: name,
          key: '$name#1@e3b0c44298fc1c14',
          after: null,
          place: null,
        );
        effects[effect.id] = effect;
        await session.appendEvent(
          EffectStarted(time: systemClock(), effectId: effect.id),
        );
        print(effect.id);
      case ['log', final effectId, ...final text]:
        final log = session.openLog(effectId)
          ..add(utf8.encode('${text.join(' ')}\n'));
        await log.close();
        print('ok');
      case ['finish', final effectId]:
        final outputId = await session.writeDocument('$effectId done');
        await session.appendEvent(
          EffectFinished(
            time: systemClock(),
            effectId: effectId,
            outputId: outputId,
          ),
        );
        await session.setEffectOutput(effects[effectId]!, outputId);
        print('ok');
      case ['end']:
        final outputId = await session.writeDocument('reviewed');
        await session.appendEvent(
          SessionFinished(time: systemClock(), outputId: outputId),
        );
        await session.release();
        print('ok');
      case ['release']:
        await session.release();
        print('ok');
      default:
        throw ArgumentError.value(line, 'line');
    }
  }
}
