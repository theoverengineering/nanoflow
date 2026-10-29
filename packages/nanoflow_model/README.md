# nanoflow_model

Договор между библиотекой и UI: то, что они должны понимать одинаково, —
модели и порт хранилища, который реализуют адаптеры. Единственный пакет,
общий для всех частей репозитория; зависит только от `path`, `collection` и
`crypto`.
Подробнее — в [хранении](../../README.md#хранение) и
[файле графа](../../README.md#файл-графа).

## Что внутри

- **Идентификаторы.** `newId()` — случайный UUID v4 в нижнем регистре;
  `isId(s)` проверяет вид `8-4-4-4-12`.
- **Время.** `formatTime` пишет UTC с ровно тремя знаками после точки и `Z`
  (`2026-09-20T14:03:11.470Z`), микросекунд не бывает. `parseTime` читает
  только такую запись и бросает `FormatException` на любой другой. `Clock` —
  источник времени, `systemClock` — настоящие часы в UTC.
- **Раскладка `runs`.** Имена каталогов и файлов сессии, эффекта и документа
  (`runs/<воркфлоу>-<время>-<id>/`, `session.json`, `log.jsonl`,
  `.owner.lock`, `documents/<id>.json`, `effects/<время>-<имя>-<id>/` со
  `effect.json` и `effect.log`); знаки имени вне `[A-Za-z0-9._-]` — `_`.
  `ownerLockOffset` (`1 << 30`) — место в `.owner.lock`, байт которого
  блокирует владелец сессии: содержимое файла остаётся читаемым.
  `idOfDirName` достаёт идентификатор из имени каталога, `isSessionDirName`
  узнаёт каталог сессии, `runsDirOf` — каталог `runs` в каталоге проекта.
- **Модели и их JSON.** `Session` (один запуск графа: `workflow`,
  снимок файла графа `graph`, `inputId`), `Effect` (`name`, `key`, `after`,
  `place`, `outputId`, `log`), `Document` и `Owner` (процесс-владелец
  сессии: `pid` и `started` — время старта процесса, UTC до миллисекунд, в
  формате времени событий, `null`, когда ОС его не дала; это содержимое
  `.owner.lock`); `Event` — событие журнала
  сессии (`session-started`, `session-resumed`, `effect-started`,
  `effect-finished`, `effect-failed`, `session-finished`, `session-failed`),
  `Change` — изменение ленты читателя (среди них `OwnerChanged`: `owner` —
  запись из `.owner.lock` или `null`, `alive` — идёт ли процесс владельца,
  `null`, когда это неизвестно). У каждой `fromJson` и `toJson`: ключи
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
  (`graphFileName`, формат `graphFileFormat`): графы (`GraphFunction`; в
  снимках старых сессий — и функции с эффектами), их тела (`GraphBody`) из
  узлов `EffectNode`, `ConditionNode` и `CallNode` и рёбер `GraphEdge`, а
  также `GraphWarning` (с `function` — графом, в чьём объявлении оно; нет
  ключа — `null`); у графа и узла — `doc`, их документация. Вида `copies`
  больше нет: файл с ним не читается. `toJson`
  пишет формат 3 и ключи в порядке спецификации; `fromJson` бросает
  `FormatException`, начинающийся с пути в JSON
  (`functions.lib/a.dart#f.body.nodes[2].kind`). Формат 2, до `doc`,
  читается с `doc: null` — так читаются снимки старых сессий; другой формат
  отвергается: файл графа до эффектов (формат 1) не читается.
  `workflowNamed(name)` находит воркфлоу по имени.
- **Исходники и отпечаток.** `packageSourcePaths`, `sourceHash` (`\r\n` читается
  как `\n`), `bytesHash`, `hashSources` и `fingerprintOf` считают `sources` и
  `fingerprint` файла графа одним кодом для `describe`, библиотеки и UI.
- **Порт хранилища** (`storage.dart`) — интерфейсы, которые реализуют
  адаптеры (файловые `nanoflow_store` и `nanoflow_reader`, `nanoflow_sqlite`)
  и через которые пишет `nanoflow`, а читают UI и приложения:
  `SessionStore` (`createSession` с `id` и `owner`, `openSession`,
  `unfinishedSessions`), `OpenSession` — открытая сессия, которой владеет
  этот процесс (`events`, `effects`, `documentValue`, `createEffect`,
  `appendEvent`, `writeDocument`, `setEffectOutput`, `setEffectAfter`,
  `openLog`, `release`), `EffectLog` — лог эффекта на дописывание, ошибки
  отдаёт `failed`, а не бросает, — и `SessionReader` (`changes`,
  `documentValue`, `effectLog`, пути — `null` у хранилища без файлов).
  Исключения контракта — `SessionBusyException`, `SessionExistsException`,
  `StoreCorruptedException`; любое другое исключение хранилища — его сбой.
- **Состояние сессии.** `replaySession(events)` проигрывает журнал сессии и
  возвращает `SessionState`: `status` (`SessionStatus` — по последнему
  событию), `effects` (`EffectState`: `status`, `starts`, `startedAt`,
  `finishedAt`, `outputId`, `error`) в порядке первых `effect-started`,
  `startedAt`, `finishedAt`, `outputId`, `error`, `codes` (хэши кода
  `session-started` и каждого `session-resumed`) и `graphIds`. Незнакомые
  события пропускаются. Состояние не хранится: оно считается заново.

## Тесты

```bash
dart test
```
