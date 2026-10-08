import 'coordinates.dart';
import 'layout_graph.dart';
import 'ports.dart';

/// The most sweeps step 4 makes; each goes left to right and back.
const int maxSweeps = 24;

/// How far under the packed layers step 4 takes back arrows to run when it
/// sorts by medians: below everything, where their lanes are unless they
/// are later found to cross less over the graph.
const double backLaneDepth = 200;

/// Step 4: orders the items of every layer for fewer crossings.
///
/// Starts from the order of step 1's walk. A sweep left to right sorts each
/// layer by the median height of the exits its arrows come from; right to
/// left, by the median height of the inputs they go to. Heights are of ports,
/// not of item middles, with the layers packed tight. A back arrow comes from
/// and goes to the graph's bottom, where its lane is unless it later goes
/// over the graph, so nodes with back arrows sink. Sweeps go on while the count of crossings does not grow and
/// the order is new, at most [maxSweeps]; the order with the fewest
/// crossings stays. Ties keep the graph's declaration order. Sets
/// [Item.order].
void orderLayers(
  LayoutGraph graph,
  List<List<Item>> layers,
  LayoutOptions options,
) {
  var ports = <GNode, Ports>{};
  var bottom = 0.0;
  void estimate() {
    ports = assignPorts(graph, options, below: const {}, backLevels: {});
    stackLayers(layers, ports, options);
    bottom = 0;
    for (final layer in layers) {
      if (layer.isNotEmpty && layer.last.y > bottom) bottom = layer.last.y;
    }
    bottom += backLaneDepth;
  }

  final declared = graph.nodes.length;
  int declaration(Item item) => item.node?.index ?? declared + item.edge!.index;

  void sortLayer(List<Item> layer, double? Function(Item) median) {
    final medians = {for (final item in layer) item: median(item)};
    final movable =
        [
          for (final item in layer)
            if (medians[item] != null) item,
        ]..sort((a, b) {
          final c = medians[a]!.compareTo(medians[b]!);
          return c != 0 ? c : declaration(a).compareTo(declaration(b));
        });
    var next = 0;
    for (var i = 0; i < layer.length; i++) {
      if (medians[layer[i]] != null) layer[i] = movable[next++];
    }
    for (var i = 0; i < layer.length; i++) {
      layer[i].order = i;
    }
  }

  double? byExits(Item item) {
    final node = item.node;
    return _median([
      for (final seg in item.ins) outY(seg, ports),
      if (node != null)
        for (final edge in node.inEdges)
          if (edge.kind == EdgeKind.back) bottom,
    ]);
  }

  double? byInputs(Item item) {
    final node = item.node;
    return _median([
      for (final seg in item.outs) inY(seg, ports),
      if (node != null)
        for (final exit in node.exits)
          for (final edge in exit.edges)
            if (edge.kind == EdgeKind.back) bottom,
    ]);
  }

  int crossings() {
    estimate();
    return countLayerCrossings(graph, layers, ports, bottom);
  }

  String signature() =>
      [for (final layer in layers) layer.map(declaration).join(',')].join(';');
  var best = _snapshot(layers);
  var fewest = crossings();
  var previous = fewest;
  final seen = {signature()};
  for (var sweep = 0; sweep < maxSweeps; sweep++) {
    for (var i = 1; i < layers.length; i++) {
      estimate();
      sortLayer(layers[i], byExits);
    }
    for (var i = layers.length - 2; i >= 0; i--) {
      estimate();
      sortLayer(layers[i], byInputs);
    }
    final count = crossings();
    if (count < fewest) {
      fewest = count;
      best = _snapshot(layers);
    }
    // A sweep that crosses as much may still have moved towards a better
    // order; a sweep that crosses more, or comes back to an order seen
    // before, ends the sweeps.
    if (count > previous || !seen.add(signature())) break;
    previous = count;
  }
  _restore(layers, best);
}

/// Crossings between neighbouring layers: pairs of pieces whose ends are in
/// opposite order, a back arrow counted as a piece from or to [bottom].
int countLayerCrossings(
  LayoutGraph graph,
  List<List<Item>> layers,
  Map<GNode, Ports> ports,
  double bottom,
) {
  var count = 0;
  for (var gap = 0; gap < layers.length - 1; gap++) {
    final pieces = <(double, double)>[
      for (final item in layers[gap])
        for (final seg in item.outs) (outY(seg, ports), inY(seg, ports)),
    ];
    for (final edge in graph.edges) {
      if (edge.kind != EdgeKind.back) continue;
      if (edge.from.layer == gap) {
        final from = edge.from.item.y + ports[edge.from]!.exitAt[edge]!;
        pieces.add((from, bottom));
      }
      if (edge.to.layer == gap + 1) {
        final to = edge.to.item.y + ports[edge.to]!.inputAt[edge]!;
        pieces.add((bottom, to));
      }
    }
    for (var i = 0; i < pieces.length; i++) {
      for (var j = i + 1; j < pieces.length; j++) {
        final a = pieces[i];
        final b = pieces[j];
        if ((a.$1 - b.$1) * (a.$2 - b.$2) < 0) count++;
      }
    }
  }
  return count;
}

double? _median(List<double> values) {
  if (values.isEmpty) return null;
  values.sort();
  final middle = values.length ~/ 2;
  return values.length.isOdd
      ? values[middle]
      : (values[middle - 1] + values[middle]) / 2;
}

List<List<Item>> _snapshot(List<List<Item>> layers) => [
  for (final layer in layers) [...layer],
];

void _restore(List<List<Item>> layers, List<List<Item>> snapshot) {
  for (var i = 0; i < layers.length; i++) {
    layers[i]
      ..clear()
      ..addAll(snapshot[i]);
    for (var j = 0; j < layers[i].length; j++) {
      layers[i][j].order = j;
    }
  }
}
