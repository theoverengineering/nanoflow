# Session Owner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The process that owns a session writes its pid and start time into `.owner.lock`; the reader learns from the OS when that process exits and tells the UI, which shows a session whose owner is gone as «Interrupted» — reactively, without polling.

**Architecture:** A new package `nanoflow_process` holds a port `Processes` (`startOf(pid)`, `exitOf(pid)`) with a macOS adapter (FFI: `sysctl` for the start time, kqueue `EVFILT_PROC/NOTE_EXIT` in a background isolate for the exit) and an "unsupported" adapter for other OSes. The library learns "who am I" once per process and hands it to the store as data; the store writes and clears `.owner.lock`; `FsReader` takes the port, watches owners of unfinished sessions and emits a new change `owner-changed`; the UI turns `alive: false` into «Interrupted».

**Tech Stack:** Dart 3.13 (`dart:ffi`, `package:ffi`, isolates), Flutter 3.47 (macOS app), `package:test`.

**Design:** `docs/superpowers/specs/2026-10-03-session-owner-design.md` (Russian) — the source of truth; read it first. Main spec: `docs/superpowers/specs/2026-10-03-code-first-design.md`.

## Global Constraints

- Dart SDK `^3.13.0`; every workspace member has `resolution: workspace`; the new package `packages/nanoflow_process` is added to the root `pubspec.yaml` `workspace:` list (CI picks members from there). Workspace path dependencies are written as `path: ../<package>` like the existing ones.
- `dart analyze --fatal-infos` at the root, `flutter analyze` in `apps/nanoflow_ui`: no issues. `dart format --output=none --set-exit-if-changed .`: no changes. `tool/ci.sh` (no flags) exits 0. Test output pristine.
- Dependencies: `nanoflow_store` never depends on `nanoflow_process` (the store only writes the owner it is given) and never imports `nanoflow_reader`; `nanoflow` and `nanoflow_reader` depend on `nanoflow_process`; the UI imports only `nanoflow_model` and `nanoflow_reader` from this repo (it may need `nanoflow_process` as a `path:` dependency in its pubspec for resolution, but never imports it); `apps/nanoflow_ui/lib/layout/` never imports Flutter; `nanoflow_process` depends only on `ffi` and Dart SDK libraries.
- Each package: public entry `lib/<name>.dart`, the rest in `lib/src/`, a short Russian `README.md`, tests in `test/`.
- `.owner.lock` JSON exactly `{"pid": <int>, "started": <time or null>}`, keys in that order, both present; empty file = no owner. Time format = event time format: UTC ISO-8601, exactly three fractional digits, `Z` (`2026-10-03T07:43:34.651Z`); the OS start time is truncated (not rounded) to milliseconds.
- The owner lock is an exclusive lock of the single byte at offset `ownerLockOffset = 1 << 30` of `.owner.lock` (not the whole file). Writing: JSON from position 0, then truncate to its length. Release: truncate to 0, then close.
- Change JSON: `{"change": "owner-changed", "sessionId": …, "owner": {pid, started} | null, "alive": true | false | null}`, keys in that order, all present.
- UI text English, dark theme, existing visuals per `docs/design/*.html`.
- Commit messages: imperative subject that says **why**; every commit ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` (or the model that did the work). Never commit `.superpowers/`.
- TDD: failing test first, see it fail for the expected reason, implement, see it pass.
- Only macOS is developed and tested. Other OSes get the "unsupported" adapter; nothing may crash there (the library still runs, writes `"started": null`; the reader says `alive: null`).
- Do not use `sleep` over 10 s in shell commands; tests that wait for a process exit use timeouts of a few seconds, never fixed sleeps longer than needed.

## Decisions

- **D1 — Port.** `abstract interface class Processes { factory Processes.forPlatform(); bool get supported; DateTime? startOf(int pid); Future<void> exitOf(int pid); Future<void> close(); }` exactly as design §3. `Processes.forPlatform()` returns `MacProcesses()` on macOS, else `UnsupportedProcesses()`. `startOf` is synchronous.
- **D2 — Fake.** `package:nanoflow_process/testing.dart` exports `FakeProcesses implements Processes`: `start(int pid, DateTime started)` makes a running process, `exit(int pid)` ends it (completes its `exitOf` futures and makes `startOf` return null), `supported` settable in the constructor (default true), `close()` makes pending `exitOf` never complete.
- **D3 — Owner model.** `nanoflow_model` gets `final class Owner { const Owner({required int pid, required DateTime? started}); toJson(); static Owner fromJson(Map<String, Object?>); == / hashCode / toString }` and `const ownerLockOffset = 1 << 30;` (in `storage_layout.dart`) and `final class OwnerChanged extends Change { const OwnerChanged({required String sessionId, required Owner? owner, required bool? alive}); name == 'owner-changed' }`, added to `Change.fromJson`.
- **D4 — Store API.** `FsStore(String runsDir, {Owner? owner, Clock clock})` (keep the existing clock parameter as it is); `lockSession(String dir, String sessionId, {Owner? owner})`; `unlockSession` unchanged in signature. `SessionHandle`/`openSession` pass the store's owner through.
- **D5 — Library owner.** `Flow` passes `FsStore(runsDirOf(directory), owner: currentOwner())` where `currentOwner()` (in `packages/nanoflow/lib/src/project.dart` or a new `owner.dart`) is memoized per process: `Owner(pid: pid /* dart:io */, started: Processes.forPlatform().startOf(pid))`; the adapter used for it is closed right after (or `startOf` needs no isolate — it does not on macOS). `Flow`'s public API is unchanged.
- **D6 — Reader API.** `FsReader({required String runsDir, Duration pollInterval = 500 ms, Processes? processes})`. Without `processes` the reader creates `Processes.forPlatform()` and closes it when the feed subscription is cancelled; a passed one is the caller's.
- **D7 — Exit handling order.** On an owner's exit the reader first scans that session (journal to its end) and only then, if the session has not ended, emits `owner-changed` with `alive: false`. A session that ended emits no more `owner-changed`.
- **D8 — UI state.** The UI keeps the latest `owner-changed` per session in `SessionData` (`owner`, `alive`; both null until the first one). A session is *interrupted* when its replayed status is `running` and `alive == false`. The model enum `SessionStatus` is not changed; the UI derives the interrupted state.

---

### Task 1: `nanoflow_process` — the OS port and the macOS adapter

**Spec:** design §1 (decisions 2, 3), §3, §7 (first bullet).

**Files:**
- Create: `packages/nanoflow_process/pubspec.yaml` (name `nanoflow_process`, `resolution: workspace`, dependency `ffi: ^2.1.0`, dev `test: ^1.25.0`), `lib/nanoflow_process.dart` (exports `Processes`, `MacProcesses`, `UnsupportedProcesses`), `lib/testing.dart` (exports `FakeProcesses`), `lib/src/processes.dart`, `lib/src/mac_processes.dart`, `lib/src/unsupported_processes.dart`, `lib/src/fake_processes.dart`, `README.md` (Russian, short: what the port is for, the macOS mechanism, how to add an OS).
- Modify: root `pubspec.yaml` (add `packages/nanoflow_process` to `workspace:`).
- Test: `packages/nanoflow_process/test/mac_processes_test.dart` (`@TestOn('mac-os')`), `test/unsupported_processes_test.dart`, `test/fake_processes_test.dart`.

**Interfaces:**
- Produces: D1, D2.

**macOS facts (verified on macOS 64-bit, arm64 and x86_64):**
- `DynamicLibrary.process()` has `sysctl`, `kqueue`, `kevent`, `close`.
- `int sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen)`; `name = {CTL_KERN=1, KERN_PROC=14, KERN_PROC_PID=1, pid}`; `oldp` a 648-byte buffer (`sizeof(struct kinfo_proc)`); after the call `*oldlenp == 0` means no such process. The start time is `kp_proc.p_un.__p_starttime`, a `struct timeval` at offset 0: `tv_sec` int64 at 0, `tv_usec` int32 at 8. Start time = `DateTime.fromMicrosecondsSinceEpoch(sec * 1e6 + usec, isUtc: true)` truncated to milliseconds.
- `struct kevent` (64-bit): `ident` uintptr @0, `filter` int16 @8, `flags` uint16 @10, `fflags` uint32 @12, `data` intptr @16, `udata` pointer @24; size 32. `EVFILT_PROC = -5`, `EVFILT_USER = -10`, `EV_ADD = 0x1`, `EV_ONESHOT = 0x10`, `EV_CLEAR = 0x20`, `EV_RECEIPT = 0x40`, `EV_ERROR = 0x4000`, `NOTE_EXIT = 0x80000000`, `NOTE_TRIGGER = 0x01000000`, `ESRCH = 3`.
- Registering with `EV_ADD | EV_ONESHOT | EV_RECEIPT` and an eventlist of 1 and a zero `timespec` returns a receipt with `EV_ERROR` set and `data` = errno (0 = registered, `ESRCH` = no such process → complete at once).
- One kqueue per adapter, created lazily on the first `exitOf`, with an `EVFILT_USER` event (ident 1, `EV_ADD | EV_CLEAR`) for waking. A background isolate (`Isolate.spawn`, given the kq fd and a `SendPort`) loops on a blocking `kevent(kq, null, 0, events, 16, null)`: `EVFILT_PROC` events → send the pid; `EVFILT_USER` → leave the loop. Registration happens in the calling isolate (kqueue is thread-safe). `close()`: trigger the user event (`fflags = NOTE_TRIGGER`), await the isolate's exit, `close(kq)`. Several `exitOf` of one pid share one registration.

- [ ] **Step 1: Failing tests.**
  - `mac_processes_test.dart`:
    - `startOf(pid)` of this process (dart:io `pid`) is not null, ≤ now, and equal on two calls;
    - `startOf` of a child `sleep 30` (`Process.start`) is within a few seconds of now and ≥ this process's start;
    - `startOf` of a pid that exited and was reaped (`Process.start('true', [])`, await `exitCode`) is null;
    - `exitOf(child.pid)` completes within 5 s after `child.kill(ProcessSignal.sigkill)` and does not complete before the kill (check that it is still pending after 200 ms);
    - `exitOf` of a child that exits by itself (`sleep 0.2`) completes;
    - `exitOf` of a reaped pid completes at once;
    - two `exitOf` of one pid and one of another pid all complete when their processes die;
    - after `close()`, the adapter's isolate is gone: `close()` completes, and a pending `exitOf` never completes (use `expectLater(... .timeout(...), throwsA(isA<TimeoutException>()))` with a short timeout).
    Tear every child down in `addTearDown`.
  - `unsupported_processes_test.dart`: `supported` false, `startOf` null, `exitOf` does not complete (short timeout).
  - `fake_processes_test.dart`: D2 behaviour.
- [ ] **Step 2:** Run `dart test` in the package; see the failures (missing library).
- [ ] **Step 3:** Implement. Keep FFI structs as `Pointer<Uint8>` buffers with typed views or `Struct` classes — your choice; free every allocation (`package:ffi` `calloc`). Translate `Processes.forPlatform()` per D1.
- [ ] **Step 4:** Tests pass; `dart analyze` root clean; `dart format` clean; `tool/ci.sh` exits 0.
- [ ] **Step 5:** Commit (why: the reader and the library need to know from the OS when a process started and when it is gone).

---

### Task 2: Model — `Owner`, `owner-changed`, the lock offset

**Spec:** design §2, §4 (first bullet), §5 (the change).

**Files:**
- Create: `packages/nanoflow_model/lib/src/owner.dart`.
- Modify: `packages/nanoflow_model/lib/nanoflow_model.dart` (export), `lib/src/changes.dart` (`OwnerChanged`, `Change.fromJson` case), `lib/src/storage_layout.dart` (`ownerLockOffset`), README.
- Test: `packages/nanoflow_model/test/owner_test.dart`, `test/changes_test.dart` (extend), `test/storage_layout_test.dart` (extend).

**Interfaces:** Produces D3. Use the existing JSON helpers (`json_fields.dart`: `readInt`, `readString`, `readObject`, `inside`) and the existing time formatting used by events (find it in `events.dart`; reuse it, do not duplicate). `started: null` must round-trip. `fromJson` errors name the field (`started: …`).

- [ ] **Step 1:** Failing tests: `Owner` toJson key order and values, `null` started, round trip, errors for missing/wrong `pid`/`started`, a time with more than three fractional digits is not accepted as written by us — follow what the event time parser does; `OwnerChanged` round trip through `Change.fromJson` with owner and with `owner: null`/`alive: null`, key order; `ownerLockOffset == 1 << 30`.
- [ ] **Step 2:** See them fail. **Step 3:** Implement. **Step 4:** Package tests, analyze, format, `tool/ci.sh`. **Step 5:** Commit (why: the owner record and its change need one language-neutral form for writer, reader and UI).

---

### Task 3: Store — write and clear the owner in `.owner.lock`

**Spec:** design §2, §4 (second bullet), §7 (store bullet); main spec §4.6 «Блокировка».

**Files:**
- Modify: `packages/nanoflow_store/lib/src/owner_lock.dart`, `lib/src/fs_store.dart`, `lib/src/session_handle.dart` (pass the owner through on open), README.
- Test: `packages/nanoflow_store/test/owner_lock_test.dart` (create or extend the existing lock test file — find where lock tests live), plus the existing child-process busy test must keep passing.

**Interfaces:**
- Consumes: `Owner`, `ownerLockOffset` (Task 2).
- Produces: D4.

- [ ] **Step 1:** Failing tests:
  - a session created by `FsStore(runs, owner: Owner(pid: 42, started: t))` has `.owner.lock` == the owner's JSON while the handle is open (read the file with `File.readAsString` while locked);
  - after the handle closes the file is empty;
  - `FsStore(runs)` without owner → empty file while held;
  - `openSession` writes the store's owner;
  - a previous longer record (write `{"pid": 123456789, "started": "…"}` by hand first) is replaced exactly by a shorter one (no tail left);
  - the lock is the byte at `ownerLockOffset`: a child process (reuse the existing child-process lock test helper) that locks byte `ownerLockOffset` exclusively makes `openSession` throw `SessionBusyException`, and one that locks byte 0 does not;
  - a child holding the session still makes a second owner get `SessionBusyException` (existing test).
- [ ] **Step 2:** See them fail. **Step 3:** Implement: lock `FileLock.exclusive` on `[ownerLockOffset, ownerLockOffset + 1)`; write JSON at position 0 then `truncate(length)`; `unlockSession` truncates to 0 then closes (keep the `_held` guard and the failure paths as they are). **Step 4:** Tests, analyze, format, `tool/ci.sh`. **Step 5:** Commit (why: a reader can tell which process owns a session and whether it let it go).

---

### Task 4: Library — the process records itself as the owner

**Spec:** design §1 (decision 4), §4 (third bullet), §7 (`nanoflow` bullet).

**Files:**
- Create: `packages/nanoflow/lib/src/owner.dart` (`Owner currentOwner()` memoized per process, plus a `forgetOwner()` seam only if a test needs it).
- Modify: `packages/nanoflow/pubspec.yaml` (`nanoflow_process: path: ../nanoflow_process`), `lib/src/flow.dart` (`FsStore(runsDirOf(directory), owner: currentOwner())`), README.
- Test: `packages/nanoflow/test/owner_test.dart`.

**Interfaces:** Consumes D1, D3, D4. Produces nothing new publicly (`Flow` API unchanged).

- [ ] **Step 1:** Failing tests (macOS): while a step of a started session is waiting (a `Completer` the test controls), `.owner.lock` of the session holds `{"pid": <dart:io pid>, "started": <MacProcesses().startOf(pid) formatted>}`; after the session finishes it is empty; after a failed session it is empty; after `stop()` it is empty; `resume` of an unfinished session writes the owner again while it runs. Use a temp project directory as the existing flow tests do (`Flow(directory: …)`).
- [ ] **Step 2:** See them fail. **Step 3:** Implement. **Step 4:** Tests, analyze, format, `tool/ci.sh`. **Step 5:** Commit (why: the owner's pid and start time make a key the UI can check against the OS).

---

### Task 5: Reader — watch owners and emit `owner-changed`

**Spec:** design §5, §7 (reader bullets); main spec §8.

**Files:**
- Create: `packages/nanoflow_reader/lib/src/owners.dart` (the watching logic: per unfinished session the current owner, its liveness, the exit subscription; reads `.owner.lock`; talks to `Processes`).
- Modify: `packages/nanoflow_reader/pubspec.yaml` (`nanoflow_process` path dependency), `lib/src/fs_reader.dart` (D6; merge exit-driven changes into the feed; close an owned adapter on cancel), `lib/src/scanner.dart` (after a session's journal is read in a scan, update its owner; expose a way to scan one session on demand for D7), README.
- Test: `packages/nanoflow_reader/test/owners_test.dart` (fake `Processes`), `test/owner_process_test.dart` (`@TestOn('mac-os')`, real child process).

**Interfaces:** Consumes D1–D3. Produces D6, D7, the `owner-changed` feed entries.

**Behaviour (design §5):**
- In each scan, for every session not ended after its journal was read: read `.owner.lock` (missing/empty → owner `null`; not valid JSON or not an `Owner` → keep the previous state, no error on the stream); if the owner record changed: for a non-null owner with non-null `started` and `processes.supported`: subscribe `exitOf(pid)` first, then `alive = processes.startOf(pid) == started`; with `started == null` or unsupported → `alive = null`; null owner → `alive = false`. Emit `owner-changed` when (`owner`, `alive`) differs from the last emitted for that session (the first time always, after the session's other changes of that scan).
- An exit of the watched owner: scan that session (D7), then, if it has not ended and the owner on record is still that same owner, set `alive = false` and emit.
- A session that has ended: drop its watch; no more `owner-changed`.
- Cancelling the feed cancels everything; an exit arriving after cancel emits nothing.

- [ ] **Step 1:** Failing tests with `FakeProcesses`. The reader never depends on the store, not even as a dev dependency: build session directories by hand with the existing reader test helpers (see `test/` for how sessions are built today) and write `.owner.lock` contents directly:
  - first read: unfinished session with empty `.owner.lock` → `owner-changed(owner: null, alive: false)` after its events;
  - live owner (`fake.start(pid, t)`, file has `{pid, t}`) → `alive: true`;
  - file's `started` differs from `fake.startOf(pid)` → `alive: false`;
  - `started: null` → `alive: null`; `FakeProcesses(supported: false)` → `alive: null`;
  - `fake.exit(pid)` → `owner-changed(alive: false)` with the same owner;
  - file cleared → `owner-changed(owner: null, alive: false)`;
  - a new owner written (resume) after an exit → `alive: true` with the new owner;
  - the journal gets `session-finished` and then the process exits (append the event, then `fake.exit`) → the feed has `session-finished` and no `alive: false` for that session;
  - a half-written file (`{"pid": 4`) → no error on the stream, no `owner-changed` until it is complete;
  - a finished session → no `owner-changed` at all;
  - a reader created without `processes` closes its own adapter on cancel (inject a factory or check via a test seam — your choice; keep the public API D6).
  - `owner_process_test.dart`: the test builds an unfinished session directory by hand, then starts a child Dart script (under `test/`) that plays the owner without the store: it locks byte `ownerLockOffset` of the session's `.owner.lock` with `RandomAccessFile.lock`, writes `{"pid": <its pid>, "started": <MacProcesses().startOf(its pid)>}` (formatted as Task 2's `Owner.toJson`), prints a line and waits. Reader with `MacProcesses` → `alive: true`; `child.kill(ProcessSignal.sigkill)` → `alive: false` within 5 s.
- [ ] **Step 2:** See them fail. **Step 3:** Implement. **Step 4:** Tests, analyze, format, `tool/ci.sh`. **Step 5:** Commit (why: the UI learns the moment a session's process dies, without polling).

---

### Task 6: UI — «Interrupted»

**Spec:** design §6, §7 (UI bullet); main spec §9; `docs/ui-spec.md` «Сессии».

**Files:**
- Modify: `apps/nanoflow_ui/pubspec.yaml` (path dependency `nanoflow_process` only if resolution needs it), `lib/state/session_feed.dart` (apply `OwnerChanged`: `SessionData.owner`, `SessionData.alive`; notify), `lib/state/sessions.dart` (interrupted summary: status text `Interrupted`, duration to the last event, tooltip text `The process that ran this session is gone; resume it to finish.`), `lib/graph/sessions_column.dart`, `lib/graph/session_bar.dart`, the places that draw a running step (graph marks, Logs rows, step window — find them through `StepStatus.running` / `SessionStatus.running` uses) so a running step of an interrupted session reads as interrupted (reuse the existing interrupted visuals of `StartOutcome.interrupted` / `node_column.dart`), `lib/theme.dart` (a colour for interrupted if none fits — prefer an existing muted/amber token), README rows.
- Test: unit tests in `test/state/` (feed applies `owner-changed`; summary interrupted; duration stops; `alive: null` and missing → running as before), widget tests (card and bar show `Interrupted` with the tooltip; a running step in an interrupted session shows the interrupted mark on the graph and in Logs; a later `owner-changed` flips a running session to interrupted without other input), golden for the session card if card goldens exist (regenerate only the intended ones and look at them).

**Interfaces:** Consumes `OwnerChanged` (Task 2) through the reader feed. D8.

- [ ] **Step 1:** Failing tests. **Step 2:** See them fail. **Step 3:** Implement. **Step 4:** `flutter analyze`, `flutter test`, root analyze/format, `tool/ci.sh`. **Step 5:** Commit (why: a session whose process died no longer pretends to run).

---

### Task 7: End to end and documents

**Spec:** design §7 (e2e), §8.

**Files:**
- Modify: `tests/e2e/pubspec.yaml` (dependency on `nanoflow_process` if needed), `tests/e2e/test/` (new test or extend `crash_resume_test.dart`): run the example (`examples/review`) as a process the way the existing crash test does, wait until a step has started, read the feed of an `FsReader` (real `MacProcesses`) on its `runs/` → `owner-changed(alive: true)` with the child's pid; `SIGKILL` the child → `owner-changed(alive: false)` within 5 s; `--resume` → `alive: true` with the new pid, then `session-finished`, and no `owner-changed` after it.
- Docs: main spec `docs/superpowers/specs/2026-10-03-code-first-design.md` §4.6 «Блокировка» (owner record, byte lock, clearing), §5.1 (`.owner.lock` contents), §8 (`owner-changed` row in the change table and its rules), §9 («Interrupted»); `README.md` (storage and UI parts); package READMEs touched by Tasks 1–6 (check they say it); `docs/ui-spec.md` (session card/bar «Interrupted», interrupted step); `apps/nanoflow_ui/README.md` rows.

- [ ] **Step 1:** Failing e2e test. **Step 2:** See it fail (or pass if Tasks 1–6 already make it pass — then say so in the report and make sure it fails when the reader is given `UnsupportedProcesses`). **Step 3:** Documents. **Step 4:** `tool/ci.sh`. **Step 5:** Commit (why: the whole path from a killed process to the reader's feed is pinned, and the documents describe the owner record).
