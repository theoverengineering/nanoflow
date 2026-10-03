# nanoflow_model

Договор между библиотекой и UI: то, что они должны понимать одинаково.
Единственный пакет, общий для всех частей репозитория; зависит только от
`path`, `collection` и `crypto`.
Подробнее — в [Хранении](../../README.md#хранение) и
[адаптере файловой системы](../../README.md#адаптер-файловой-системы).

## Что внутри

- **Идентификаторы.** `newId()` — случайный UUID v4 в нижнем регистре;
  `isId(s)` проверяет вид `8-4-4-4-12`.
- **Время.** `formatTime` пишет UTC с ровно тремя знаками после точки и `Z`
  (`2026-09-20T14:03:11.470Z`), микросекунд не бывает. `parseTime` читает
  только такую запись и бросает `FormatException` на любой другой. `Clock` —
  источник времени, `systemClock` — настоящие часы в UTC.
- **Раскладка `runs`.** Имена каталогов и файлов сессии, шага и документа
  (`runs/<воркфлоу>-<время>-<id>/`, `session.json`, `log.jsonl`,
  `.owner.lock`, `documents/<id>.json`, `steps/<время>-<имя>-<id>/` со
  `step.json` и `step.log`); знаки имени вне `[A-Za-z0-9._-]` — `_`.
  `idOfDirName` достаёт идентификатор из имени каталога, `isSessionDirName`
  узнаёт каталог сессии, `runsDirOf` — каталог `runs` в каталоге проекта.
- **Модели и их JSON.** `Session` (один вызов функции воркфлоу: `workflow`,
  снимок файла графа `graph`, `inputId`), `Step` (`name`, `key`, `after`,
  `place`, `outputId`, `log`) и `Document`; `Event` — событие журнала
  сессии (`session-started`, `session-resumed`, `step-started`,
  `step-finished`, `step-failed`, `session-finished`, `session-failed`),
  `Change` — изменение ленты читателя. У каждой `fromJson` и `toJson`: ключи
  пишутся в порядке спецификации, и все всегда есть, `null` — когда значения
  нет. Равенство по значению (для `Session.graph`, `Document.value` и
  `UnknownEvent.json` — глубокое). `fromJson` бросает `FormatException` с
  местом проблемы (`session.id`); `Event.fromJson` не бросает никогда:
  событие с незнакомым именем или с неподходящими полями становится
  `UnknownEvent`, который пишется обратно как был. Время события хранится в
  UTC с точностью до миллисекунд. У известных событий общий предок
  `KnownEvent` с `time`: `switch` по `Event` исчерпывается им и
  `UnknownEvent`.
- **Файл графа.** `GraphFile.fromJson` разбирает `nanoflow.graph.json`
  (`graphFileName`, формат `graphFileFormat`): функции с шагами
  (`GraphFunction`), их тела (`GraphBody`) из узлов `StepNode`,
  `ConditionNode`, `CallNode` и `CopiesNode` и рёбер `GraphEdge`, а также
  `GraphWarning`. `toJson` пишет ключи в порядке спецификации; `fromJson`
  бросает `FormatException`, начинающийся с пути в JSON
  (`functions.lib/a.dart#f.body.nodes[2].kind`), и отвергает формат, не равный
  1. `workflowNamed(name)` находит workflow-функцию по имени.
- **Исходники и отпечаток.** `packageSourcePaths`, `sourceHash` (`\r\n` читается
  как `\n`), `bytesHash`, `hashSources` и `fingerprintOf` считают `sources` и
  `fingerprint` файла графа одним кодом для `describe`, библиотеки и UI.
- **Состояние сессии.** `replaySession(events)` проигрывает журнал сессии и
  возвращает `SessionState`: `status` (`SessionStatus` — по последнему
  событию), `steps` (`StepState`: `status`, `starts`, `startedAt`,
  `finishedAt`, `outputId`, `error`) в порядке первых `step-started`,
  `startedAt`, `finishedAt`, `outputId`, `error`, `codes` (хэши кода
  `session-started` и каждого `session-resumed`) и `graphIds`. Незнакомые
  события пропускаются. Состояние не хранится: оно считается заново.

## Тесты

```bash
dart test
```
