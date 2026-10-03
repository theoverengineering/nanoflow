# nanoflow code-first Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn nanoflow from "an engine process that drives a graph program" into "a library that runs ordinary Dart workflow functions in process, a tool that reads their graph from code, and a UI that draws both", as specified in `docs/superpowers/specs/2026-10-03-code-first-design.md`.

**Architecture:** `nanoflow_model` stays the contract (session storage v2, graph file model, source fingerprints). `nanoflow_store` writes one session journal per workflow call; `nanoflow_reader` follows all sessions of a project. `nanoflow` (rewritten) runs workflows in a zone that gives every step a deterministic key, so `resume` finds saved results after a crash. `nanoflow_describe` (new, analyzer-based) writes `nanoflow.graph.json`. The Flutter UI reads the graph file and the sessions, nothing else. The engine (`apps/nanoflow_cli`), the graph DSL and the `--call` protocol are deleted.

**Tech Stack:** Dart 3.13, Flutter 3.47 (macOS), `package:test`, `package:path`, `package:crypto`, `package:analyzer` (describe only), `package:watcher` or `Directory.watch` (describe `--watch`), `file_selector`, `shared_preferences`.

**The spec is the source of truth.** Every task names the spec sections (`§N`) it implements; read them in full first (Russian). The decisions log `docs/superpowers/specs/2026-10-02-code-first-decisions.md` explains why. When this plan and the spec disagree, the spec wins unless a Decision below says otherwise. Prototypes that prove the risky parts are in `prototypes/step_keys` (step keys) and `prototypes/static_graph` (extraction) — port them, keep their tests' scenarios.

## Global Constraints

- Dart SDK `^3.13.0` in every pubspec; every workspace member has `resolution: workspace`; one root `pubspec.yaml` and `pubspec.lock`. `apps/nanoflow_ui` stays outside the workspace with its own lock and `path:` dependencies on `nanoflow_model` and `nanoflow_reader` (old D17). `prototypes/*` stay outside the workspace and are not touched.
- One root `analysis_options.yaml`. `dart analyze` at the root (and `flutter analyze` in the UI when the UI is in scope) reports **no issues**; `dart format --output=none --set-exit-if-changed .` changes nothing.
- Layout after this plan: `packages/nanoflow_model`, `packages/nanoflow_store`, `packages/nanoflow_reader`, `packages/nanoflow`, `packages/nanoflow_describe`, `apps/nanoflow_ui`, `examples/review`, `tests/e2e`, `tool/`, `docs/`, `prototypes/`.
- Dependencies: packages never depend on apps; `nanoflow_store` and `nanoflow_reader` never import each other; the UI imports only `nanoflow_model` and `nanoflow_reader` from this repo; `apps/nanoflow_ui/lib/layout/` never imports `package:flutter` or `dart:ui`; `nanoflow` never depends on `analyzer`; `nanoflow_describe` never depends on `nanoflow_store`/`nanoflow_reader`.
- Each package: public entry `lib/<name>.dart`, the rest in `lib/src/`, a short Russian `README.md`, tests in `test/`.
- Ids: UUID v4, lowercase, 36 chars. Event time: UTC ISO-8601, exactly three fractional digits, `Z` (`2026-10-03T10:00:00.482Z`).
- Directory and file names (spec §5.1): `runs/`; session `<workflow>-YYYY-MM-DDTHH-MM-SS-<id>`; `session.json`, `log.jsonl`, `.owner.lock`, `documents/<id>.json`, `steps/YYYY-MM-DDTHH-MM-SS-mmm-<name>-<id>/` with `step.json` and `step.log`; name characters outside `[A-Za-z0-9._-]` become `_`.
- Model JSON forms, keys in this order, every key present (`null` when no value): Session `{id, workflow, graph, inputId}`; Step `{id, sessionId, name, key, after, place, outputId, log}`; Document `{id, sessionId, value}`; Event `{time, event, …own fields in the §5.3 table order}`.
- Events: `session-started{code}`, `session-resumed{code,graphId}`, `step-started{stepId}`, `step-finished{stepId,outputId}`, `step-failed{stepId,error,stack}`, `session-finished{outputId}`, `session-failed{error,stack}`.
- Reader changes (discriminator key `change`): `session-added{session}`, `step-added{step}`, `step-changed{step}`, `event-added{sessionId,event}`, `document-added{sessionId,documentId}`, `log-corrupted{sessionId,line,text}`.
- Graph file: `nanoflow.graph.json`, JSON exactly as spec §6.1, `"format": 1`, keys in the order shown there.
- Library API exactly as spec §4.1.
- UI: English text, dark theme, local time zone, ids shortened to 4 chars with the full id in a tooltip; existing visuals per `docs/design/*.html`; new frames per `docs/design/code-first/*.html` (these mockups are in Russian — the UI text is English).
- Commit messages: imperative subject that says **why** (the problem solved or capability enabled), not what; every commit ends with the `Co-Authored-By:` line of the model that did the work. Never commit `.superpowers/`.
- TDD: failing test first, see it fail for the expected reason, implement, see it pass. Test output pristine.
- **UI window.** From Task 3 until Task 12 the Flutter app does not build (it still uses the old model). Tasks 3–9 verify the workspace only: `tool/ci.sh` honours `NANOFLOW_SKIP_UI=1` (added in Task 1, removed in Task 14). Tasks 10–13 verify the UI with `flutter analyze` and `flutter test` in `apps/nanoflow_ui`.

## Decisions

Binding where the spec is silent.

- **D1 — Contexts and keys.** Exactly spec §4.3, ported from `prototypes/step_keys/lib/flow.dart` with two changes: contexts are hashed (`h(s)` = first 16 lowercase hex chars of sha256 of UTF-8 `s`; root context `""`), and every context carries `after` (the last adopted step key, inherited by child contexts). Step key: `<name>#<n>@<h(context)>`. A call context of `c` numbered `k`: `h(c + "/~" + k)` — numbers are given only in the zone's `register*Callback` handlers, from two counters per context: unary/binary registrations (async continuations, `then`, stream listeners) → `h(c + "/~" + k)`, no-argument registrations (`Timer`, `scheduleMicrotask`) → `h(c + "/~t" + k)`; `scheduleMicrotask`/`createTimer` handlers only carry the scheduler's context (Task 4 fix rounds 2–3). Adopting step `K` sets the context to `K` and `after` to `K`. Both live and journal paths schedule identical callbacks in the caller's context: the step body runs in context `h(K + "/~0")` (not `K`), and the future `f.step` returns belongs to the zone the session was started from, not the keyed zone (Task 4 review found both).
- **D2 — Step records on resume.** `SessionHandle.steps()` gives all step records; the library indexes them by `key`. A live step whose key already has a record reuses it (no new `step.json`) and appends a new `step-started`.
- **D3 — Step order on disk.** Create: step dir with `step.json` (atomic) → `step-started`. Finish: output document → `step-finished` → rewrite `step.json` with `outputId`. Fail: `step-failed`. `step-finished`/`step-failed` are authoritative; replay ignores `step.json`'s `outputId`.
- **D4 — Error texts.** `error` = `exception.toString()` with every run of `\r`/`\n` replaced by one space; `stack` = `stackTrace.toString()`.
- **D5 — Library exceptions** (all exported from `package:nanoflow/nanoflow.dart`): `SessionBusyException` (re-exported from the store), `SessionNotFoundException(sessionId)`, `WorkflowMismatchException(sessionId, expected, actual)` (resume with another workflow than `session.workflow`), `StorageException(cause)` (wraps `FileSystemException`/`StoreCorruptedException`), `FlowStoppedException`, `CodecException(type, reason)`.
- **D6 — Place.** The frame that called `f.step`: first frame of `StackTrace.current` whose URI is neither `dart:` nor `package:nanoflow/`; format `path:line`. Normalisation per spec §5.2: `package:<graph file package or pubspec name>/x` → `lib/x`; `file://` under the project directory → relative path with `/`; otherwise the URI path as printed. The column is dropped.
- **D7 — Code hash.** Spec §4.7. Fingerprint of sources = `fingerprintOf(await hashSources(dir, await packageSourcePaths(dir)))` from `nanoflow_model` (Task 2), the same functions `describe` uses.
- **D8 — Sessions and zones.** Each session runs in its own zone; `f.step` finds its session through a zone value. Several sessions of one `Flow` may run at once. `print` inside a step body goes to that step's `StepLog` through the session zone's `print` handler (the step body runs in a child context whose zone value names the step).
- **D9 — Codec registry.** `addCodec<T>` stores decoders under `T`, `T?`, `List<T>`, `List<T>?`, `Map<String, T>`, `Map<String, T>?` (types obtained with `Type typeOf<X>() => X;`). JSON-native types need no codec: a value is JSON-native when `jsonEncode` succeeds without calling any `toJson` (check by encoding with `toEncodable` that throws). Decode: JSON-native `T` → cast; otherwise the registered decoder; none → `CodecException`.
- **D10 — exec dies with the process.** The bash wrapper of `exec` (kept from today's `packages/nanoflow/lib/src/exec.dart`) also watches a pipe from the Dart process (an extra fd kept open by Dart); when it reads EOF it stops the group exactly as on TERM. Verified by killing the Dart process with SIGKILL in a test.
- **D11 — describe on fixtures.** `describePackage(String dir, {String? packageName})`: `packageName` defaults to the `name:` in `<dir>/pubspec.yaml`. Fixture packages under `packages/nanoflow_describe/test/fixtures/<name>/` have `lib/`/`bin/` but no `pubspec.yaml`, so the analyzer resolves `package:nanoflow` through the workspace's package config.
- **D12 — Step names in the graph.** `StepNode.name` is the literal; a non-literal name is the expression source, with a warning.
- **D13 — UI place matching.** A step maps to the `StepNode` whose `place` equals the step's `place`, or whose `place` the step's `place` ends with after a `/`.
- **D14 — Old graph model.** `packages/nanoflow_model/lib/src/graph.dart` (README format) stays until Task 12 removes its last user (the UI) and deletes it.

---

### Task 1: Retire the engine, the graph program and the DSL

**Spec:** §2 (what is deleted), §10.

**Files:**
- Delete: `apps/nanoflow_cli/` (whole), `tool/dev/` (whole), `examples/review/` (whole; Task 9 recreates it), `tests/e2e/test/review_example_test.dart`, `tests/e2e/test/resume_test.dart`, `tests/e2e/test/fixtures/`, `tests/e2e/test/support/engine.dart` and any support file only those tests use.
- Delete from `packages/nanoflow`: `lib/src/{build,call,serve,watch,graph,vertex,naming,dart_types}.dart`, their tests and fixtures (keep `lib/src/exec.dart`, `test/exec_test.dart` and whatever fixtures `exec_test` needs).
- Modify: `packages/nanoflow/lib/nanoflow.dart` (export only `exec`, `ExecException`), `packages/nanoflow/pubspec.yaml` (drop dependencies only the deleted code used), `packages/nanoflow/README.md` (one paragraph: the package is being rewritten; `exec` remains), root `pubspec.yaml` (`workspace:` members: model, store, reader, nanoflow, tests/e2e), `tool/ci.sh` (skip the Flutter block when `NANOFLOW_SKIP_UI=1`), `.gitignore` (keep `**/runs/`).
- Keep `tests/e2e/test/store_reader_contract_test.dart` as is (it still passes against the unchanged store and reader).

- [ ] **Step 1:** Delete the files above; update exports, pubspecs, workspace list, `ci.sh` (`if has_ui && [[ "${NANOFLOW_SKIP_UI:-}" != 1 ]]; then …`).
- [ ] **Step 2:** `dart pub get`, `dart analyze`, `dart format --output=none --set-exit-if-changed .`, `NANOFLOW_SKIP_UI=1 tool/ci.sh` — all green. Also run `tool/ci.sh` without the flag: the UI still builds and its tests pass (the model is unchanged so far) — required.
- [ ] **Step 3:** Commit (why: the engine process and the graph-program protocol are replaced by in-process workflows).

---

### Task 2: Graph file model and source fingerprints

**Spec:** §6.1, §6.2, §6.3.

**Files:**
- Create: `packages/nanoflow_model/lib/src/graph_file.dart`, `packages/nanoflow_model/lib/src/sources.dart`
- Modify: `packages/nanoflow_model/lib/nanoflow_model.dart` (export both), `packages/nanoflow_model/pubspec.yaml` (add `crypto`)
- Test: `packages/nanoflow_model/test/graph_file_test.dart`, `packages/nanoflow_model/test/sources_test.dart`

**Interfaces — Produces:**

```dart
const graphFileName = 'nanoflow.graph.json';
const graphFileFormat = 1;

final class GraphFile {
  const GraphFile({required this.format, required this.package, required this.fingerprint,
      required this.sources, required this.builds, required this.workflows,
      required this.functions, required this.warnings});
  /// Throws FormatException whose message starts with the JSON path of the
  /// bad field (`functions.lib/a.dart#f.body.nodes[2].kind: ...`).
  factory GraphFile.fromJson(Map<String, Object?> json);
  Map<String, Object?> toJson(); // keys in spec §6.1 order
  final int format;
  final String package;
  final String fingerprint;                 // 'sha256:<64 hex>'
  final Map<String, String> sources;        // path -> 'sha256:<hex>'
  final Map<String, String> builds;         // binary name -> 'sha256:<hex>'
  final List<String> workflows;             // function ids
  final Map<String, GraphFunction> functions;
  final List<GraphWarning> warnings;
  /// The workflow function whose id ends with '#name' or '.name'; null if none.
  GraphFunction? workflowNamed(String name);
}
final class GraphFunction { const GraphFunction({required this.id, required this.name, required this.place, required this.body}); final String id; final String name; final String? place; final GraphBody body; }
final class GraphBody { const GraphBody({required this.nodes, required this.edges}); final List<GraphNode> nodes; final List<GraphEdge> edges; GraphNode? node(String id); }
sealed class GraphNode { String get id; String? get place; }
final class StepNode extends GraphNode { name }            // kind "step"
final class ConditionNode extends GraphNode { label }      // kind "fork"
final class CallNode extends GraphNode { List<String> functions } // kind "call"
final class CopiesNode extends GraphNode { label, GraphBody body } // kind "copies"
final class GraphEdge { const GraphEdge({required this.from, required this.to, required this.label}); final String? from; final String? to; final String? label; }
final class GraphWarning { const GraphWarning({required this.place, required this.message}); final String? place; final String message; }
```

(Constructors and `==`/`hashCode`/`toString` like the existing entities: deep equality for collections.)

```dart
/// Paths, relative to [packageDir] with '/', of the .dart files under lib/ and
/// bin/, skipping any directory whose name starts with '.' or is 'build';
/// sorted. Missing lib/ or bin/ is fine.
Future<List<String>> packageSourcePaths(String packageDir);
/// 'sha256:' + hex sha256 of [bytes] after replacing every "\r\n" with "\n".
String sourceHash(List<int> bytes);
/// 'sha256:' + hex sha256 of [bytes] as they are (binaries).
String bytesHash(List<int> bytes);
/// The hash of every path that exists; missing files are left out.
Future<Map<String, String>> hashSources(String packageDir, Iterable<String> paths);
/// 'sha256:' + hex sha256 of the lines '<path> <hash>\n' sorted by path.
String fingerprintOf(Map<String, String> sourceHashes);
```

- [ ] **Step 1:** Failing tests: `GraphFile` round trip (`fromJson(toJson())` equals; `toJson` key order equals spec order for the file, a function, a body, each node kind, an edge); every node kind parses; `from`/`to`/`label` null allowed; unknown `kind` → `FormatException` naming the path; `format` other than 1 → `FormatException`; `workflowNamed('review')` finds `lib/review.dart#review` and `lib/x.dart#Flows.review`, not `lib/x.dart#reviewer`. Sources: temp dir with `lib/a.dart`, `lib/.hidden/b.dart`, `lib/build/c.dart`, `bin/main.dart`, `test/t.dart`, `lib/x.txt` → `['bin/main.dart', 'lib/a.dart']`; `sourceHash` of `"a\r\nb"` equals `sourceHash` of `"a\nb"`; `fingerprintOf` is independent of map order and changes when a hash or a path changes; known-answer test: `fingerprintOf({'lib/a.dart': 'sha256:00'})` equals sha256 of `"lib/a.dart sha256:00\n"`.
- [ ] **Step 2:** Run, see failures. **Step 3:** Implement. **Step 4:** Tests, analyze, format green. **Step 5:** Commit (why: describe, the library and the UI must read and hash the graph file the same way).

---

### Task 3: Session storage v2 (model, store, reader)

**Spec:** §5 (all), §8, §4.6 (order of writes), §4.7.

**Files:**
- Modify (model): `lib/src/entities.dart` (Session, Step, Document per §5.2; delete `Run`), `lib/src/events.dart` (the seven events of §5.3 + `UnknownEvent`; no `runId`), `lib/src/changes.dart` (§8 table), `lib/src/replay.dart` (§5.4: `SessionState replaySession(List<Event> events)`), `lib/src/storage_layout.dart` (names below), `lib/nanoflow_model.dart`; their tests.
- Modify (store): `packages/nanoflow_store/lib/src/fs_store.dart`, `session_handle.dart`, rename `engine_lock.dart` → `owner_lock.dart` (`ownerLockFileName = '.owner.lock'`, same mechanism, wording "another process owns the session"); tests.
- Modify (reader): `packages/nanoflow_reader/lib/src/{fs_reader,scanner}.dart` (session journal instead of run journals; no graph-name filter); tests.
- Modify: `tests/e2e/test/store_reader_contract_test.dart` (new models: a session with input, two steps — one finished with output, one failed — then `session-finished`; the reader gives the same models and events).

**Interfaces — Produces (model):**

```dart
final class Session { const Session({required this.id, required this.workflow, required this.graph, required this.inputId}); final String id; final String workflow; final Map<String, Object?>? graph; final String? inputId; }
final class Step { const Step({required this.id, required this.sessionId, required this.name, required this.key, required this.after, required this.place, required this.outputId, required this.log}); … final String log; /* "step.log" */ Step withOutput(String outputId); }
// Document unchanged.
sealed class Event { static Event fromJson(Map<String, Object?> json); String get name; Map<String, Object?> toJson(); }
sealed class KnownEvent extends Event { DateTime get time; }
final class SessionStarted extends KnownEvent { String? code; }      // 'session-started'
final class SessionResumed extends KnownEvent { String? code; String? graphId; }
final class StepStarted extends KnownEvent { String stepId; }
final class StepFinished extends KnownEvent { String stepId; String? outputId; }
final class StepFailed extends KnownEvent { String stepId; String error; String stack; }
final class SessionFinished extends KnownEvent { String? outputId; }
final class SessionFailed extends KnownEvent { String error; String stack; }
final class UnknownEvent extends Event { final Map<String, Object?> json; }

enum SessionStatus { running, finished, failed }
enum StepStatus { running, finished, failed }
final class StepState { stepId, status, starts, startedAt, finishedAt, outputId, error }
final class SessionState { status, steps (List<StepState> by first step-started), startedAt, finishedAt, outputId, error, codes (List<String?>), graphIds (List<String>) }
SessionState replaySession(List<Event> events);

// changes.dart: sealed Change with SessionAdded{session}, StepAdded{step}, StepChanged{step}, EventAdded{sessionId, event}, DocumentAdded{sessionId, documentId}, LogCorrupted{sessionId, line, text}; fromJson/toJson with key 'change'.

// storage_layout.dart
const runsDirName = 'runs', sessionFileName = 'session.json', documentsDirName = 'documents',
    eventsFileName = 'log.jsonl', stepsDirName = 'steps', stepFileName = 'step.json',
    logFileName = 'step.log', ownerLockFileName = '.owner.lock';
String sessionDirName(String workflow, DateTime createdAt, String id);
String stepDirName(DateTime startedAt, String name, String id);
String documentFileName(String id);
String? idOfDirName(String name);
bool isSessionDirName(String name); // '<anything non-empty>-YYYY-MM-DDTHH-MM-SS-<id>'
String runsDirOf(String projectDir); // '<projectDir>/runs'
```

**Interfaces — Produces (store):**

```dart
final class FsStore {
  FsStore(String runsDir, {Clock clock = systemClock});
  /// Builds the session atomically (session.json, documents/<input>.json when
  /// input is given, log.jsonl with session-started{code}), holding the owner
  /// lock from inside the build. Creates runsDir when missing.
  Future<SessionHandle> createSession({required String workflow, required Map<String, Object?>? graph, required ({Object? value})? input, required String? code});
  /// null when there is no such session. Takes the lock (SessionBusyException
  /// when another process owns it), truncates an incomplete last journal line.
  Future<SessionHandle?> openSession(String sessionId);
  /// Ids of sessions of [workflow] whose journal has no session-finished or
  /// session-failed, newest first. Unreadable sessions are skipped.
  Future<List<String>> unfinishedSessions(String workflow);
}
final class SessionHandle {
  final Session session; final String dir;
  Future<List<Event>> events();
  Future<List<Step>> steps();
  Future<Object?> documentValue(String documentId);
  Future<Step> createStep({required String name, required String key, required String? after, required String? place});
  Future<void> appendEvent(KnownEvent event);
  Future<String> writeDocument(Object? value);
  Future<Step> setStepOutput(Step step, String outputId);
  StepLog openLog(String stepId);   // appends to the step's step.log
  Future<void> release();
}
```

Keep today's robustness unchanged: atomic writes, monotonic times in names, journal truncation on open, `StepLog` backpressure, refusing to rebuild a removed session's directories, `StoreCorruptedException`, `SessionBusyException`.

**Interfaces — Produces (reader):**

```dart
final class FsReader {
  FsReader({required String runsDir, Duration pollInterval = const Duration(milliseconds: 500)});
  Stream<Change> changes();   // all sessions in runsDir; events of a session in journal order after its session-added
  Future<Object?> documentValue(String sessionId, String documentId);
  Stream<String> stepLog(String sessionId, String stepId);
  String? sessionPath(String sessionId); String? stepPath(String stepId);
  String? logPath(String stepId); String? documentPath(String sessionId, String documentId);
}
```

- [ ] **Step 1:** Model tests first (port the existing ones to the new forms): JSON key order of every model and event; every event round trip; event with wrong field types → `UnknownEvent` that writes back the same map; replay cases: empty → running with no steps; start/finish; a step started twice then finished → `starts: 2`; step-failed → step failed, session still running; session-failed → failed with error; `codes` from started + two resumes; `graphIds` only non-null. Layout tests: names per §5.1 incl. unsafe characters; `isSessionDirName` accepts `review-x-2026-10-03T10-00-00-<id>`, rejects `.tmp-<id>` and junk.
- [ ] **Step 2:** Implement the model; model tests green.
- [ ] **Step 3:** Store tests (port today's): create builds the whole session atomically (no `.tmp` left, lock held — second `openSession` in another isolate gets `SessionBusyException`); `createStep` writes `steps/<time>-<name>-<id>/step.json`; finish order of D3 via a fake clock; `openSession` truncates a partial line; `unfinishedSessions` filters by workflow and terminal events, newest first; removed session dir → writes fail with `FileSystemException` and nothing is rebuilt.
- [ ] **Step 4:** Implement the store; tests green.
- [ ] **Step 5:** Reader tests (port today's): changes for a session written by hand (session-added before its events; event order; document-added; step-changed when outputId appears; log-corrupted once); `stepLog` live tail; a session dir appearing later is picked up.
- [ ] **Step 6:** Implement the reader; update the e2e contract test; `NANOFLOW_SKIP_UI=1 tool/ci.sh` green.
- [ ] **Step 7:** Commit (why: a workflow call has one journal; runs that split and step inputs no longer exist).

---

### Task 4: Flow core — sessions, zones and step keys

**Spec:** §3, §4.1, §4.3, §4.6 (create, live step, end), §4.7, §5.2 `place`.

**Files:**
- Create: `packages/nanoflow/lib/src/flow.dart` (`Flow`, `FlowSession`), `lib/src/context.dart` (zone, contexts, keys — port of `prototypes/step_keys/lib/flow.dart`), `lib/src/project.dart` (project directory, workflow name, place, code hash, graph snapshot), `lib/src/errors.dart` (D5 exceptions)
- Modify: `lib/nanoflow.dart`, `pubspec.yaml` (deps: `nanoflow_model`, `nanoflow_store`, `crypto`, `path`)
- Test: `test/keys_test.dart` (port of `prototypes/step_keys/test/*` — all 14 scenarios, live keys same over 20 seeds), `test/flow_test.dart`, `test/project_test.dart`, `test/support.dart`

**Interfaces — Produces:**

```dart
final class Flow {
  Flow({String? directory});
  String get directory;                       // spec §3
  Future<FlowSession<R>> start<I, R>(Future<R> Function(Flow f, I input) workflow, I input);
  Future<R> run<I, R>(Future<R> Function(Flow f, I input) workflow, I input);
  Future<T> step<T>(String name, FutureOr<T> Function() body);
}
final class FlowSession<R> { String get id; Future<R> get result; }
String workflowNameOf(Function workflow);     // from toString(); ArgumentError otherwise
String? placeOf(StackTrace trace, {required String projectDir, required String? package});
```

In this task values are JSON-native only (codecs come in Task 6): a non-JSON-native input/result/step value throws `CodecException`.

- [ ] **Step 1:** Port the key machinery with D1 and its tests: the 14 scenarios of `prototypes/step_keys` must give the same set of keys over 20 seeds, and after a simulated crash (a journal with a random subset of finished steps) each copy gets its own data. The test harness may drive the context machinery directly (no files) — expose an internal `KeyedZone` for tests under `lib/src/`.
- [ ] **Step 2:** Failing `flow_test`: `run(review, 'x')` on a temp project dir writes one session whose journal is `session-started`, then per step `step-started`/`step-finished`, then `session-finished` with the result document; step records have `name`, `key` (`collect#1@<16 hex>`), `after` (null for the first, previous key for the next), `place` (`test/flow_test.dart:<line>` — the line of the `f.step` call), `outputId`; `step-failed` with `error`/`stack` when a body throws, and the exception reaches the workflow; uncaught → `session-failed` and `result` completes with that error; `f.step` outside a session → `StateError`; two sessions of one `Flow` running at once keep their steps apart.
- [ ] **Step 3:** Failing `project_test`: directory resolution (explicit; ancestor with `pubspec.yaml` of a given script path; none → script dir); `workflowNameOf` for a top-level function and a static method, `ArgumentError` for a closure; `placeOf` normalisation cases of D6 (package URI, file URI inside/outside the project, missing frame); code hash = fingerprint of the project's sources; snapshot = the decoded `nanoflow.graph.json` or null when missing or unreadable (unreadable → null, no exception).
- [ ] **Step 4:** Implement; all green; commit (why: workflows run in process and every step gets a key that survives a crash).

---

### Task 5: Resume, ownership, failures, stop

**Spec:** §4.1 (`resume`, `unfinished`, `stop`), §4.6 (resume, lock, storage failure, stop).

**Files:**
- Modify: `packages/nanoflow/lib/src/flow.dart`, `lib/src/errors.dart`
- Test: `packages/nanoflow/test/resume_test.dart`, `test/failures_test.dart`, fixture programs under `test/fixtures/` (each a `main` that runs a workflow, used by tests that kill a process)

**Interfaces — Produces:**

```dart
Future<FlowSession<R>> resume<I, R>(Future<R> Function(Flow f, I input) workflow, String sessionId);
Future<List<String>> unfinished(Function workflow);
void stop();
```

- [ ] **Step 1:** Failing `resume_test`: a fixture program runs a three-step workflow whose second step waits on a file; the test kills it with SIGKILL once step 2 started; `resume` in the test process: step 1's body is not run again (count via a side file), step 2 runs again and its record gets a second `step-started` (`starts == 2` in replay), step 3 runs, `session-resumed{code}` is written with `graphId: null` (same code), `result` is the workflow's value. Also: resume of a finished session returns the saved result without running anything or writing; resume of a failed session completes `result` with an error carrying the saved text; unknown id → `SessionNotFoundException`; other workflow → `WorkflowMismatchException`; resume while another process owns the session (a fixture holding it) → `SessionBusyException`; `unfinished(review)` lists the killed session only.
- [ ] **Step 2:** Failing: resume with a different code hash writes the project's current graph snapshot as a document and `session-resumed{graphId}` names it.
- [ ] **Step 3:** Failing `failures_test`: the session dir removed mid-run → the next `f.step` throws `StorageException`, `result` completes with `StorageException`, nothing is written afterwards (dir stays absent); `stop()` → next `f.step` throws `FlowStoppedException`, journal unchanged after the stop, the session is resumable.
- [ ] **Step 4:** Implement; green; commit (why: a crashed or stopped session is finished by `resume` without repeating finished steps).

---

### Task 6: Codecs, step logs and exec inside steps

**Spec:** §4.4, §4.5.

**Files:**
- Create: `packages/nanoflow/lib/src/codecs.dart`
- Modify: `lib/src/flow.dart` (encode/decode inputs, results, step values; `print` → step log), `lib/src/exec.dart` (stderr to the current step's log; D10; `flow.stop()` stops all groups), `lib/nanoflow.dart`
- Test: `test/codecs_test.dart`, `test/step_log_test.dart`, `test/exec_test.dart` (keep today's cases, adjust to the new log sink), fixture for D10

**Interfaces — Produces:**

```dart
void addCodec<T>(T Function(Map<String, Object?> json) fromJson); // on Flow
Future<String> exec(String executable, List<String> arguments, {String? workingDirectory, Map<String, String>? environment});
```

- [ ] **Step 1:** Failing codec tests: JSON-native values pass without a codec; a class with `toJson` + registered `fromJson` round-trips through the journal (resume returns an equal object); `List<T>`, `Map<String, T>`, `T?` work after one `addCodec<T>`; missing codec → the step fails with `CodecException` naming the type **on the first execution**; `toJson` missing → `CodecException`; `fromJson` returning another type → `CodecException`; workflow input and result use the same rules.
- [ ] **Step 2:** Failing step-log tests: `print` in a step body lands in that step's `step.log` (two parallel steps keep their lines apart); `print` outside steps is not written to any step log.
- [ ] **Step 3:** Failing exec tests: stderr of a program run inside a step is in the step's log; outside a step it goes to the process stderr; `flow.stop()` ends a running `sleep 100` group; D10: a fixture process that started `sleep 100` through `exec` is killed with SIGKILL and the `sleep` is gone within 5 s.
- [ ] **Step 4:** Implement; green; commit (why: steps return the user's own types and their output and programs belong to the step).

---

### Task 7: Extractor — the graph of a package from its code

**Spec:** §6.1, §7.1.

**Files:**
- Create: `packages/nanoflow_describe/` (`pubspec.yaml` with `analyzer`, `path`, `nanoflow_model`; dev: `test`, `nanoflow`), `lib/nanoflow_describe.dart`, `lib/src/extract.dart` (port of `prototypes/static_graph/lib/extract.dart`), `lib/src/describe.dart`, `README.md`
- Add to root `pubspec.yaml` workspace.
- Test: `test/extract_test.dart`, fixtures `test/fixtures/{review,release,inline,interfaces,recursion,warnings}/lib/*.dart` (no pubspec, D11)

**Interfaces — Produces:**

```dart
final class DescribeResult { final GraphFile? graph; final List<String> errors; }
/// Reads every source of the package (packageSourcePaths) with resolved types
/// and builds the graph file; compile errors -> graph null, errors listed.
Future<DescribeResult> describePackage(String packageDir, {String? packageName});
```

Rules beyond the prototype:
- Functions with steps become `functions` entries; a call to one becomes a `call` node (the prototype inlined callees — change that); recursion is just a `call` to itself.
- `Future.wait([for (…) …])` and `Future.wait(xs.map((x) async {…}))` → `copies` node (label `<variable> in <expression source>`, body = the element / closure body; a body that is a single call → body with one `call` node).
- Loop forks `for … in`: outcomes `each`/`done`; `if`/`while`/`for(;;)`/`?:`/`&&`/`||`: `true`/`false`; `switch`: case source / `default`.
- Interface or abstract method call → `call` with every implementation in the package's sources that has steps (sorted by id).
- `workflows`: the functions passed as first argument to `Flow.start`/`run`/`resume` (by element).
- Recognise `Flow.step`, `Flow.start`/`run`/`resume` by element whose library URI starts with `package:nanoflow/`; `Future.wait` by `dart:async`.
- Node ids: decimal strings in creation order within a body.
- `place` relative to the package root.
- `fingerprint`/`sources` from Task 2's functions; `builds: {}`; `format: 1`; `package` from the argument or pubspec.

- [ ] **Step 1:** Port the prototype's tests to the new format: review fixture → exactly the README review graph (nodes and labelled edges listed in the test); release fixture → loop fork with `each`/`done`, `call` node for `publish` and a `functions` entry for it, switch on enum without `default`; inline fixture → `copies` nodes for both forms and an ordinary loop for the sequential form; interfaces fixture → `call` with two implementations; recursion fixture → `call` to itself, no infinite loop; warnings fixture → each warning of §7.1 with its place.
- [ ] **Step 2:** Implement; tests green; workspace green; commit (why: the graph is read from ordinary code instead of a DSL).

---

### Task 8: describe command — write, watch, check, stamp

**Spec:** §6.3, §7.

**Files:**
- Create: `packages/nanoflow_describe/bin/nanoflow_describe.dart`, `lib/src/command.dart`
- Test: `test/command_test.dart`

**Interfaces — Produces:** `Future<int> runDescribe(List<String> args, {required String cwd, StringSink? out, StringSink? err})` (the bin calls it and sets `exitCode`).

- [ ] **Step 1:** Failing tests on a temp package (copy a fixture into a temp dir and add a `pubspec.yaml` + `dart pub get --offline`, or point `--package` at a fixture inside the workspace): plain run writes `nanoflow.graph.json` equal to `describePackage(...).graph.toJson()` (pretty, 2 spaces, trailing newline); a second run without changes does not rewrite (mtime unchanged); `--check` exits 0 when fresh and 1 after a source edit; compile error → exit 1, errors on `err`, file untouched; `stamp <binary>`: refuses (exit 1, file unchanged) when the fingerprint is stale, otherwise writes `builds[<basename>] = bytesHash(binary)` and copies the file next to the binary; `--watch` rewrites after an edit (poll the file up to 10 s in the test) and prints one line per rewrite.
- [ ] **Step 2:** Implement; green; commit (why: developers keep the graph file fresh and builds carry it).

---

### Task 9: Example and end-to-end checks

**Spec:** §10.

**Files:**
- Create: `examples/review/` (`pubspec.yaml` deps `nanoflow`, dev `nanoflow_describe`; `lib/review.dart` — the README review graph as in spec §1/decisions 2, with `Change`/`Report` classes with `fromJson`/`toJson`; `bin/main.dart` — reads the branch from args, `flow.start`, prints the session id on stdout, `--resume <id>` resumes, SIGINT → `flow.stop()` then exit 130; `nanoflow.graph.json` generated by describe; `README.md`)
- Modify: root `pubspec.yaml` (members), `tool/ci.sh` (`(cd examples/review && dart run nanoflow_describe --check)`), `tests/e2e/pubspec.yaml`
- Create: `tests/e2e/test/review_example_test.dart`, `tests/e2e/test/crash_resume_test.dart`, `tests/e2e/test/support/*.dart`

- [ ] **Step 1:** Failing e2e: running the example (compiled once per suite with `dart compile exe` into a temp dir, plus `dart run` once) ends with exit 0 and a finished session whose steps are `collect`, `inspect`, `fix`, `inspect`, `publish`, `notify` for a branch that needs one fix; session `graph` equals the example's graph file; session code = fingerprint under `dart run` and the binary's hash when compiled (stamp the binary first and check `builds`).
- [ ] **Step 2:** Failing crash test: the example started with a branch whose `inspect` waits on a marker file; SIGKILL after `inspect` started; `--resume <id>` finishes; `collect` ran once (side-effect counter file); `inspect` record has `starts == 2`.
- [ ] **Step 3:** Failing: a second `--resume` while the first owns the session exits non-zero with `SessionBusyException`'s message; `describe --check` on the example passes in CI.
- [ ] **Step 4:** Implement; `NANOFLOW_SKIP_UI=1 tool/ci.sh` green; commit (why: the whole path — run, crash, resume, graph file — is checked end to end).

---

### Task 10: UI data — graph file, freshness, sessions v2

**Spec:** §9 (open, freshness, session), decisions 8, 9.

**Files (apps/nanoflow_ui):**
- Delete: `lib/state/graph_source.dart`, its tests, `lib/graph/graph_errors.dart` (replaced), the PATH lookup in `lib/platform/shell.dart` (keep Finder/editor helpers), `lib/platform/terminal.dart` if unused.
- Create: `lib/state/graph_file_source.dart` (read + watch `nanoflow.graph.json`; emits `GraphFile` or a parse error), `lib/state/freshness.dart` (spec §9 freshness: sources vs disk, builds vs binaries next to the file; session code check), `lib/graph/graph_notes.dart` (banner for staleness + warnings list + "session ran on other code"/"not checked"/"session has no snapshot").
- Modify: `lib/start/start_screen.dart` and `recent_graphs.dart` (pick `*.graph.json`), `lib/state/session_feed.dart`, `sessions.dart`, `session_view.dart`, `graph_model.dart` (feed from `FsReader(runsDir: runsDirOf(dir))`; sessions filtered by the selected workflow name; session state from `replaySession`), tests.

- [ ] **Step 1:** Failing tests (pure Dart where possible): the graph of a session = the document named by its last non-null `session-resumed.graphId`, else `session.graph`, else the graph file's graph with the note "session has no snapshot"; `GraphFileSource` emits the parsed file, then a new one after the file changes, and an error for broken JSON without losing the last good graph; `freshness`: unchanged sources → fresh; one edited source → stale with that path; file next to a binary listed in `builds` → fresh when hashes match, stale otherwise; session code in `{fingerprint} ∪ builds.values` → matches; other → "other code"; null → "not checked".
- [ ] **Step 2:** Implement data; widget tests for the notes banner states. `flutter analyze` may still fail in views not yet migrated (Tasks 11–12) — in this task make the app build by keeping old views compiling against adapters only if cheap; otherwise mark the views with `// migrated in Task 11/12` and exclude nothing from analysis: the task is done when its own tests pass and `flutter analyze` reports issues only in files Tasks 11–12 replace (list them in the report).
- [ ] **Step 3:** Commit (why: the UI reads the graph from the graph file and checks it against the code).

---

### Task 11: UI graph view — one level, drill-down

**Spec:** §9 (graph), decisions 6, 10; mockups `docs/design/code-first/function-frames.html`, `copies-frame.html`.

**Files (apps/nanoflow_ui):**
- Modify: `lib/layout/layout_graph.dart` (`LayoutGraph.ofBody(GraphBody body)` replacing `LayoutGraph.of(Graph)`; entry = a start marker, `to: null` = end; edge labels from `GraphEdge.label`; several unlabelled/same-label edges from a node = a split), `lib/layout/*` where they read `WorkerNode`/`ForkNode`, `lib/graph/canvas/node_tile.dart` (kinds: step `>_`, condition `◇` with the label as name, call = stacked tile with `{ N }` where N counts steps in the function's body and `name()` below, copies = stacked tile `×N`/label), `lib/graph/canvas/graph_canvas.dart`, `lib/graph/header.dart` (workflow picker when the file has several; breadcrumb path `review › publish() › upload()`), `lib/graph/graph_screen.dart` (double-click call/copies → open its body; breadcrumb click → back).
- Test: layout tests on the review, release and inline graphs (no crossings, no broken rules — the existing `checks.dart`), widget tests for drill-down and breadcrumbs.

- [ ] **Step 1:** Failing layout tests for `LayoutGraph.ofBody` on the three example bodies (built in the test from JSON like the describe fixtures produce).
- [ ] **Step 2:** Port the layout entry point; tiles per kind; drill-down with breadcrumbs; workflow picker.
- [ ] **Step 3:** Render the three graphs with `tool/render_layout.dart` (update it to read a graph file and a function id) and look at the PNGs; fix what looks wrong.
- [ ] **Step 4:** `flutter analyze` (only Task 12 files may still report issues — list them), `flutter test` green for touched areas; commit (why: users see the graph read from code, one function at a time).

---

### Task 12: UI sessions on the graph — marks, copies, logs, step window

**Spec:** §9 (session, steps on the graph, copies, logs, step window), decisions 10, 11; mockup `docs/design/code-first/copy-switcher.html`.

**Files (apps/nanoflow_ui):**
- Delete: `lib/state/runs.dart`, `lib/graph/run_switcher.dart`, `lib/graph/details/input_column.dart`, `lib/state/schema_labels.dart`, split/inherited rows in `lib/state/log_rows.dart`, the README-format `packages/nanoflow_model/lib/src/graph.dart` and its tests and exports (D14).
- Create: `lib/state/step_places.dart` (D13 mapping; steps not on the graph), `lib/state/copies.dart` (spec §9 copies: per `CopiesNode`, copies = chains by `after`, numbered by first `step-started`, status, hint), `lib/graph/copy_switcher.dart` (chips `all · 1 ✓ · 2 ● · 3 ●`; list with search/filter when > 12 copies; nested copies path).
- Modify: `lib/state/graph_marks.dart` (counts/running/failed per node from step states; inside a copies frame: per selected copy or all), `visits.dart`, `visit_details.dart`, `step_details.dart` (output, log, place, error with stack; no input), `log_rows.dart`, `lib/graph/logs/*`, `lib/graph/details/*`, `lib/graph/sessions_column.dart`, `session_bar.dart`.
- Test: unit tests for `step_places`, `copies` (the `after` chains of the prototype's scenarios: in place, map, nested copies), `graph_marks`; widget tests for the copy switcher and the step window.

- [ ] **Step 1:** Failing unit tests for `step_places` and `copies`.
- [ ] **Step 2:** Implement state; then views; delete the old model graph (D14).
- [ ] **Step 3:** `tool/ci.sh` **without** `NANOFLOW_SKIP_UI` green (the app builds again); run the app on the example's project directory, take screenshots of a finished session, a running one and a selected copy; compare with the mockups; fix differences.
- [ ] **Step 4:** Commit (why: users follow a session and each parallel copy on the graph read from code).

---

### Task 13: UI — expand a function or copies frame in place

**Spec:** §9 (button on the tile — expand in place), decision 6; mockup `docs/design/code-first/function-frames.html`.

**Files (apps/nanoflow_ui):**
- Create: `lib/layout/nested.dart` (lay out an expanded `call`/`copies` node as a frame: the inner body's layout placed inside a padded rectangle with a title row; the frame is a node of the outer layout with the inner layout's size; nesting recursive)
- Modify: `lib/layout/layout.dart`, `lib/graph/canvas/*` (frame painter: 1 px solid outline in the tile border colour, no fill, title top-left `name()`, `−` top-right collapses; copies frame keeps its stack outlines, header and footer), `lib/graph/graph_screen.dart` (expanded set per path).
- Test: layout tests (expanded `publish()` inside release: no overlaps, no crossings with the frame border except edges entering/leaving it; two levels nested), widget test expand/collapse.

- [ ] **Step 1:** Failing layout tests. **Step 2:** Implement. **Step 3:** Render and look at the result against the mockup. **Step 4:** Commit (why: small functions can be read in context without leaving the parent graph).

---

### Task 14: Documents and final cleanup

**Spec:** §10.

**Files:**
- Rewrite: `README.md` (what nanoflow is now: workflow functions, steps, codecs, `exec`, sessions, resume, graph file, describe, UI; architecture table from spec §2; storage §5; graph file §6; drop the YAML format, command protocol, graph program, `Запуск` CLI and `nanoflow check` sections).
- Delete: `docs/dart-graph.md` (move its «Внешние программы» guidance into `packages/nanoflow/README.md`).
- Update: `docs/ui-spec.md` (graph file, notes, frames, copies, step window), `docs/graph-layout.md` (entry/end markers instead of `start`, frames), every package README, `apps/nanoflow_ui/README.md`.
- Modify: `tool/ci.sh` (remove `NANOFLOW_SKIP_UI`).

- [ ] **Step 1:** Write the documents (Russian, the style of today's README: short bold-led bullets).
- [ ] **Step 2:** `tool/ci.sh` green; commit (why: the documents describe the code-first nanoflow instead of the retired engine).
