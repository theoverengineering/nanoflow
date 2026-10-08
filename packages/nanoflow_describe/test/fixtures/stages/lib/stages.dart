// A switch on a local variable, each path taking the way it already knows:
// a stage chosen by an if before the loop, `stage = …; continue loop` as a
// jump, a break back to the same case; the fork drawn only for a path whose
// value is not known; a variable set in a local function left alone; and a
// switch outside a loop, where only the case taken is drawn.
import 'package:nanoflow/nanoflow.dart';

enum Stage { write, review, done }

Future<void> agree(Flow f, bool written) async {
  Stage stage;
  if (written) {
    stage = Stage.review;
  } else {
    stage = Stage.write;
  }
  loop:
  while (true) {
    switch (stage) {
      case Stage.write:
        await f.effect('write', () => print('write'));
        stage = Stage.review;
        continue loop;
      case Stage.review:
        final ok = await f.effect('review', () => true);
        if (ok) {
          stage = Stage.done;
        } else {
          stage = Stage.write;
        }
        continue loop;
      case Stage.done:
        await f.effect('declare', () => print('declare'));
        return;
    }
  }
}

Future<void> pick(Flow f, Stage Function() next) async {
  var stage = Stage.write;
  loop:
  while (true) {
    switch (stage) {
      case Stage.write:
        await f.effect('write', () => print('write'));
        stage = next();
        continue loop;
      case Stage.review:
        await f.effect('review', () => print('review'));
        break;
      case Stage.done:
        return;
    }
  }
}

Future<void> captured(Flow f) async {
  var stage = Stage.write;
  void advance() {
    stage = Stage.done;
  }

  loop:
  while (true) {
    switch (stage) {
      case Stage.write:
        await f.effect('write', () => print('write'));
        advance();
        continue loop;
      case Stage.review:
      case Stage.done:
        return;
    }
  }
}

Future<void> once(Flow f) async {
  final stage = Stage.review;
  switch (stage) {
    case Stage.write:
      await f.effect('write', () => print('write'));
    case Stage.review:
      await f.effect('review', () => print('review'));
    case Stage.done:
      await f.effect('declare', () => print('declare'));
  }
}

Future<void> fallback(Flow f) async {
  final stage = Stage.done;
  switch (stage) {
    case Stage.write:
      await f.effect('write', () => print('write'));
    default:
      await f.effect('other', () => print('other'));
  }
}
