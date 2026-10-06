# One Node per Function Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `describe` draws every function called in a body as one `call` node, with arrows from every place it is called and to what follows each call; the node's place is where the function is declared.

**Architecture:** In `packages/nanoflow_describe/lib/src/extract.dart`, after a body's control flow is projected onto nodes, call nodes with the same `functions` are merged into one (edges rewired and de-duplicated, ids deterministic), and a call node's `place` becomes the called function's declaration. The graph file format becomes 3. The UI reads the graph as it is.

**Tech Stack:** Dart 3.13, `package:analyzer` 14.4, Flutter 3.47.

**Design:** `docs/superpowers/specs/2026-10-06-one-node-per-function-design.md` (Russian) — the source of truth.

## Global Constraints

- `nanoflow_describe` never depends on `nanoflow_store`/`nanoflow_reader`; `nanoflow` never depends on `analyzer`; the UI imports only `nanoflow_model` and `nanoflow_reader`; `apps/nanoflow_ui/lib/layout/` has no Flutter.
- The graph file is byte-identical on every run (deterministic node ids and edge order).
- `dart analyze --fatal-infos`, `flutter analyze`, `dart format --output=none --set-exit-if-changed .` clean; `tool/ci.sh` exits 0 (it runs `describe --check` on the example).
- Commit messages: imperative subject that says **why**; end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never commit `.superpowers/`.
- TDD; look at regenerated goldens.
- The user's project `/Users/stanislavdalinin/Projects/scheduleme/nanoflow-task-graph` is read-only.

---

### Task 1: One call node per function in a body

**Spec:** design §2–§3; code-first spec §6.1, §7.1.

**Files:**
- Modify: `packages/nanoflow_describe/lib/src/extract.dart` (merge calls; declaration place), `packages/nanoflow_model/lib/src/graph_file.dart` (`graphFileFormat = 3`), docs (code-first spec §6.1 call node and `format`, §7.1; `packages/nanoflow_describe/README.md`; `docs/ui-spec.md` where it says a call tile's place is the call; `docs/graph-layout.md` if it assumes a call per place).
- Regenerate: `examples/review/nanoflow.graph.json`, describe's expected JSON in tests (`"format": 3`, merged calls where the fixture calls a function twice), the UI's test graphs (`apps/nanoflow_ui/test/layout/graphs/*.graph.json` — the describe-made ones per the UI README recipe, the hand-made and user-copied ones (`chain`, `chain-later`, `task-carry`) by re-describing the source when available, otherwise by merging their call nodes the same way with a small script and bumping `format`), the recorded fixtures (`tests/e2e/tool/record_*.dart`), and goldens.
- Test: `packages/nanoflow_describe/test/` (a new fixture `test/fixtures/calls_twice/`), `packages/nanoflow_model/test/graph_file_test.dart` (format 2 refused), UI tests that depend on call node ids/places.

- [ ] **Step 1: Failing describe tests** for design §3's cases (sequence, `if` branches, loop and outside it, `switch`, consecutive calls → loop edge, interface method from two places → one node with the interface member's declaration place, two same-named effects stay two nodes, determinism).
- [ ] **Step 2:** See them fail.
- [ ] **Step 3:** Implement the merge and the declaration place; bump the format.
- [ ] **Step 4:** Regenerate the files listed above; fix UI tests that named call nodes by old ids or places (keep their intent); look at every changed golden (call tiles' places now show declarations; graphs where a function was called twice now show one tile with arrows from both places).
- [ ] **Step 5:** Docs; `flutter test`, analyzers, format, `tool/ci.sh`; commit (why: a function called from several places is one node the arrows lead to, as the graph is meant to read, and its tile says where the function is).
