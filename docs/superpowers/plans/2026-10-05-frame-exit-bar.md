# Frame Exit Bar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A frame drawn in place shows, on its right side, a bar for the end of its body: every arrow that ends the function arrives at it with its own height and arrowhead, and the frame's way out leaves from the bar's middle instead of a dot.

**Architecture:** The body's end port in a frame gets the input-bar geometry a tile has (inputs spread along a bar, gap and arrowhead before it) in the pure layout (`apps/nanoflow_ui/lib/layout/`); the canvas draws that bar and the arrowheads, and no exit dot for the frame node.

**Tech Stack:** Flutter 3.47 (macOS app), Dart 3.13, `flutter_test`.

**Design:** `docs/superpowers/specs/2026-10-05-frame-exit-bar-design.md` (Russian) — the source of truth.

## Global Constraints

- `apps/nanoflow_ui/lib/layout/` never imports Flutter; the UI imports only `nanoflow_model` and `nanoflow_reader` from this repo.
- `flutter analyze` and `dart analyze --fatal-infos`: no issues; `dart format --output=none --set-exit-if-changed .`: no changes; `tool/ci.sh` exits 0; test output pristine.
- The bar uses the tile input bar's constants (`LayoutOptions.barWidth`, `arrowGap`, `arrowLength`, the 10 px input spacing and the bar's margin past the outer inputs) — no new magic numbers.
- `checkLayout` stays empty on every test graph with frames and on the random nested bodies.
- `docs/design/` is not changed.
- Commit messages: imperative subject that says **why**; end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` (or the model that did the work). Never commit `.superpowers/`.
- TDD: failing test first, see it fail for the expected reason, implement, see it pass. Look at regenerated goldens.

---

### Task 1: The bar at a frame's exit

**Spec:** design §2–§4.

**Files:**
- Modify: `apps/nanoflow_ui/lib/layout/coordinates.dart` (`frameOf`: the end port's bar and input geometry), `apps/nanoflow_ui/lib/layout/nested.dart` and/or `routing.dart` / `lanes.dart` (room inside the frame for the gap and arrowhead before the bar; arrows to the end port at their own heights), `apps/nanoflow_ui/lib/layout/checks.dart` if a rule names the old "no further than their heads" shape, `apps/nanoflow_ui/lib/graph/canvas/edges_painter.dart` (draw the end port's bar outlined like a tile's bar; arrows into it end with heads and the gap), `apps/nanoflow_ui/lib/graph/canvas/exit_labels.dart` (no exit dot for a frame node), `docs/ui-spec.md` («Рамки»), `docs/graph-layout.md` (frames), `apps/nanoflow_ui/README.md` (rows of the touched files).
- Test: `apps/nanoflow_ui/test/layout/nested_test.dart`, `test/graph/canvas/` (painter test), goldens `canvas_frames`, `graph_frames`, `graph_copies_in_place` (regenerate and look).

**Interfaces:**
- Produces: in the layout, the end port of a body in a frame has a `bar` like a tile's (`NodeFrame.bar` non-null when arrows come to it) placed with its width's middle on the frame's right side line, its middle at the frame's exit height; edges into it end like edges into a tile's bar.

- [ ] **Step 1: Failing tests.**
  - Layout (`nested_test.dart`), on release's `publish()` expanded in place (the `!ok` `false` way and `rollback` both end the body), and on a hand-built body with three ways to its end:
    - the end port's bar exists; its x-middle is the frame's right side; its middle y is the frame's exit y;
    - the arrows to the end arrive at distinct heights, symmetric around the bar's middle, 10 px apart, each ending `arrowGap` before the bar's left edge with room for its head;
    - the bar spans them with the tile bar's margin; one arrow → the tile bar length for one input;
    - `checkLayout` is empty, and the random nested bodies test still passes.
  - Canvas: for a frame, `EdgesPainter` paints the end port's bar with the canvas-coloured outline (as `paints..rrect(…)` like the tile bar test in `graph_canvas_test.dart`), and `ExitsPainter` paints no dot for the frame node; a tile's exit dot is unchanged.
- [ ] **Step 2:** Run; see them fail for the expected reasons.
- [ ] **Step 3:** Implement design §2–§3.
- [ ] **Step 4:** Regenerate the goldens with frames; look at them (crop and enlarge the exit of `publish()` and of `upload()`, and the in-place copies frame's exit) — a bar, arrows with heads at their own heights, the outer arrow from the bar's middle, no dot. Update `docs/ui-spec.md`, `docs/graph-layout.md`, the UI README.
- [ ] **Step 5:** `flutter test`, analyzers, format, `tool/ci.sh`. Commit (why: the paths that end a function drawn in place show where each comes from instead of merging into a dot).
