import 'dart:math' as math;

import 'coordinates.dart';
import 'geometry.dart';
import 'layout_graph.dart';
import 'ports.dart';

/// What turns in a gap between layers.
enum TurnKind {
  /// A loop going up or down beside its node's exits.
  loopOut,

  /// A forward arrow changing height on its way to the next layer.
  forward,

  /// A back arrow going down from its exit to its lane under the graph.
  backOut,

  /// A back arrow coming up from its lane to its input.
  backIn,

  /// A loop coming back to its node's input.
  loopIn,
}

/// One turn in a gap: a vertical (or a 45° diagonal) with horizontal pieces
/// attached on its left and right.
final class Turn {
  Turn._(this.kind, this.edge, this.ends, {this.seg});

  final TurnKind kind;
  final GEdge edge;

  /// The forward piece, for [TurnKind.forward].
  final Seg? seg;

  /// Where horizontal pieces attach: their y, and whether they go off to the
  /// left of the vertical (true) or to the right. The first is where the
  /// arrow comes from, the second where it goes.
  final List<(double, bool)> ends;

  double get top => math.min(ends[0].$1, ends[1].$1);

  double get bottom => math.max(ends[0].$1, ends[1].$1);

  double get rise => bottom - top;

  /// The x of the vertical; for a diagonal, where it starts.
  double x = 0;

  /// Whether the turn is a 45° diagonal instead of a vertical.
  bool diagonal = false;

  /// The x where the turn ends: the vertical, or the diagonal's far end.
  double get end => diagonal ? x + rise : x;

  /// The least x for the turn, and how much room it needs right of [end]
  /// before the next layer's tiles, as a vertical and as a diagonal.
  double _least = 0;
  double _leastDiagonal = 0;
  double _room = 0;
  double _roomDiagonal = 0;

  double get least => diagonal ? _leastDiagonal : _least;

  double get room => diagonal ? _roomDiagonal : _room;

  @override
  String toString() => '$kind $edge x=$x${diagonal ? ' diagonal' : ''}';
}

/// The x of every layer and of every turn.
final class Lanes {
  Lanes._(this.left);

  /// The x of each layer's tiles' left side.
  final List<double> left;

  /// The turns of forward pieces that change height.
  final Map<Seg, Turn> forward = {};

  /// Back arrows going down, and coming up.
  final Map<GEdge, Turn> backOut = {};
  final Map<GEdge, Turn> backIn = {};

  /// Loops going round, and coming back.
  final Map<GEdge, Turn> loopOut = {};
  final Map<GEdge, Turn> loopIn = {};
}

/// The least horizontal gap between the tiles of neighbouring layers.
const double minLayerGap = 40;

/// How far an arrow keeps from texts and marks it passes.
const double clearance = 8;

/// Step 7: the lanes in every gap between layers, and with them the x of the
/// layers.
///
/// A turn in a gap takes a lane: its own x, a lane gap right of the turn
/// before it. Lanes are ordered for the fewest crossings — a ladder down
/// turns further right the higher it starts, a ladder up the lower it starts,
/// back arrows and loops nest — and start right of every label and counter
/// room they pass. A small change of height becomes a 45° diagonal where
/// that fits in the gap. A gap is as wide as its labels, lanes, the straight
/// piece before an input and the arrowhead need.
///
/// [frames] are the nodes' frames with tiles at x = 0; [depth] is the y of
/// every back arrow's lane under the graph.
Lanes assignLanes(
  List<List<Item>> layers,
  Map<GNode, Ports> ports,
  Map<GNode, NodeFrame> frames,
  Map<GEdge, double> depth,
  LayoutOptions options,
) {
  final lanes = Lanes._(List<double>.filled(layers.length, 0));
  final r = options.cornerRadius;
  final r45 = r * math.tan(math.pi / 8);
  final entry =
      options.minInputStraight +
      options.arrowLength +
      options.arrowGap +
      options.barWidth / 2;
  var right = 0.0;
  for (var gap = -1; gap < layers.length; gap++) {
    final leftNodes = gap < 0
        ? const <GNode>[]
        : [for (final i in layers[gap]) ?i.node];
    final rightNodes = gap + 1 < layers.length
        ? [for (final i in layers[gap + 1]) ?i.node]
        : const <GNode>[];
    final leftX = gap < 0 ? 0.0 : lanes.left[gap];
    final leftEdge = gap < 0 ? 0.0 : right;
    // Obstacles of the left layer, absolute; of the right one, relative to
    // its tiles' left side.
    final leftObstacles = [
      for (final node in leftNodes)
        for (final rect in frames[node]!.obstacles) rect.shift(Point(leftX, 0)),
    ];
    final rightObstacles = [
      for (final node in rightNodes) ...frames[node]!.obstacles,
    ];

    final turns = <Turn>[];
    void setRoom(Turn turn, {required double reach}) {
      // Left: past the own label and every mark the turn's heights pass.
      var least = reach;
      for (final rect in leftObstacles) {
        if (_spans(turn, rect)) {
          least = math.max(least, rect.right + clearance);
        }
      }
      turn._least = least + r;
      turn._leastDiagonal = least + r45;
      // Right: the straight piece and arrowhead before an input, and every
      // mark of the next layer the turn's heights pass.
      var room = 0.0;
      var roomDiagonal = 0.0;
      final into = turn.ends[1];
      if (!into.$2) {
        final toInput = switch (turn.kind) {
          TurnKind.forward => !turn.seg!.to.isPass,
          TurnKind.backIn || TurnKind.loopIn => true,
          _ => false,
        };
        final straight = toInput ? entry : options.laneGap / 2;
        room = r + straight;
        roomDiagonal = r45 + straight;
      }
      for (final rect in rightObstacles) {
        if (_spans(turn, rect)) {
          final need = clearance - rect.left;
          room = math.max(room, need);
          roomDiagonal = math.max(roomDiagonal, need);
        }
      }
      turn._room = room;
      turn._roomDiagonal = roomDiagonal;
    }

    double reachOf(GEdge edge) =>
        leftEdge + frames[edge.from]!.exits[edge.exit]!.reach;

    // Pieces that keep their height still need room for their label, the
    // straight piece and the arrowhead.
    var needed = gap < 0 ? 0.0 : right + minLayerGap;
    if (gap >= 0) {
      for (final item in layers[gap]) {
        for (final seg in item.outs) {
          final from = outY(seg, ports);
          final to = inY(seg, ports);
          final start = item.isPass ? leftEdge : reachOf(seg.edge);
          final finish = seg.to.isPass ? options.laneGap : entry;
          if ((to - from).abs() > _flat) {
            final turn = Turn._(TurnKind.forward, seg.edge, [
              (from, true),
              (to, false),
            ], seg: seg);
            setRoom(turn, reach: start);
            turns.add(turn);
            lanes.forward[seg] = turn;
          } else {
            needed = math.max(needed, start + finish);
          }
        }
      }
      for (final node in leftNodes) {
        final port = ports[node]!;
        final y = node.item.y;
        for (final exit in node.exits) {
          for (final edge in exit.edges) {
            if (edge.kind == EdgeKind.back) {
              final turn = Turn._(TurnKind.backOut, edge, [
                (y + port.exitAt[edge]!, true),
                (depth[edge]!, true),
              ]);
              setRoom(turn, reach: reachOf(edge));
              turns.add(turn);
              lanes.backOut[edge] = turn;
            } else if (edge.kind == EdgeKind.loop) {
              final turn = Turn._(TurnKind.loopOut, edge, [
                (y + port.exitAt[edge]!, true),
                (y + _loopOffset(edge, port, options), true),
              ]);
              setRoom(turn, reach: reachOf(edge));
              turns.add(turn);
              lanes.loopOut[edge] = turn;
            }
          }
        }
      }
    }
    for (final node in rightNodes) {
      final port = ports[node]!;
      final y = node.item.y;
      for (final edge in port.inputs) {
        if (edge.kind == EdgeKind.back) {
          final turn = Turn._(TurnKind.backIn, edge, [
            (depth[edge]!, false),
            (y + port.inputAt[edge]!, false),
          ]);
          setRoom(turn, reach: leftEdge + clearance);
          turns.add(turn);
          lanes.backIn[edge] = turn;
        } else if (edge.kind == EdgeKind.loop) {
          final turn = Turn._(TurnKind.loopIn, edge, [
            (y + _loopOffset(edge, port, options), false),
            (y + port.inputAt[edge]!, false),
          ]);
          setRoom(turn, reach: leftEdge + clearance);
          turns.add(turn);
          lanes.loopIn[edge] = turn;
        }
      }
    }
    // Marks of the two layers at the same height must not meet.
    for (final a in leftObstacles) {
      for (final b in rightObstacles) {
        if (a.top < b.bottom + clearance && b.top < a.bottom + clearance) {
          needed = math.max(needed, a.right + 2 * clearance - b.left);
        }
      }
    }

    final ordered = _orderTurns(turns, options.laneGap);
    double width() {
      var next = needed;
      for (final turn in ordered) {
        next = math.max(next, turn.end + turn.room);
      }
      return next;
    }

    _placeTurns(ordered, options.laneGap);
    _slant(ordered, width(), options);
    final next = width();

    if (gap + 1 < layers.length) {
      lanes.left[gap + 1] = next;
      right = next + options.tile;
    }
  }
  return lanes;
}

/// Heights that differ less than this run straight.
const double _flat = 1e-6;

double _loopOffset(GEdge edge, Ports port, LayoutOptions options) {
  final above = port.loopsAbove.indexOf(edge);
  return loopOffset(
    edge.from,
    port,
    options,
    below: above < 0,
    index: above < 0 ? port.loopsBelow.indexOf(edge) : above,
  );
}

/// Whether [turn]'s heights pass [rect], with room to spare.
bool _spans(Turn turn, Rect rect) =>
    turn.top < rect.bottom + clearance && rect.top - clearance < turn.bottom;

/// What putting [a] left of [b] costs: one for each crossing, and much more
/// for pieces that would run along each other closer than [near].
///
/// A piece going off right of [a] at a height [b] spans crosses [b], and a
/// piece coming in left of [b] at a height [a] spans crosses [a]. A piece
/// going off right of [a] and one coming in left of [b] at nearly the same
/// height overlap between the two verticals: [a] must go right of [b] then.
int _cost(Turn a, Turn b, double near) {
  var count = 0;
  for (final (y, onLeft) in a.ends) {
    if (onLeft) continue;
    if (_inside(y, b)) count++;
    for (final (other, otherOnLeft) in b.ends) {
      if (otherOnLeft && (other - y).abs() < near) count += _alongside;
    }
  }
  for (final (y, onLeft) in b.ends) {
    if (onLeft && _inside(y, a)) count++;
  }
  return count;
}

/// The cost of two pieces running along each other: worse than any number
/// of crossings a gap can have.
const int _alongside = 1000;

bool _inside(double y, Turn turn) =>
    y > turn.top + _flat && y < turn.bottom - _flat;

/// Orders turns left to right for the fewest crossings.
///
/// Pieces that would run along each other decide some pairs outright; the
/// turns go in an order that keeps those pairs, each where it costs least
/// among the turns before it (rightmost of equals). Then turns move one at a
/// time to the place that costs least, while that lowers the cost.
List<Turn> _orderTurns(List<Turn> turns, double near) {
  final pending = [...turns]
    ..sort((a, b) {
      final c = a.kind.index.compareTo(b.kind.index);
      return c != 0 ? c : a.edge.index.compareTo(b.edge.index);
    });
  // must[t]: the turns that have to be left of t.
  final must = <Turn, Set<Turn>>{for (final t in pending) t: {}};
  for (final a in pending) {
    for (final b in pending) {
      if (!identical(a, b) &&
          _cost(b, a, near) < _alongside &&
          _cost(a, b, near) >= _alongside) {
        must[a]!.add(b);
      }
    }
  }
  // What [turn] costs at [at] among [others], whose order stays.
  int costAt(List<Turn> others, Turn turn, int at) {
    var cost = 0;
    for (var j = 0; j < others.length; j++) {
      cost += j < at
          ? _cost(others[j], turn, near)
          : _cost(turn, others[j], near);
    }
    return cost;
  }

  final order = <Turn>[];
  while (pending.isNotEmpty) {
    // The first turn whose required left neighbours are all placed; with a
    // cycle among them, the first turn.
    final turn = pending.firstWhere(
      (t) => must[t]!.every(order.contains),
      orElse: () => pending.first,
    );
    pending.remove(turn);
    var from = 0;
    for (var j = 0; j < order.length; j++) {
      if (must[turn]!.contains(order[j])) from = j + 1;
    }
    var bestAt = from;
    var best = -1;
    for (var at = from; at <= order.length; at++) {
      final cost = costAt(order, turn, at);
      if (best < 0 || cost <= best) {
        best = cost;
        bestAt = at;
      }
    }
    order.insert(bestAt, turn);
  }
  var moved = true;
  while (moved) {
    moved = false;
    for (var i = 0; i < order.length; i++) {
      final turn = order.removeAt(i);
      var bestAt = i;
      var best = costAt(order, turn, i);
      for (var at = 0; at <= order.length; at++) {
        final cost = costAt(order, turn, at);
        if (cost < best) {
          best = cost;
          bestAt = at;
        }
      }
      order.insert(bestAt, turn);
      if (bestAt != i) moved = true;
    }
  }
  return order;
}

/// Turns forward turns into 45° diagonals where they fit: a small change of
/// height goes smoothly instead of taking a lane.
///
/// Only changes of height up to two corners and a lane gap slant: a vertical
/// would barely have a straight part there, while a longer slant reads worse
/// than a lane. A diagonal must fit in the gap as the lanes made it ([width]
/// is where the next layer's tiles start), between its own straight pieces,
/// and nothing may turn in its stretch of x at heights near its own; turns
/// at other heights may share that stretch, since a slanted piece does not
/// line up with them. Smaller changes of height go first.
void _slant(List<Turn> order, double width, LayoutOptions options) {
  final laneGap = options.laneGap;
  final most = 2 * options.cornerRadius + laneGap;
  bool near(Turn a, Turn b) =>
      a.top < b.bottom + laneGap && b.top < a.bottom + laneGap;
  final candidates =
      [
        for (final turn in order)
          if (turn.kind == TurnKind.forward && turn.rise <= most) turn,
      ]..sort((a, b) {
        final c = a.rise.compareTo(b.rise);
        return c != 0 ? c : a.edge.index.compareTo(b.edge.index);
      });
  for (final turn in candidates) {
    final i = order.indexOf(turn);
    var x = turn._leastDiagonal;
    for (var j = 0; j < i; j++) {
      if (near(order[j], turn)) x = math.max(x, order[j].end + laneGap);
    }
    var fits = x + turn.rise + turn._roomDiagonal <= width + 1e-9;
    for (var j = i + 1; j < order.length && fits; j++) {
      if (near(order[j], turn) && x + turn.rise + laneGap > order[j].x) {
        fits = false;
      }
    }
    if (fits) {
      turn
        ..diagonal = true
        ..x = x;
    }
  }
}

/// Gives each turn its x, left to right: the least it may take, and a lane
/// gap right of the turn before. Turns never share an x, even at heights far
/// apart: two verticals in line read as one arrow.
///
/// A piece going off right of a turn at nearly the height of a piece coming
/// in left of an earlier turn would seem to go on from it: such turns keep
/// three lane gaps apart, so that the break between the pieces shows.
void _placeTurns(List<Turn> order, double laneGap) {
  for (var i = 0; i < order.length; i++) {
    final turn = order[i];
    var x = i == 0
        ? turn.least
        : math.max(turn.least, order[i - 1].end + laneGap);
    for (var j = 0; j < i; j++) {
      if (_continues(order[j], turn, laneGap)) {
        x = math.max(x, order[j].end + 3 * laneGap);
      }
    }
    turn.x = x;
  }
}

/// Whether a piece going off right of [b] is nearly level with a piece
/// coming in left of [a].
bool _continues(Turn a, Turn b, double near) {
  for (final (y, onLeft) in a.ends) {
    if (!onLeft) continue;
    for (final (other, otherOnLeft) in b.ends) {
      if (!otherOnLeft && (other - y).abs() < near) return true;
    }
  }
  return false;
}
