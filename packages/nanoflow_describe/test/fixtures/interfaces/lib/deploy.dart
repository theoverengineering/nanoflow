// A call through an interface: which implementation runs is known only when
// the session runs, so the call goes to every implementation that has effects.
import 'package:nanoflow/nanoflow.dart';

abstract interface class Notifier {
  Future<void> notify(Flow f, String message);
}

class ChatNotifier implements Notifier {
  @override
  Future<void> notify(Flow f, String message) async {
    await f.effect('post', () => print('chat: $message'));
  }
}

class MailNotifier implements Notifier {
  @override
  Future<void> notify(Flow f, String message) async {
    final to = await f.effect('find-owners', () => 'owners@example.com');
    await f.effect('send-mail', () => print('mail to $to: $message'));
  }
}

/// Calls no effect: not a function with effects, so not one of the calls.
class QuietNotifier implements Notifier {
  @override
  Future<void> notify(Flow f, String message) async {}
}

Future<void> deploy(Flow f, String service) async {
  await f.effect('roll-out', () => print('roll out $service'));
  await notifierFor(service).notify(f, '$service deployed');
}

Notifier notifierFor(String service) => switch (service) {
  'billing' => MailNotifier(),
  'search' => ChatNotifier(),
  _ => QuietNotifier(),
};
