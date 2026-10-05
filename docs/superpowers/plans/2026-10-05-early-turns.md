# Early Turns Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An arrow leaving a node narrower than its layer turns as close to its node as the layout rules allow, instead of running to the layer's right edge first.

**Architecture:** In step 7 (`apps/nanoflow_ui/lib/layout/lanes.dart`), a turn's room starts at its own node's exit reach, and the layer's nodes with their right-side marks become marks for turns whose heights pass them; the existing lane allocation then places each turn as far left as allowed.

**Tech Stack:** Flutter 3.47 / Dart 3.13, pure layout library (no Flutter in `lib/layout/`), `flutter_test`.

**Design:** `docs/superpowers/specs/2026-10-05-early-turns-design.md` (Russian) — the source of truth.

## Global Constraints

- `apps/nanoflow_ui/lib/layout/` never imports Flutter.
- `checkLayout` stays empty on every test graph and on the random (nested) bodies; no graph's crossing count in `test/layout/reference.json` increases.
- Layers whose nodes have one width lay out exactly as before (byte-identical `describe()` for those fixtures).
- `flutter analyze`, `dart analyze --fatal-infos`, `dart format --output=none --set-exit-if-changed .` clean; `tool/ci.sh` exits 0; test output pristine.
- Commit messages: imperative subject that says **why**; end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never commit `.superpowers/`.
- TDD; look at regenerated goldens.

---

### Task 1: Turn next to the node in a wide layer

**Spec:** design §2–§4.

**Files:**
- Modify: `apps/nanoflow_ui/lib/layout/lanes.dart`, possibly `routing.dart` and `checks.dart`; `docs/graph-layout.md` (the wide-layer bullet in step 6, step 7); `apps/nanoflow_ui/README.md` if a row changes.
- Test: `apps/nanoflow_ui/test/layout/` (lanes/layout/nested tests; `reference.json` only if counts fall), goldens with frames.

- [ ] **Step 1: Failing tests.**
  - `task-carry.graph.json` (`task` with `carry()`, and `carry` with `work()` expanded so the layer is wide): the back arrows of `review()` and `decide()` turn within `clearance` + the lane spacing of their own tiles' exit reach, nested (`decide`'s inner), no crossings added.
  - Hand-built: a narrow node under a wide frame in one layer — its back arrow turns next to it; a narrow node whose turn passes the frame's heights — turns right of the frame (as before); a forward arrow from a narrow node to a target at the frame's height — turns right of the frame.
  - A `checkLayout` rule (if missing): no vertical of a turn passes through a node, its exit mark or label in the layer it sits in.
- [ ] **Step 2:** See them fail.
- [ ] **Step 3:** Implement design §2.
- [ ] **Step 4:** All layout tests, random bodies (and nested), `reference.json` (counts must not rise; lower them only with evidence), goldens with frames regenerated and looked at; graphs without frames unchanged.
- [ ] **Step 5:** Docs; `flutter test`, analyzers, format, `tool/ci.sh`; commit (why: arrows from a narrow node turn next to it instead of crossing the empty width of a wide layer).
