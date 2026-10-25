// Renders graph layouts in the mockups' style, to look at them.
//
//   dart run tool/render_layout.dart [--out <dir>] [--png] <graph file>
//       [<function>[/<copies node>...]]...
//
// Each function of the graph file named — by its id, or by what follows `#`
// in it — and each copies body named after it by its node's id becomes
// <dir>/<package>-<function>[-<node>...].svg; with no function named, every
// function and every copies body in it. The default <dir> is the current
// directory; the layout's crossings and any broken rules are printed. With
// --png, headless Google Chrome ($CHROME, or its usual place on macOS) also
// renders the PNG at twice the size. (`qlmanage -t` renders SVG too, but
// into a square of about 800 px, cutting off wider graphs.)
import 'dart:convert';
import 'dart:io';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/layout/layout.dart';

/// Where headless Chrome is: `$CHROME`, or the usual place on macOS.
String get _chrome =>
    Platform.environment['CHROME'] ??
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

const _usage =
    'usage: dart run tool/render_layout.dart [--out <dir>] [--png] '
    '<graph file> [<function>[/<copies node>...]]...';

Future<void> main(List<String> args) async {
  var out = '.';
  var png = false;
  final rest = <String>[];
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--out' && i + 1 < args.length) {
      out = args[++i];
    } else if (args[i] == '--png') {
      png = true;
    } else {
      rest.add(args[i]);
    }
  }
  if (rest.isEmpty) {
    stderr.writeln(_usage);
    exitCode = 2;
    return;
  }
  if (png && !File(_chrome).existsSync()) {
    stderr.writeln(
      'cannot render PNG: no Google Chrome at $_chrome; '
      'set CHROME to its executable',
    );
    exitCode = 1;
    return;
  }
  final json = jsonDecode(File(rest.first).readAsStringSync());
  final file = GraphFile.fromJson(json as Map<String, Object?>);
  final bodies = <String, GraphBody>{};
  try {
    if (rest.length == 1) {
      for (final function in file.functions.values) {
        _addAll(bodies, _short(function.id), function.body);
      }
    } else {
      for (final path in rest.skip(1)) {
        final (name, body) = _bodyAt(file, path);
        bodies[name] = body;
      }
    }
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    exitCode = 2;
    return;
  }
  Directory(out).createSync(recursive: true);
  for (final MapEntry(key: name, value: body) in bodies.entries) {
    final layout = layoutBody(body, functions: file.functions);
    final stem = '${file.package}-$name';
    final problems = checkLayout(layout);
    final caption =
        '$stem · ${countCrossings(layout)} crossings · '
        '${problems.length} problems';
    final svg = File('$out/$stem.svg')
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
        '--screenshot=${File('$out/$stem.png').absolute.path}',
        svg.absolute.uri.toString(),
      ]);
      if (result.exitCode != 0) {
        stderr.writeln('$stem: chrome failed: ${result.stderr}');
        exitCode = 1;
      }
    }
  }
}

/// A function's id without its path: `release`, `MailNotifier.notify`.
String _short(String id) => id.substring(id.indexOf('#') + 1);

/// [body] by [name], and every copies body in it after it.
void _addAll(Map<String, GraphBody> bodies, String name, GraphBody body) {
  bodies[name] = body;
  for (final node in body.nodes) {
    if (node is CopiesNode) _addAll(bodies, '$name-${node.id}', node.body);
  }
}

/// The body [path] names in [file]: a function, by its id or what follows
/// `#` in it, then the copies nodes down to the body, by their ids.
(String, GraphBody) _bodyAt(GraphFile file, String path) {
  // A function's id has slashes of its own: the nodes start after `#`.
  final hash = path.indexOf('#');
  final slash = path.indexOf('/', hash < 0 ? 0 : hash);
  final name = slash < 0 ? path : path.substring(0, slash);
  final nodes = slash < 0
      ? const <String>[]
      : path.substring(slash + 1).split('/');
  final function =
      file.functions[name] ??
      file.functions.values.where((f) => _short(f.id) == name).firstOrNull;
  if (function == null) throw FormatException('no function $name');
  var body = function.body;
  var stem = _short(function.id);
  for (final id in nodes) {
    final node = body.node(id);
    if (node is! CopiesNode) {
      throw FormatException('$id in $stem is not a copies node');
    }
    body = node.body;
    stem = '$stem-$id';
  }
  return (stem, body);
}

/// The size of the SVG of [layout]: the layout, its margin and the caption.
(double, double) _size(GraphLayout layout) => (
  layout.bounds.width + 2 * _pad,
  layout.bounds.height + 2 * _pad + _captionRoom,
);

/// The canvas's colours, as lib/graph/canvas/canvas_style.dart has them.
const _canvas = '#1C1D20';
const _tileFill = '#3A3B42';
const _tileBorder = '#7A7B83';
const _stackFill = '#2E2F35';
const _stackBorder = '#6A6B73';
const _badgeFill = '#42434A';
const _badgeBorder = '#5E5F66';
const _badgeText = '#D5D6DA';
const _markerBorder = '#6E6F76';
const _markerText = '#A7A8AE';
const _icon = '#E4E5E9';
const _name = '#ECECEE';
const _place = '#6E6F76';
const _caption = '#7E7F86';
const _edge = '#A3A4AB';
const _back = '#9C8CFF';
const _label = '#D5D6DA';
const _bar = '#A3A4AB';

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
    ..writeln('<defs>');
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

  // Labels on opaque chips.
  final options = layout.options;
  for (final exit in layout.exits) {
    final label = exit.label;
    final chip = exit.labelRect;
    if (label != null && chip != null) {
      svg.writeln(_chip(chip, label, _label, options.chipPadding));
    }
  }

  // Nodes.
  for (final node in layout.nodes.values) {
    final t = node.tile;
    final c = t.center;
    switch (node.kind) {
      case NodeKind.start || NodeKind.end:
        svg
          ..writeln(
            '<rect x="${_n(t.left + 1)}" y="${_n(t.top + 1)}" '
            'width="${_n(t.width - 2)}" height="${_n(t.height - 2)}" '
            'rx="11" fill="$_canvas" stroke="$_markerBorder" '
            'stroke-width="1.5" stroke-dasharray="4 3"/>',
          )
          ..writeln(
            _inside(c, node.inside!, _markerText, size: 12, mono: false),
          );
      case NodeKind.effect || NodeKind.condition:
        svg
          ..writeln(_tile(t))
          ..writeln(
            _lineIcon(
              Point(c.x - 14, c.y - 14),
              node.kind == NodeKind.condition ? _conditionIcon : _effectIcon,
            ),
          );
      case NodeKind.call || NodeKind.copies:
        for (var k = tilesBehind(node.kind); k >= 1; k--) {
          svg.writeln(
            '<rect x="${_n(t.left + k * stackInset + 0.75)}" '
            'y="${_n(t.top - k * stackStep + 0.75)}" '
            'width="${_n(t.width - 2 * k * stackInset - 1.5)}" '
            'height="${_n(t.height - 1.5)}" rx="11" fill="$_stackFill" '
            'stroke="$_stackBorder" stroke-width="1.5"/>',
          );
        }
        // ƒ with the count of the effects in them under it, the two in the
        // middle of the tile as the app draws them.
        final iconTop = c.y - (28 + _countLine) / 2;
        svg
          ..writeln(_tile(t))
          ..writeln(_lineIcon(Point(c.x - 14, iconTop), _functionIcon))
          ..writeln(
            _inside(
              Point(c.x, iconTop + 28 + _countLine / 2),
              node.inside!,
              _icon,
              size: _countSize,
              mono: true,
              opacity: 0.7,
            ),
          );
        if (node.kind == NodeKind.copies) {
          // The badge across the top right of the stack.
          const width = 24.0;
          final top =
              t.top - stackStep * tilesBehind(node.kind) - badgeHeight / 2;
          final right = t.right + badgeOverhang;
          svg
            ..writeln(
              '<rect x="${_n(right - width)}" y="${_n(top)}" '
              'width="${_n(width)}" height="${_n(badgeHeight)}" '
              'rx="${_n(badgeHeight / 2)}" fill="$_badgeFill" '
              'stroke="$_badgeBorder"/>',
            )
            ..writeln(
              '<text x="${_n(right - width / 2)}" y="${_n(top + 10.5)}" '
              'text-anchor="middle" font-family="Geist Mono, Menlo, monospace" '
              'font-size="10" fill="$_badgeText">$copiesBadge</text>',
            );
        }
    }
    if (node.name case final name?) {
      final n = node.nameRect;
      svg.writeln(
        '<text x="${_n(n.center.x)}" y="${_n(n.bottom - 3)}" '
        'text-anchor="middle" font-family="Geist, Helvetica, sans-serif" '
        'font-size="12.5" font-weight="600" fill="$_name">'
        '${_escape(name)}</text>',
      );
    }
    if (node.place case final place?) {
      final p = node.placeRect;
      svg.writeln(
        '<text x="${_n(p.center.x)}" y="${_n(p.bottom - 3)}" '
        'text-anchor="middle" font-family="Geist Mono, Menlo, monospace" '
        'font-size="10.5" fill="$_place">${_escape(place)}</text>',
      );
    }
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

/// The tile [t] of an effect, a condition, a call or copies.
String _tile(Rect t) =>
    '<rect x="${_n(t.left + 1)}" y="${_n(t.top + 1)}" '
    'width="${_n(t.width - 2)}" height="${_n(t.height - 2)}" rx="11" '
    'fill="$_tileFill" stroke="$_tileBorder" stroke-width="2"/>';

/// A tile's 28-unit line icon drawn by [shapes], its top left at [at].
String _lineIcon(Point at, String shapes) =>
    '<g transform="translate(${_n(at.x)} ${_n(at.y)})" '
    'fill="none" stroke="$_icon" stroke-width="1.6" '
    'stroke-linecap="round" stroke-linejoin="round">$shapes</g>';

String _chip(Rect rect, String text, String colour, double padding) =>
    '<rect x="${_n(rect.left)}" y="${_n(rect.top)}" '
    'width="${_n(rect.width)}" height="${_n(rect.height)}" rx="3" '
    'fill="$_canvas"/>'
    '<text x="${_n(rect.left + padding)}" y="${_n(rect.bottom - 2.5)}" '
    'font-family="Geist Mono, Menlo, monospace" font-size="10" '
    'fill="$colour">${_escape(text)}</text>';

/// [text] on a line whose middle is [c], [size] px high, [opacity] opaque.
String _inside(
  Point c,
  String text,
  String colour, {
  required double size,
  required bool mono,
  double opacity = 1,
}) =>
    '<text x="${_n(c.x)}" y="${_n(c.y + size * 0.35)}" text-anchor="middle" '
    'font-family="${mono ? 'Geist Mono, Menlo, monospace' : 'Geist, Helvetica, sans-serif'}" '
    'font-size="${_n(size)}" fill="$colour"'
    '${opacity < 1 ? ' fill-opacity="${_n(opacity)}"' : ''}>'
    '${_escape(text)}</text>';

/// The effects of a call or of a copy under its `ƒ`: their size, and the
/// height of their line.
const _countSize = 11.0;
const _countLine = _countSize * 1.3;

/// An effect's terminal.
const _effectIcon =
    '<rect x="3.5" y="5.5" width="21" height="17" rx="3.5"/>'
    '<path d="M9 11l3.2 3L9 17M14.5 17.5h4.5"/>';

/// The branch: a node on the left branching to two on the right.
const _conditionIcon =
    '<rect x="3" y="11" width="6" height="6" rx="1.8"/>'
    '<rect x="19" y="4" width="6" height="6" rx="1.8"/>'
    '<rect x="19" y="18" width="6" height="6" rx="1.8"/>'
    '<path d="M9 14 h4 M13 14 V9 a2 2 0 0 1 2 -2 h4 '
    'M13 14 v5 a2 2 0 0 0 2 2 h4"/>';

/// `ƒ` with `×` by it, as in `f(x)`.
const _functionIcon =
    '<path d="M5.5 22.5c1.6 0 2.4-1.1 2.8-3.1L11.6 8.6c.5-2.1 1.3-3.1 3-3.1'
    'M8 12.5h6M16.5 13.5l6 6M22.5 13.5l-6 6"/>';

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
