import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../state/ansi.dart';
import '../../state/effect_details.dart';
import '../../state/effect_files.dart';
import '../../state/texts.dart' show thousands;
import '../../theme.dart';
import 'ansi_span.dart';
import 'document_view.dart' show TabNote;
import 'mono_lines.dart';

/// An effect's log in monospace, as it grows (docs/ui-spec.md «Logs»): its
/// last [previewLines] lines until `Show all`, in the colors its ANSI escape
/// sequences give it.
///
/// It opens at the end of the log and holds on to it as lines come, until
/// the user scrolls up; scrolled back down, it holds on again. Whether it
/// holds on is [following]. A running effect's log ends in a cursor.
class LogView extends StatefulWidget {
  const LogView({
    super.key,
    required this.files,
    required this.effect,
    required this.following,
  });

  final EffectFiles files;
  final EffectDetails effect;
  final ValueNotifier<bool> following;

  /// What a finished effect that wrote no log shows.
  static const nothing = 'The effect wrote nothing to its log';

  @override
  State<LogView> createState() => _LogViewState();
}

class _LogViewState extends State<LogView> {
  /// How long an effect's log may stay empty before the view says it is: the
  /// text on disk comes a moment after the view opens.
  static const _quietTime = Duration(milliseconds: 300);

  late final StreamSubscription<String> _log;
  final _scroll = ScrollController();

  /// The complete lines, the style each starts in, and how many characters
  /// each shows: its escape sequences show none.
  final List<String> _lines = [];
  final List<AnsiStyle> _starts = [];
  final List<int> _widths = [];

  /// What is written after the last complete line, and the style it starts
  /// in: that the lines before leave.
  String _partial = '';
  AnsiStyle _style = AnsiStyle.plain;

  /// The longest complete line, -1 while there is none, and its text
  /// without escape sequences.
  int _longest = -1;
  String _longestText = '';

  /// The first line shown: a long log shows its tail.
  int _start = 0;
  bool _all = false;
  Object? _error;
  bool _quiet = false;
  late final Timer _quietTimer;

  int get _count => _lines.length + (_partial.isEmpty ? 0 : 1);

  @override
  void initState() {
    super.initState();
    final effect = widget.effect;
    _log = widget.files
        .effectLog(effect.sessionId, effect.effectId)
        .listen(_add, onError: _failed);
    _scroll.addListener(_scrolled);
    _quietTimer = Timer(_quietTime, () => setState(() => _quiet = true));
  }

  @override
  void dispose() {
    _quietTimer.cancel();
    unawaited(_log.cancel());
    _scroll.dispose();
    super.dispose();
  }

  void _add(String text) {
    // The text written so far comes first: the view opens at its end.
    final first = _count == 0;
    _error = null;
    final parts = '$_partial$text'.split('\n');
    _partial = parts.removeLast();
    for (final line in parts) {
      final (:width, :end) = ansiWidth(line, _style);
      _lines.add(line);
      _starts.add(_style);
      _widths.add(width);
      if (_longest < 0 || width > _widths[_longest]) {
        _longest = _lines.length - 1;
        _longestText = withoutEscapes(line);
      }
      _style = end;
    }
    final follow = first || widget.following.value;
    setState(() {
      if (follow && !_all) _start = math.max(0, _count - previewLines);
    });
    if (follow) _toEnd();
  }

  /// A read that failed: reading goes on, and what was read stays.
  void _failed(Object error) => setState(() => _error = error);

  /// Holds on to the end once the lines are laid out.
  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && _scroll.hasClients) {
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    }
  });

  void _scrolled() {
    final position = _scroll.position;
    widget.following.value = position.pixels >= position.maxScrollExtent - 1;
  }

  void _showAll() {
    final above = _start;
    setState(() {
      _all = true;
      _start = 0;
    });
    // The lines in view stay in view.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(
        widget.following.value
            ? _scroll.position.maxScrollExtent
            : _scroll.offset + above * MonoLines.lineHeight,
      );
    });
  }

  InlineSpan _lineAt(int index) {
    final i = _start + index;
    final (line, style) = i < _lines.length
        ? (_lines[i], _starts[i])
        : (_partial, _style);
    return ansiSpan(shownRuns(ansiRuns(line, style).runs, whole: _all));
  }

  /// The longest complete line from [from], without its escape sequences.
  String _widestFrom(int from) {
    if (from == 0) return _longestText;
    var widest = -1;
    for (var i = from; i < _lines.length; i++) {
      if (widest < 0 || _widths[i] > _widths[widest]) widest = i;
    }
    return widest < 0 ? '' : withoutEscapes(_lines[widest]);
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null && _count == 0) {
      return TabNote(
        'Could not read the log: $error',
        color: AppColors.dangerText,
      );
    }
    final running = widget.effect.running;
    if (_count == 0 && !running) {
      return _quiet ? const TabNote(LogView.nothing) : const TabNote('');
    }
    final shown = _count - _start;
    final longest = _widestFrom(_start);
    final partial = withoutEscapes(_partial);
    final widest = partial.length > longest.length ? partial : longest;
    final cut = _all
        ? null
        : cutText(
            lines: _start == 0
                ? null
                : 'Showing the last ${thousands(shown)} of '
                      '${thousands(_count)} lines',
            widest: widest,
          );
    return MonoLines(
      count: shown,
      lineAt: _lineAt,
      widest: shownLine(widest, whole: _all),
      controller: _scroll,
      cursor: running,
      cut: cut == null ? null : (text: cut, showAll: _showAll),
    );
  }
}
