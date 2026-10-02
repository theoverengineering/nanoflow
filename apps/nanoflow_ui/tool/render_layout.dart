// Renders graph layouts in the mockups' style, to look at them.
//
//   dart run tool/render_layout.dart [--out <dir>] [--png] <graph.json>...
//
// Each graph file (the README graph format as JSON) becomes <dir>/<name>.svg,
// the default <dir> being the current directory; the layout's crossings and
// any broken rules are printed. With --png, headless Google Chrome also
// renders <dir>/<name>.png at twice the size. (`qlmanage -t` renders SVG too,
// but into a square of about 800 px, cutting off wider graphs.)
import 'dart:convert';
import 'dart:io';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/layout/layout.dart';

const _chrome = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

Future<void> main(List<String> args) async {
  var out = '.';
  var png = false;
  final files = <String>[];
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--out' && i + 1 < args.length) {
      out = args[++i];
    } else if (args[i] == '--png') {
      png = true;
    } else {
      files.add(args[i]);
    }
  }
  if (files.isEmpty) {
    stderr.writeln(
      'usage: dart run tool/render_layout.dart [--out <dir>] [--png] '
      '<graph.json>...',
    );
    exitCode = 2;
    return;
  }
  Directory(out).createSync(recursive: true);
  for (final file in files) {
    final json = jsonDecode(File(file).readAsStringSync());
    final graph = Graph.fromJson(json as Map<String, Object?>);
    final layout = layoutGraph(graph);
    final name = file.split('/').last.replaceAll(RegExp(r'\.json$'), '');
    final problems = checkLayout(layout);
    final caption =
        '$name · ${countCrossings(layout)} crossings · '
        '${problems.length} problems';
    final svg = File('$out/$name.svg')
      ..writeAsStringSync(renderSvg(layout, caption));
    stdout.writeln(caption);
    for (final problem in problems) {
      stdout.writeln('  $problem');
    }
    if (png) {
      final (width, height) = _size(layout);
      final result = await Process.run(_chrome, [
        '--headless=new',
        '--disable-gpu',
        '--hide-scrollbars',
        '--force-device-scale-factor=2',
        '--window-size=${width.ceil()},${height.ceil()}',
        '--screenshot=${File('$out/$name.png').absolute.path}',
        svg.absolute.uri.toString(),
      ]);
      if (result.exitCode != 0) {
        stderr.writeln('$name: chrome failed: ${result.stderr}');
        exitCode = 1;
      }
    }
  }
}

/// The size of the SVG of [layout]: the layout, its margin and the caption.
(double, double) _size(GraphLayout layout) => (
  layout.bounds.width + 2 * _pad,
  layout.bounds.height + 2 * _pad + _captionRoom,
);

/// The mockups' colours.
const _canvas = '#27282C';
const _dots = '#3A3B41';
const _tileFill = '#323338';
const _tileBorder = '#5A5B62';
const _icon = '#C9CACF';
const _name = '#ECECEE';
const _command = '#9A9BA2';
const _caption = '#7E7F86';
const _edge = '#8E8F96';
const _back = '#9C8CFF';
const _label = '#BDB3FF';
const _counter = '#7E7F86';
const _bar = '#8E8F96';
const _stub = '#55565C';

const _pad = 40.0;
const _captionRoom = 24.0;

/// [layout] as an SVG document, [caption] under it.
String renderSvg(GraphLayout layout, String caption) {
  final (width, height) = _size(layout);
  final svg = StringBuffer()
    ..writeln(
      '<svg xmlns="http://www.w3.org/2000/svg" width="${_n(width)}" '
      'height="${_n(height)}" viewBox="0 0 ${_n(width)} ${_n(height)}">',
    )
    ..writeln('<defs>')
    ..writeln(
      '<pattern id="dots" width="22" height="22" '
      'patternUnits="userSpaceOnUse"><circle cx="11" cy="11" r="1" '
      'fill="$_dots"/></pattern>',
    );
  for (final (id, colour) in [('ah', _edge), ('ahb', _back)]) {
    svg.writeln(
      '<marker id="$id" markerWidth="11" markerHeight="9" refX="0.5" '
      'refY="4.5" orient="auto" markerUnits="userSpaceOnUse">'
      '<path d="M0.5 0.6L10.5 4.5L0.5 8.4z" fill="$colour"/></marker>',
    );
  }
  svg
    ..writeln('</defs>')
    ..writeln(
      '<rect width="${_n(width)}" height="${_n(height)}" fill="$_canvas"/>',
    )
    ..writeln(
      '<rect width="${_n(width)}" height="${_n(height)}" fill="url(#dots)"/>',
    )
    ..writeln('<g transform="translate($_pad $_pad)">');

  // Arrows under everything else.
  for (final edge in layout.edges) {
    final back = edge.isDashed;
    final d = StringBuffer('M${_p(edge.points.first)}');
    for (final piece in edge.pieces) {
      switch (piece) {
        case LinePiece(:final to):
          d.write(' L${_p(to)}');
        case ArcPiece(:final to, :final radius, :final clockwise):
          d.write(
            ' A${_n(radius)} ${_n(radius)} 0 0 ${clockwise ? 1 : 0} ${_p(to)}',
          );
      }
    }
    svg.writeln(
      '<path d="$d" fill="none" stroke="${back ? _back : _edge}" '
      'stroke-width="1.6"${back ? ' stroke-dasharray="6 5"' : ''} '
      'marker-end="url(#${back ? 'ahb' : 'ah'})"/>',
    );
  }

  // Stubs of empty targets.
  for (final exit in layout.exits.where((e) => e.isEmpty)) {
    final y = exit.anchor.y;
    final end = exit.stubEnd!;
    svg
      ..writeln(
        '<path d="M${_p(exit.anchor)} L${_n(end)} ${_n(y)}" '
        'stroke="$_stub" stroke-width="1.6"/>',
      )
      ..writeln(
        '<path d="M${_n(end)} ${_n(y - 6)} L${_n(end)} ${_n(y + 6)}" '
        'stroke="$_stub" stroke-width="2.4" stroke-linecap="round"/>',
      );
  }

  // Keys and counters on opaque chips.
  final options = layout.options;
  for (final exit in layout.exits) {
    final label = exit.label;
    final chip = exit.labelRect;
    if (label != null && chip != null) {
      svg.writeln(_chip(chip, label, _label, options.chipPadding));
    }
    final counter = exit.counterAt;
    const text = '1×';
    final w =
        options.measure(text, LabelKind.counter) + 2 * options.chipPadding;
    svg.writeln(
      _chip(
        Rect.fromLTWH(counter.x, counter.y, w, options.chipHeight),
        text,
        _counter,
        options.chipPadding,
      ),
    );
  }

  // Nodes.
  for (final node in layout.nodes.values) {
    final t = node.tile;
    svg.writeln(
      '<rect x="${_n(t.left + 1)}" y="${_n(t.top + 1)}" '
      'width="${_n(t.width - 2)}" height="${_n(t.height - 2)}" rx="11" '
      'fill="$_tileFill" stroke="$_tileBorder" stroke-width="2"/>',
    );
    final c = t.center;
    svg.writeln(
      '<g transform="translate(${_n(c.x - 14)} ${_n(c.y - 14)})" '
      'fill="none" stroke="$_icon" stroke-width="1.6" '
      'stroke-linecap="round" stroke-linejoin="round">'
      '${node.isFork ? _forkIcon : _workerIcon}</g>',
    );
    if (node.startRect case final start?) {
      svg.writeln(
        '<text x="${_n(start.left)}" y="${_n(start.bottom - 2)}" '
        'font-family="Geist, Helvetica, sans-serif" font-size="9.5" '
        'font-weight="600" letter-spacing="0.76" fill="$_caption">START</text>',
      );
    }
    final n = node.nameRect;
    svg.writeln(
      '<text x="${_n(n.center.x)}" y="${_n(n.bottom - 3)}" '
      'text-anchor="middle" font-family="Geist, Helvetica, sans-serif" '
      'font-size="12.5" font-weight="600" fill="$_name">'
      '${_escape(node.name)}</text>',
    );
    final cmd = node.commandRect;
    svg.writeln(
      '<text x="${_n(cmd.center.x)}" y="${_n(cmd.bottom - 3)}" '
      'text-anchor="middle" font-family="Geist Mono, Menlo, monospace" '
      'font-size="10.5" fill="$_command">${_escape(node.command)}'
      '</text>',
    );
    if (node.bar case final bar?) {
      final r = bar.rect;
      svg.writeln(
        '<rect x="${_n(r.left)}" y="${_n(r.top)}" width="${_n(r.width)}" '
        'height="${_n(r.height)}" rx="2" fill="$_bar"/>',
      );
    }
  }

  // Exit handles over the tiles' sides.
  for (final exit in layout.exits) {
    final h = exit.handle;
    switch (exit.shape) {
      case ExitShape.dot:
        svg.writeln(
          '<circle cx="${_n(exit.anchor.x)}" cy="${_n(exit.anchor.y)}" '
          'r="5.5" fill="$_edge" stroke="$_canvas" stroke-width="2"/>',
        );
      case ExitShape.capsule:
        svg.writeln(
          '<rect x="${_n(h.left)}" y="${_n(h.top)}" width="${_n(h.width)}" '
          'height="${_n(h.height)}" rx="5.5" fill="$_edge" '
          'stroke="$_canvas" stroke-width="2"/>',
        );
      case ExitShape.stub:
        svg.writeln(
          '<circle cx="${_n(exit.anchor.x)}" cy="${_n(exit.anchor.y)}" '
          'r="5.5" fill="$_stub" stroke="$_canvas" stroke-width="2"/>',
        );
    }
  }

  svg
    ..writeln('</g>')
    ..writeln(
      '<text x="$_pad" y="${_n(height - 14)}" '
      'font-family="Geist, Helvetica, sans-serif" font-size="12" '
      'fill="$_caption">${_escape(caption)}</text>',
    )
    ..writeln('</svg>');
  return svg.toString();
}

String _chip(Rect rect, String text, String colour, double padding) =>
    '<rect x="${_n(rect.left)}" y="${_n(rect.top)}" '
    'width="${_n(rect.width)}" height="${_n(rect.height)}" rx="3" '
    'fill="$_canvas"/>'
    '<text x="${_n(rect.left + padding)}" y="${_n(rect.bottom - 2.5)}" '
    'font-family="Geist Mono, Menlo, monospace" font-size="10" '
    'fill="$colour">${_escape(text)}</text>';

const _workerIcon =
    '<rect x="3.5" y="5.5" width="21" height="17" rx="3.5"/>'
    '<path d="M9 11l3.2 3L9 17M14.5 17.5h4.5"/>';

const _forkIcon =
    '<circle cx="8" cy="14" r="2.6"/>'
    '<path d="M10.6 14h3c1.8 0 2.4-1 2.4-2.4V9.8c0-1.2.8-2 2-2h3.2'
    'M13.6 14c1.8 0 2.4 1 2.4 2.4v1.8c0 1.2.8 2 2 2h3.2"/>';

String _p(Point p) => '${_n(p.x)} ${_n(p.y)}';

String _n(double value) {
  final fixed = value.toStringAsFixed(2);
  return fixed.contains('.')
      ? fixed.replaceFirst(RegExp(r'\.?0+$'), '')
      : fixed;
}

String _escape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
