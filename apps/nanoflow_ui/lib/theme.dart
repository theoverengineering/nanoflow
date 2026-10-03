import 'package:flutter/material.dart';
import 'package:nanoflow_model/nanoflow_model.dart' show SessionStatus;

import 'state/sessions.dart' show SessionSummary;
import 'state/visits.dart' show StartOutcome;

/// Colors of the mockups in docs/design/ (their HTML has the exact values).
abstract final class AppColors {
  /// The window behind every screen.
  static const window = Color(0xFF1F2023);

  /// Lines between areas: under the graph screen's header.
  static const divider = Color(0xFF2B2C30);

  static const card = Color(0xFF26272B);
  static const cardBorder = Color(0xFF303136);

  /// A card under the pointer or selected.
  static const accentSurface = Color(0xFF2B2745);
  static const accentBorder = Color(0xFF4B4380);

  /// The square an icon sits in.
  static const tile = Color(0xFF323338);
  static const tileBorder = Color(0xFF45464C);

  /// Small secondary buttons (`Remove`); also the missing card's dashes.
  static const control = Color(0xFF2A2B30);
  static const controlBorder = Color(0xFF3A3B41);

  /// The primary button; the accent of the app's theme.
  static const accent = Color(0xFF6D5DE8);
  static const onAccent = Color(0xFFFFFFFF);

  /// The selected session's id.
  static const accentText = Color(0xFFBDB3FF);

  /// The sessions column, the `Logs` panel, the bars over the canvas.
  static const panel = Color(0xFF202125);

  /// Round the bars over the canvas; over the `Logs` panel.
  static const panelBorder = Color(0xFF34353A);

  /// The `·` between the parts of the session bar.
  static const separator = Color(0xFF55565C);

  static const textPrimary = Color(0xFFECECEE);
  static const textSecondary = Color(0xFFD5D6DA);
  static const textMuted = Color(0xFFA7A8AE);
  static const textFaint = Color(0xFF8E8F96);
  static const textDim = Color(0xFF6E6F76);

  /// Something running: its status bar, dot and text.
  static const running = Color(0xFFF2A93B);
  static const runningSurface = Color(0xFF33291B);
  static const runningBorder = Color(0xFF5E4825);

  /// Something failed: its status bar and dot; its text is [dangerText].
  static const failed = Color(0xFFF0555C);
  static const dangerSurface = Color(0xFF3A1D20);
  static const dangerBorder = Color(0xFF6A2F34);
  static const dangerText = Color(0xFFF7878C);

  /// Something finished, or live: its status bar and dot, its text.
  static const finished = Color(0xFF3CC47C);
  static const finishedSurface = Color(0xFF1D3328);
  static const finishedBorder = Color(0xFF2F5E44);
  static const finishedText = Color(0xFF8FDDB0);

  /// The running bar's darker stripes; the dim ring of the running sign.
  static const runningStripe = Color(0xFFC98526);
  static const runningRing = Color(0xFF4A3A1E);

  /// `2 starts`, `following tail`: amber notes.
  static const noteSurface = Color(0xFF3A2C16);
  static const noteText = Color(0xFFF2C27A);

  /// Something interrupted — its process stopped before it ended: its
  /// status bar, dot, sign, frame and text. Muted, as nothing goes on: not
  /// the amber of running.
  static const interrupted = textMuted;

  /// The selected step's row: its left bar, its name.
  static const accentLine = Color(0xFF9C8CFF);
  static const selectedText = Color(0xFFF7F3EA);

  /// The open tab of the step details.
  static const selectedTab = Color(0xFF34353A);

  /// A log or a document: the area it is shown in, its text.
  static const textArea = Color(0xFF1A1B1E);
  static const textAreaText = Color(0xFFC9CACF);

  // The step details window (docs/design/step-details.html).

  /// Round the window, and its `Output` column.
  static const backdrop = Color(0xFF1C1D20);
  static const backdropDot = Color(0xFF2C2D32);

  /// Under the window's top bar.
  static const topBarBorder = Color(0xFF2E2F34);

  /// A place in the code, the path of a step's directory, a duration after
  /// a time, a note, the punctuation of JSON.
  static const textSubtle = Color(0xFF9A9BA2);

  /// The keys of JSON.
  static const link = Color(0xFFB7ABFF);

  /// Numbers, and `true`, `false` and `null`, in data.
  static const jsonNumber = Color(0xFF8FDDB0);
  static const jsonLiteral = Color(0xFF8CC4F0);
}

/// The colors a session's status is shown in.
extension SessionStatusColors on SessionStatus {
  /// The status bar of its card, the dot on the session bar.
  Color get color => switch (this) {
    SessionStatus.running => AppColors.running,
    SessionStatus.failed => AppColors.failed,
    SessionStatus.finished => AppColors.finished,
  };

  /// `Running for 12m 26s`, `failed in 6m 18s`.
  Color get textColor => switch (this) {
    SessionStatus.running => AppColors.running,
    SessionStatus.failed => AppColors.dangerText,
    SessionStatus.finished => AppColors.finishedText,
  };
}

/// The colors of a session's card and bar: those of its status, but an
/// interrupted session's are [AppColors.interrupted].
extension SessionSummaryColors on SessionSummary {
  /// The status bar of its card, the dot on the session bar.
  Color get statusColor => interrupted ? AppColors.interrupted : status.color;

  /// `Running for 12m 26s`, `Interrupted after 3m 20s`.
  Color get statusTextColor =>
      interrupted ? AppColors.interrupted : status.textColor;
}

/// The colors a step's state — how its last start stands — is shown in: its
/// sign and its bar in `Logs`, the frame of its icon in the step details
/// window.
extension StartOutcomeColors on StartOutcome {
  Color get color => switch (this) {
    StartOutcome.running => AppColors.running,
    StartOutcome.interrupted => AppColors.interrupted,
    StartOutcome.failed => AppColors.failed,
    StartOutcome.finished => AppColors.finished,
  };
}

/// Text of the mockups: UI text in Geist; ids, places, paths and logs in
/// Geist Mono. Sizes, weights and colors are the mockups' CSS.
abstract final class AppText {
  static const sans = 'Geist';
  static const mono = 'Geist Mono';

  // CSS `normal` line height of the Google Fonts Geist the mockups were drawn
  // with: 1.3 em, the baseline 1.005 em from the top. The bundled fonts put
  // their lines closer; this spacing puts text where the mockups have it.
  static const _lineHeight = 1.3;
  static const _leading = TextLeadingDistribution.even;

  /// [family] at [size], spaced as the mockups' text is.
  static TextStyle _style(
    String family,
    double size, {
    FontWeight? fontWeight,
    double? letterSpacing,
    Color? color,
  }) => TextStyle(
    height: _lineHeight,
    leadingDistribution: _leading,
    fontFamily: family,
    fontSize: size,
    fontWeight: fontWeight,
    letterSpacing: letterSpacing,
    color: color,
  );

  /// The default for text that names no style.
  static const body = TextStyle(
    height: _lineHeight,
    leadingDistribution: _leading,
    inherit: false,
    fontFamily: sans,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    textBaseline: TextBaseline.alphabetic,
  );

  // Start screen.
  static final pageTitle = _style(
    sans,
    26,
    fontWeight: FontWeight.w700,
    letterSpacing: 26 * -0.015,
    color: AppColors.textPrimary,
  );
  static final pageHint = _style(sans, 13.5, color: AppColors.textMuted);
  static final primaryButton = _style(
    sans,
    13.5,
    fontWeight: FontWeight.w600,
    color: AppColors.onAccent,
  );
  static final sectionTitle = _style(
    sans,
    12.5,
    fontWeight: FontWeight.w600,
    color: AppColors.textSecondary,
  );
  static final count = _style(mono, 11.5, color: AppColors.textFaint);
  static final cardTitle = _style(
    sans,
    14,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );
  static final cardPath = _style(mono, 11.5, color: AppColors.textMuted);
  static final cardMeta = _style(sans, 12, color: AppColors.textMuted);
  static final badge = _style(sans, 10.5, fontWeight: FontWeight.w600);
  static final button = _style(sans, 12, color: AppColors.textSecondary);

  // Graph screen header.
  static final crumb = _style(sans, 13, color: AppColors.textMuted);
  static final crumbSeparator = _style(sans, 13, color: AppColors.textDim);
  static final headerTitle = _style(
    sans,
    13.5,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );
  static final headerPath = _style(mono, 11.5, color: AppColors.textFaint);

  /// The graph file's name in the header, among links that are not it.
  static final headerFile = _style(sans, 13, color: AppColors.textSecondary);
  static final liveBadge = _style(sans, 11.5);

  // Sessions column.
  static final panelTitle = _style(
    sans,
    13.5,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );
  static final sessionTitle = _style(
    sans,
    13,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );
  static final sessionId = _style(mono, 11);
  static final sessionStatus = _style(sans, 12);
  static final sessionSteps = _style(sans, 11.5, color: AppColors.textMuted);

  /// `1 failed`, `2 errors`.
  static final smallBadge = _style(sans, 10.5);
  static final hint = _style(sans, 12, color: AppColors.textMuted);

  // The session bar over the canvas.
  static final barLabel = _style(sans, 12, color: AppColors.textMuted);
  static final barId = _style(
    mono,
    12,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
  );

  /// The `·` between the bar's parts: the mockup's 16 px default.
  static final barSeparator = _style(sans, 16, color: AppColors.separator);

  // What is wrong with the current graph, over the canvas.
  static final problemTitle = _style(sans, 12, fontWeight: FontWeight.w600);
  static final problemText = _style(sans, 12, color: AppColors.textMuted);
  static final problemCode = _style(mono, 11, color: AppColors.textSecondary);

  // The Logs panel.
  static final logsTitle = _style(
    sans,
    13,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );
  static final logsSteps = _style(sans, 12, color: AppColors.textMuted);

  /// `Step`, `Started`, `Took`; the timeline's axis.
  static final columnTitle = _style(sans, 10.5, color: AppColors.textFaint);
  static final axisLabel = _style(mono, 9.5, color: AppColors.textFaint);
  static final stepName = _style(sans, 12, color: AppColors.textPrimary);

  /// A failure's error, `not on the graph`.
  static final stepDetail = _style(mono, 10.5, color: AppColors.textMuted);
  static final stepTime = _style(mono, 10.5, color: AppColors.textMuted);
  static final stepTook = _style(mono, 10.5, color: AppColors.textSecondary);
  static final startsNote = _style(sans, 10, color: AppColors.noteText);

  /// `↑ 8 earlier steps`, the end of a session.
  static final listNote = _style(sans, 10.5, color: AppColors.textMuted);

  // The selected step's details.
  static final detailsTitle = _style(
    sans,
    12.5,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );
  static final tab = _style(sans, 12, color: AppColors.textMuted);
  static final noteBadge = _style(sans, 11, color: AppColors.noteText);
  static final smallButton = _style(sans, 11.5, color: AppColors.textSecondary);

  /// A line of a log or a document: the mockups' 1.7 line height.
  static final textLine = _style(
    mono,
    11.5,
    color: AppColors.textAreaText,
  ).copyWith(height: 1.7);

  /// What a tab says instead of data.
  static final textAreaNote = _style(sans, 12, color: AppColors.textMuted);
  static final filePath = _style(mono, 10.5, color: AppColors.textFaint);
  static final fileButton = _style(sans, 11, color: AppColors.textSecondary);

  // The step details window.
  static final windowNode = _style(
    sans,
    15,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );
  static final windowPlace = _style(mono, 11, color: AppColors.textSubtle);
  static final visitText = _style(sans, 12, color: AppColors.textPrimary);
  static final windowCopy = _style(sans, 12, color: AppColors.textMuted);
  static final resultChip = _style(sans, 11.5);

  /// `PLACE IN CODE`, `THIS STEP`, `OUTPUT`: 0.09 em apart.
  static final sectionLabel = _style(
    sans,
    11,
    fontWeight: FontWeight.w700,
    letterSpacing: 11 * 0.09,
    color: AppColors.textMuted,
  );
  static final toggle = _style(sans, 11.5, color: AppColors.textMuted);
  static final fromText = _style(sans, 12, color: AppColors.textMuted);
  static final dataName = _style(mono, 12, color: AppColors.textPrimary);
  static final dataType = _style(mono, 10, color: AppColors.textMuted);
  static final dataValue = _style(mono, 12, color: AppColors.noteText);

  /// A line of JSON: 12 px at 1.8.
  static final jsonLine = _style(
    mono,
    12,
    color: AppColors.textAreaText,
  ).copyWith(height: 1.8);
  static final placeBox = _style(mono, 12, color: AppColors.textPrimary);
  static final placeNote = _style(sans, 11.5, color: AppColors.textSubtle);
  static final factLabel = _style(sans, 12, color: AppColors.textMuted);
  static final factValue = _style(mono, 12, color: AppColors.textPrimary);
  static final factNote = _style(sans, 11.5, color: AppColors.textSubtle);
  static final stepPath = _style(mono, 10.5, color: AppColors.textSubtle);
  static final outputTab = _style(sans, 12, color: AppColors.textMuted);
}

/// The MaterialApp around every screen, in the app's theme; tests show
/// screens in it too.
Widget appFrame({required Widget home}) => MaterialApp(
  title: 'nanoflow',
  theme: nanoflowTheme(),
  debugShowCheckedModeBanner: false,
  home: home,
);

/// The app's dark theme.
ThemeData nanoflowTheme() => ThemeData(
  brightness: Brightness.dark,
  colorScheme: const ColorScheme.dark(
    primary: AppColors.accent,
    onPrimary: AppColors.onAccent,
    surface: AppColors.window,
    onSurface: AppColors.textPrimary,
  ),
  scaffoldBackgroundColor: AppColors.window,
  // Complete styles: Material's own would lend their letter spacing to text
  // under a Material widget.
  textTheme: const TextTheme(
    displayLarge: AppText.body,
    displayMedium: AppText.body,
    displaySmall: AppText.body,
    headlineLarge: AppText.body,
    headlineMedium: AppText.body,
    headlineSmall: AppText.body,
    titleLarge: AppText.body,
    titleMedium: AppText.body,
    titleSmall: AppText.body,
    bodyLarge: AppText.body,
    bodyMedium: AppText.body,
    bodySmall: AppText.body,
    labelLarge: AppText.body,
    labelMedium: AppText.body,
    labelSmall: AppText.body,
  ),
);
