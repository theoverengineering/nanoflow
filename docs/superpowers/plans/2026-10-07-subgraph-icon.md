# Subgraph Icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A call's tile is one tile with a subgraph icon and the count of its effects under it, not a stack; copies keep their stack and show the same icon.

**Architecture:** A new line icon in `apps/nanoflow_ui/lib/widgets/icons.dart` (28 units, like the effect's terminal and the condition's diamond); `NodeTile` draws it with the existing `inside` text under it on call and copies tiles; `tilesBehind(NodeKind.call)` becomes 0, so nothing is stacked behind a call; `tool/render_layout.dart` mirrors it in SVG.

**Tech Stack:** Flutter 3.47 / Dart 3.13, `flutter_test`, goldens.

**Design:** `docs/superpowers/specs/2026-10-07-subgraph-icon-design.md` (Russian) — the source of truth, with the icon's exact geometry.

## Global Constraints

- `apps/nanoflow_ui/lib/layout/` never imports Flutter.
- `checkLayout` stays empty on every test graph and on the random (nested) bodies; no graph's crossing count in `test/layout/reference.json` increases.
- What `insideText` returns (`{ 3 }`, `{ 1–2 }`, `{ ? }`, `{ }`) does not change.
- `flutter analyze`, `dart analyze --fatal-infos`, `dart format --output=none --set-exit-if-changed .` clean; `tool/ci.sh` exits 0; test output pristine.
- Commit messages: imperative subject that says **why**; end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never commit `.superpowers/`.
- TDD; look at every regenerated golden.

---

### Task 1: Subgraph icon on call and copies tiles

**Spec:** design §2–§4.

**Files:**
- Modify: `apps/nanoflow_ui/lib/widgets/icons.dart` (the icon), `apps/nanoflow_ui/lib/graph/canvas/node_tile.dart` (call and copies tiles: icon with the count under it; no stack behind a call; doc comments), `apps/nanoflow_ui/lib/layout/coordinates.dart` (`tilesBehind(NodeKind.call) == 0`; comments), `apps/nanoflow_ui/lib/layout/layout_graph.dart` (the `insideText` comment: the text is under the icon), `apps/nanoflow_ui/tool/render_layout.dart` (same in SVG).
- Docs: `docs/ui-spec.md` («Узел — квадратная плитка»: вызов, копии), `apps/nanoflow_ui/README.md` (the `node_tile.dart` row), `docs/superpowers/specs/2026-10-03-code-first-design.md` (where a call is a «плитка-стопка»).
- Test: `apps/nanoflow_ui/test/graph/canvas/node_tile_test.dart`, layout tests touching `tilesBehind`/`overTile`, goldens with calls or copies.

- [ ] **Step 1: Failing tests.** A call tile shows the subgraph icon and its `{ N }`, with no tile stacked behind it and `+` in place; a copies tile shows two tiles behind it, `×3`, the subgraph icon and its `{ N }`; `tilesBehind(NodeKind.call) == 0`.
- [ ] **Step 2:** See them fail.
- [ ] **Step 3:** Implement design §2 (icon geometry verbatim from the design).
- [ ] **Step 4:** All tests; layout tests and `reference.json` (counts must not rise); regenerate the goldens with calls or copies and look at each — the call tile has the icon and the count under it, no stack; copies have the stack, `×3`, the icon. Render `tool/render_layout.dart --png` on `test/layout/graphs/release.graph.json` and look.
- [ ] **Step 5:** Docs; `flutter test`, analyzers, format, `tool/ci.sh`; commit (why: a stack read as «called many times» and meant something else on copies; a call gets its own icon as an effect and a condition have).

---

### Task 2: ƒ on calls and copies, the branch on forks

**Spec:** design, «Поправка» and §2 (both icons' geometry), §4.

The branch icon from Task 1 reads as a fork: it moves to the condition's tile in place of the diamond, and calls and copies get the function icon `ƒ`. In ASCII SVG (28 units, stroke 1.6, round caps and joins): `M5.5 22.5c1.6 0 2.4-1.1 2.8-3.1L11.6 8.6c.5-2.1 1.3-3.1 3-3.1M8 12.5h6M16.5 13.5l6 6M22.5 13.5l-6 6`.

**Files:**
- Modify: `apps/nanoflow_ui/lib/widgets/icons.dart` (the function icon; the condition's icon is the branch; name the icons by what they stand for), `apps/nanoflow_ui/lib/graph/canvas/node_tile.dart`, `apps/nanoflow_ui/tool/render_layout.dart`, and every other place the condition's diamond is drawn in the app.
- Docs: `docs/ui-spec.md`, `apps/nanoflow_ui/README.md`, `docs/superpowers/specs/2026-10-03-code-first-design.md` and code comments where a fork is a «ромб»/diamond or a call has the subgraph/branch icon.
- Test: `node_tile_test.dart` and the tests of other places that draw a condition's icon; goldens.

- [ ] **Step 1: Failing tests.** A call and copies show the function icon; a condition shows the branch, no diamond anywhere a condition's icon is drawn.
- [ ] **Step 2:** See them fail.
- [ ] **Step 3:** Implement (geometry verbatim).
- [ ] **Step 4:** All tests; regenerate the goldens and reference renders with calls, copies or forks and look at each.
- [ ] **Step 5:** Docs; `flutter test`, analyzers, format, `tool/ci.sh`; commit (why: the branch read as a fork, so forks get it and calls say «function»).
