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

sealed class Step {}

final class Draft extends Step {
  Draft(this.text);
  final String text;
}

final class Check extends Step {
  Check(this.text);
  final String text;
}

Future<void> carry(Flow f, bool drafted) async {
  Step step;
  if (drafted) {
    step = Check('kept');
  } else {
    step = Draft('fresh');
  }
  loop:
  while (true) {
    switch (step) {
      case Draft(:final text):
        final next = await f.effect('draft', () => '$text!');
        step = Check(next);
        continue loop;
      case Check(:final text):
        final ok = await f.effect('check', () => text.isNotEmpty);
        if (ok) return;
        step = Draft(text);
        continue loop;
    }
  }
}

Future<void> refutable(Flow f) async {
  Step step = Draft('');
  loop:
  while (true) {
    switch (step) {
      case Draft(text: ''):
        await f.effect('empty', () => print('empty'));
        step = Check('filled');
        continue loop;
      case Draft():
        await f.effect('draft', () => print('draft'));
        return;
      case Check():
        await f.effect('check', () => print('check'));
        return;
    }
  }
}
