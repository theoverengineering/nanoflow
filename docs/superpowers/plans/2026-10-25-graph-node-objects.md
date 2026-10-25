# Graph nodes as `node(...)`, arrows as functions — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the graph-of-nodes form (function nodes, maps of targets, sets, `otherwise`, `Exit`) with nodes made by `node('name', (I x) async {…})` and arrows that are Dart functions returning `nextNode(arg)`.

**Architecture:** `package:nanoflow` gets `Node<I, O>`, `node()`, `Next`, and a `Graph` whose `call(input)` is a transition and whose `run(f, input)` is the workflow; `graph_run.dart` runs a node as an effect typed by `O`, calls each part's route on its output and follows the `Next`s it gives. `nanoflow_describe` reads `node(...)` variables and the bodies of routes (switch expressions, `?:`, `if`/`switch` statements with `return`, sets, `null`) into the same graph-file node kinds, so the UI does not change.

**Tech Stack:** Dart 3 (pub workspace), `package:analyzer` in `nanoflow_describe`, `package:test`, Flutter only for `tool/ci.sh`'s UI suite (UI code untouched).

**Spec:** `docs/superpowers/specs/2026-10-25-graph-node-objects-design.md` (read it; it replaces §2–§5, §7, §9–§10 of `docs/superpowers/specs/2026-10-08-graph-nodes-design.md`, whose §6 joins still hold).

## Global Constraints

- Graph file format stays `3`; no new node kinds; `apps/nanoflow_ui` is not changed.
- A node runs as one effect named `name`; its result is journaled with the codec of `O` (`codecs.of<O>()`); an unfinished node reruns whole on resume.
- `.next` takes only a function `Object? Function(O output)`; a route gives a `Next`, a `Set` of `Next`s (side by side), or `null` (branch ends, output goes to the graph result); anything else is a `StateError` naming the node and what the route gave.
- A node's place is per graph: the line where it is first named in that graph's declaration (part head or a call in a route); `Session.placeOfNode(graph, node)` keeps looking it up by graph name and node name.
- Joins keep the old semantics (2–6 different nodes, queues, incomplete join never fires, continuation from the first node's branch); a join part is `Part<Never>`, so its route annotates its record parameter.
- A join member without its own arrows is not an end of the graph.
- No new dependencies. `dart format` clean, `dart analyze` clean under `package:lints/recommended.yaml`.
- Code comments and dartdoc in English; README and specs in Russian, in the voice of the files around them.
- Commit subjects say why, not what (`~/.claude/CLAUDE.md`), and end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Each task leaves its own package's `dart analyze` and `dart test` green; `tool/ci.sh` as a whole is red between Task 1 and Task 3 (describe's fixtures, the example and e2e use the old API until they are rewritten) and must pass at the end of Task 3.

## Review Focus

- A route that gives a `List` of transitions (`[a(x), b(y)]`) instead of a set — a reasonable person writes this; it must fail with the `StateError` that says a route gives a `Next`, a set of them or `null`, not with a cast error deep in the runner. Test in Task 1.
- A route that throws (e.g. a `switch` statement's `default: throw`) — the session must fail with that error once the other branches end, like a node that throws. Test in Task 1.
- The same `node(...)` used in a graph and in a graph nested in it as a node — the two tiles must get different places in the graph file and each effect must take the place of the graph it ran in. Tests in Task 1 (runtime place lookup) and Task 2 (describe places).
- A route returning a node whose name another node of the same graph already has — must be a `StateError` at run time, not a silent mix-up of effect keys. Test in Task 1.
- A graph used as a node whose route gives the next step from its result — the outer graph must get the inner graph's result as the route's argument, also on resume. Test in Task 1.

---

### Task 1: The library — `node`, routes, `Graph.run`

**Files:**
- Modify: `packages/nanoflow/lib/src/graph.dart` (rewrite)
- Modify: `packages/nanoflow/lib/src/graph_run.dart`
- Modify: `packages/nanoflow/lib/src/flow.dart:352-371` (`nodeEffect`)
- Modify: `packages/nanoflow/lib/src/project.dart:95-110` (`workflowNameOf`)
- Modify: `packages/nanoflow/lib/src/codecs.dart` (remove `Codecs.resultOf` and what only it uses)
- Modify: `packages/nanoflow/lib/nanoflow.dart` (exports)
- Test: `packages/nanoflow/test/graph_test.dart` (rewrite), `packages/nanoflow/test/graph_run_test.dart` (rewrite), `packages/nanoflow/test/codec_types_test.dart` (drop the `resultOf` group)

**Interfaces:**
- Produces (exported from `package:nanoflow`: `Node`, `node`, `Next`, `Graph`, `Part`; `Exit` is gone):
  - `sealed class Nodelike<I, O> { String get name; Next call(I input); }` — not exported; `Node` and `Graph` extend it.
  - `final class Node<I, O> extends Nodelike<I, O>` with `final String name`, `final FutureOr<O> Function(I input) body`, `Next call(I input)`; internal (not exported, used by the runner): `FutureOr<Object?> runWith(Object? input)` (casts `input as I` inside the class, so a `Node<String, X>` seen as `Nodelike<Object?, X>` never reads `body` through the supertype) and `TypeCodec outputCodec(Codecs codecs) => codecs.of<O>()`.
  - `Node<I, O> node<I, O>(String name, FutureOr<O> Function(I input) body)`.
  - `final class Next` with `final Nodelike<Object?, Object?> target`, `final Object? input`; private constructor.
  - `final class Graph<I, O> extends Nodelike<I, O>`: `Graph(String name, List<Part<Object?>> parts)`, `Next call(I input)`, `Future<O> run(Flow f, I input)`, internal `Future<Object?> runWith(Flow f, Object? input)`; `static Part<O> start<O>(Nodelike<Object?, O> node)`, `static Part<O> part<O>(Nodelike<Object?, O> node)`, `static Part<Never> join(List<Nodelike<Object?, Object?>> nodes)`.
  - `final class Part<O>`: `Part<O> next(Object? Function(O output) route)` — wraps `route` into `Object? Function(Object?)` casting inside, so the runner calls it without knowing `O`.
  - `Graph<Object?, Object?>? graphOfRun(Function function)` (replaces `graphOfCall`): the graph whose `run` tear-off `function` is; `workflowNameOf` uses it.
  - `Future<Object?> nodeEffect(Flow flow, String graph, Node<Object?, Object?> node, Object? input)` in `flow.dart`: `session.effect<Object?>(node.name, () => node.runWith(input), codec: node.outputCodec(flow._codecs), place: () => session.placeOfNode(graph, node.name))`.

- [ ] **Step 1: Write the failing tests in `graph_test.dart`** (creation and shape):
  - `builds the shape: starts, nodes by name, a route on each part` — `Graph('g', [Graph.start(a).next((x) => b(x)), Graph.part(b).next((x) => null)])` has starts `['a']`, nodes `['a', 'b']`.
  - `a node only a route reaches is not declared up front` — a graph whose last node appears only inside a route builds without error.
  - `call gives a Next, it runs nothing` — `final n = a('in'); expect(n.target, same(a)); expect(n.input, 'in');` and `body` was not called (a counter stays 0); same for `graph('in')`.
  - `graphOfRun finds a graph by its run` — `graphOfRun(g.run)` is `g`; `graphOfRun(someTopLevelFunction)` is `null`; `workflowNameOf(g.run) == 'g'`.
  - group `rejects`: `a graph without a start`; `arrows of a node declared twice` (two parts on `a`, and `.next(...).next(...)` on one part); `two nodes of one name` (two `node('a', …)` objects as part heads); `a join of too few, too many or repeated nodes`; `several problems at once, each on its line` — each an `ArgumentError` whose message contains the line used today (`'the graph has no start'`, `'the arrows of a are declared twice'`, `'two nodes are named a'`, `'a join takes 2 to 6 different nodes'`).

- [ ] **Step 2: Run them to see them fail**

  Run: `cd packages/nanoflow && dart test test/graph_test.dart`
  Expected: compile errors (`node`, `Next`, `run` undefined).

- [ ] **Step 3: Rewrite `graph.dart`** with the interfaces above. Keep `GraphShape`/`ShapeNode`/`ShapeJoin` but: `ShapeNode` holds `Nodelike` and `Object? Function(Object?)? route` instead of `Routes`; `NodeKind`, `Routes`, `AllRoutes`, `CaseRoutes`, `Exit`, `staticNameOf` use and the reachability check go away. `GraphShape` gets `ShapeNode nodeFor(Nodelike node)` — identity lookup, made on first sight; a new object whose name another node of the graph has throws `StateError('graph "$name": two nodes are named $nodeName')`.

- [ ] **Step 4: Run `graph_test.dart`** — Expected: PASS.

- [ ] **Step 5: Write the failing tests in `graph_run_test.dart`** (rewrite the file; keep its `Change`/`Report` codecs, replace `Collected`/`Empty`/`Found` by a plain sealed class with `fromJson`, no `Exit`):
  - `a node runs as an effect named after it, its result journaled with the codec of O` — the journal has `effect-finished` for `collect#1@…` and the JSON of the result.
  - group `routes`: `a switch on a sealed output gives each case its own next node and argument`; `the other way of the same graph`; `?: on a bool picks one`; `a set runs both side by side`; `null ends the branch and its output is the result`; `a loop goes round until the route leaves it`; `a List of transitions is a StateError naming the node` (message contains `'a route gives a Next, a set of them or null'` and the node's name); `a route that throws fails the session once the other branch has ended`; `a node of a name another node of the graph has is a StateError`.
  - group `joins` (old cases under the new form): `fire once for each full set, round a loop`; `that never fill up end their branch, and the graph ends`; `a join member without its own arrows is no end of the graph` (the graph's result is the join target's output, not a member's).
  - `a graph is a node: it runs on its own effects, and its result goes into the outer route` — outer route switches on the inner graph's result.
  - `a workflow function runs a graph with run`.
  - `a session of a graph is named after it, unfinished finds it, and resume takes finished nodes from the journal and reruns an unfinished one whole` — a node that counts its runs: run 1 crashes inside node 2 (`flow.stop()` or a throwing body after a marker), resume: node 1 not rerun (counter 1), node 2 rerun (counter 2).
  - `a node whose output has no codec fails as it runs, with a CodecException`.
  - group `the place of a node's effect`: `is the one the graph file gives the node in that graph` — a graph file with the same node name in two graphs at different places; each effect gets its own graph's place; `is null without a graph file`.
  - `gives the same keys and the same after whatever the timing` — the existing random-delay test under the new form.

- [ ] **Step 6: Run them to see them fail** — `dart test test/graph_run_test.dart`, expected: failures/compile errors.

- [ ] **Step 7: Implement `graph_run.dart`, `nodeEffect`, `workflowNameOf`.** `_call`: a `Node` → `nodeEffect(flow, shape.name, node, value)`; a `Graph` → `graph.runWith(flow, value)`. After an output: no route and no join → result; route → `_targets(route(output))`: `Next` → one target via `shape.nodeFor(next.target)` with `next.input`; `Set` whose every element is a `Next` → all of them side by side; `null` → result, branch ends; otherwise `StateError('the route of ${node.name} gave $value: a route gives a Next, a set of them or null')`. A route that throws is the branch's error (as a node's).

- [ ] **Step 8: Remove `Codecs.resultOf`** and the code only it uses; delete the `resultOf` group in `codec_types_test.dart`.

- [ ] **Step 9: Run the package's tests and analysis**

  Run: `cd packages/nanoflow && dart analyze && dart test`
  Expected: `No issues found!`, `All tests passed!`

- [ ] **Step 10: Commit:**

```bash
git add packages/nanoflow
git commit   # why: a map of targets went unchecked by the compiler and could not hand the next node what it needs
```

---

### Task 2: `describe` — nodes, routes, places, docs, warnings

**Files:**
- Modify: `packages/nanoflow_describe/lib/src/graphs.dart` (rewrite)
- Create: `packages/nanoflow_describe/lib/src/routes.dart` (`part of 'extract.dart'`; the route reader)
- Modify: `packages/nanoflow_describe/lib/src/extract.dart` (index `node(...)` variables beside graphs; add `part 'routes.dart';`; drop what only the map form used)
- Modify: `packages/nanoflow_describe/test/fixtures/graphs/lib/graphs.dart`, `packages/nanoflow_describe/test/fixtures/graph_warnings/lib/graph_warnings.dart` (rewrite for the new form)
- Test: `packages/nanoflow_describe/test/graphs_test.dart`

**Interfaces:**
- Consumes: Task 1's API (`node`, `Node.call`, `Graph.call`, `Graph.start/part/join`, `Part.next`, `Graph.run`).
- Produces: graph file bodies per spec §8 — `EffectNode(name: node name, place: first mention of the node in this graph's declaration, doc: comment over the node's variable)`, `CallNode(functions: [graph id], place: first mention)`, `ConditionNode` for each drawn fork of a route, edges as below; `GraphFunction.doc` = comment over the graph's variable. `workflows` also lists graphs passed as `x.run` to `Flow.start/run/resume`.

Route reading (spec §8–§9), in `routes.dart`:
- A route is the function literal in `.next(...)` or a reference to a top-level function (read its body); anything else → warning `route not drawn: <source>`.
- Expression body or `return e`: `e` is read as a value —
  - `n(arg)` / `g(arg)` where `n` is a `node(...)` variable or `g` a graph variable (resolved AST may be `FunctionExpressionInvocation` or `MethodInvocation(target: null)`; reuse `_graphCalled`'s pattern) → edge to that node;
  - set literal → edge to each element's node;
  - `null` → edge to the end;
  - `switch` expression → a fork labelled `switch (<subject source>)`, one edge per case labelled with the case's pattern source including its `when` guard;
  - `c ? a : b` → a fork labelled `<c source>`, edges `true`/`false`;
  - anything else → warning `route value not drawn: <source>`.
- Block body: `if`/`else` → fork `<condition source>`, `true`/`false`; `switch` statement → fork `switch (<expression source>)`, one edge per member (`default` → `default`); `return` reads its value; falling off the end → edge to the end; other statements without a `return` inside are skipped.
- A fork all of whose outcomes reach the same single target is not drawn (the outcome goes straight there), as in the function extractor.

- [ ] **Step 1: Rewrite the fixtures.** `graphs.dart`: nodes made with `node(...)` (with and without `///` docs), a graph using a switch-expression route over a sealed output, a `?:` route, a set (parallel), `null`, a join with an annotated record parameter, a block-body route with `if` and `switch` statements, a graph used as a node of another graph, the same node in both graphs, a top-level function as a route, and `flow.run(g.run, …)` in `bin/main.dart`. `graph_warnings.dart`: one of each warning below.

- [ ] **Step 2: Write the failing tests in `graphs_test.dart`:**
  - `draws graphs of nodes: effects at their first mention, forks for switch and ?:, edges for sets and null, joins, a graph as a call` — the whole expected file via `expectedFile`/`expectFile` (support.dart).
  - `the same node in two graphs has a place of its own in each`.
  - `gives nodes and graphs the doc comment over their variable`.
  - `warns` — exact messages and places for: a node or graph not in a top-level variable (`'a node outside a top-level variable is not drawn'`, `'a graph outside a top-level variable is not drawn'`); a name that is not a string literal (`'node name is not a string literal'`, `'graph name is not a string literal'`); two nodes named alike in one graph (`'two nodes are named <n> in graph <g>'`); `route not drawn: …`; `route value not drawn: …`; a node that cannot be reached (`'<n> cannot be reached'`); a join route whose parameter is not the record of its members' outputs (`'the route of the join takes <T>, not the record of its nodes\' outputs'`); a side effect in a route (the side-effect rules used outside effects in a workflow function); a graph used as a node of another graph that can end in several ends at once — two or more targets of one set transition each reach an end edge without passing a join (`'graph <g> is a node and can end in several ends at once'`).

- [ ] **Step 3: Run them to see them fail** — `cd packages/nanoflow_describe && dart test test/graphs_test.dart`.

- [ ] **Step 4: Implement** `graphs.dart` and `routes.dart` per the rules above; types of a node come from its variable's static type `Node<I, O>`; remove the map-of-targets code (`_keyPayload`, `_coversAll`, `_exitValue`, `_subjectOf`, `_keyElement`, the target-type `_check`), keeping `_checkJoin` adapted to the join route's parameter.

- [ ] **Step 5: Run the package's tests and analysis** — `dart analyze && dart test` in `packages/nanoflow_describe`; expected all pass, no issues.

- [ ] **Step 6: Commit** — why: describe could not read graphs whose nodes are `node(...)` and whose arrows are routes.

---

### Task 3: The example, e2e and the documents

**Files:**
- Modify: `examples/review/lib/review_graph.dart`, `examples/review/bin/graph.dart`, `examples/review/nanoflow.graph.json` (regenerated), `examples/review/README.md` if it shows the graph
- Modify: `tests/e2e/test/review_example_test.dart`
- Modify: `README.md` (section «Граф из узлов» and the `flow.run(reviewGraph.call, …)` line in «Библиотека»), `packages/nanoflow/README.md` (graph section), `packages/nanoflow_describe/README.md` (bullet «Графы из узлов» and the graph warnings)
- Modify: `docs/superpowers/specs/2026-10-03-code-first-design.md` §4.1, §6.1, §7.1 (graph mentions); `docs/superpowers/specs/2026-10-02-code-first-decisions.md` decision 14; `docs/superpowers/specs/2026-10-08-graph-nodes-design.md` (a note at the top: the form of nodes and arrows is replaced by the 2026-10-25 design)

**Interfaces:**
- Consumes: Tasks 1–2.
- The example's shape (e2e asserts it): `sealed class Collected` with `static Collected fromJson(Map<String, Object?>)` and `toJson()`; `final class Empty implements Collected { Empty(this.branch); final String branch; }` (`{'branch': …}`); `final class Found implements Collected { Found(this.change); final Change change; }` (the change's JSON); nodes `collect`, `inspect`, `fix`, `discard`, `publish`, `notify`, `report` as in spec §2, built on `review.dart`'s `collect`, `inspect` and `fix`; graph `reviewGraph` named `'reviewGraph'`; `bin/graph.dart` registers `Change`, `Report`, `Collected` codecs and runs `reviewGraph.run`.

- [ ] **Step 1: Update the e2e expectations** in `review_example_test.dart` for the graph test: effects at their first mention in `reviewGraph`'s declaration with their docs, a fork `switch (collected)` with edges `Empty(:final branch)` / `Found(:final change)`, a fork for the `?:` route with `true` (to `publish` and `notify`) and `false` (to `fix`), the join of `publish` and `notify` into `report`; the run-to-the-end and resume-after-SIGKILL tests unchanged in intent.
- [ ] **Step 2: Run it to see it fail** — `cd tests/e2e && dart test test/review_example_test.dart`.
- [ ] **Step 3: Rewrite the example**, regenerate its graph file (`cd examples/review && dart run nanoflow_describe`), run `dart run nanoflow_describe --check` (exit 0).
- [ ] **Step 4: Run e2e** — expected PASS.
- [ ] **Step 5: Update the documents** listed above to the new form (spec §10); decision 14 says graphs of nodes are written with `node(...)` and routes and links the 2026-10-25 design, and keeps that code and nodes are two equal ways.
- [ ] **Step 6: Run the whole suite** — `tool/ci.sh`, expected exit 0.
- [ ] **Step 7: Commit** — why: the example and the documents still showed maps of targets and `Exit`, which the library no longer has.
