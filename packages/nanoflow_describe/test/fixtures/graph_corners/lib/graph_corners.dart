// Corners of graphs: a route's switch on a record of types a switch must
// cover, which needs no default, beside one on a record that does; nodes
// documented by block comments, one of them empty.
// ignore_for_file: slash_for_doc_comments
import 'package:nanoflow/nanoflow.dart';

enum Speed { slow, fast }

final class Alert {
  const Alert(this.urgent, this.speed, this.quiet, this.tries);

  final bool urgent;
  final Speed speed;
  final bool quiet;
  final int tries;
}

/** Takes an alert in. */
final receive = node('receive', (Alert alert) async => alert);

/**
 * Pages someone.
 *
 * Only when it is urgent.
 */
final page = node('page', (Alert alert) async => alert);

/**/
final mail = node('mail', (Alert alert) async => alert);

final log = node('log', (Alert alert) async => alert);

final chat = node('chat', (Alert alert) async => alert);

final route = Graph<Alert, Alert>('route', [
  Graph.start(receive).next((alert) {
    switch ((alert.urgent, (alert.speed, alert.quiet))) {
      case (true, _):
        return page(alert);
      case (false, (Speed.slow, _)):
        return mail(alert);
      case (false, (Speed.fast, true)):
        return log(alert);
      case (false, (Speed.fast, false)):
        return chat(alert);
    }
  }),
]);

// A record with an int: the switch need not cover it.
final retry = Graph<Alert, Alert>('retry', [
  Graph.start(receive).next((alert) {
    switch ((alert.urgent, alert.tries)) {
      case (true, _):
        return page(alert);
      case (false, 0):
        return mail(alert);
    }
    return null;
  }),
]);
