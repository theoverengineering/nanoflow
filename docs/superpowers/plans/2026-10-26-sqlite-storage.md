# Хранение сессий в SQLite — план

Спека: [2026-10-26-sqlite-storage-design.md](../specs/2026-10-26-sqlite-storage-design.md).
Каждый этап кончается зелёными `dart analyze --fatal-infos` и тестами
затронутых пакетов и коммитом; этап 4 — ещё `flutter analyze` и
`flutter test` UI; перед слиянием — `tool/ci.sh`.

## Этап 1. Контракт и файловые адаптеры за ним

1. `nanoflow_model/lib/src/storage.dart`: `SessionStore`, `OpenSession`,
   `EffectLog`, `SessionReader`; `SessionBusyException`,
   `SessionExistsException`, `StoreCorruptedException`. Экспорт.
2. `nanoflow_store`: `SessionHandle` → `FsSession implements OpenSession`
   (файл `fs_session.dart`), `EffectLog` → `FsEffectLog implements
   EffectLog` (`failed` — `Future<Exception>`), исключения — из модели.
   `FsStore implements SessionStore`: владелец — параметр `createSession` и
   `openSession`, а не конструктора; `id` в `createSession`.
3. `Owners` → `nanoflow_process` (зависит от `nanoflow_model`):
   `observe(sessionId, ({Owner? owner})? record)`; чтение `.owner.lock` —
   в `Scanner` `nanoflow_reader`. `FsReader implements SessionReader`.
4. `nanoflow`: `Flow({directory, store})`, по умолчанию `FsStore`;
   `owner: currentOwner()` в вызовах; `_stored` — любое `Exception`, кроме
   `SessionBusyException`/`SessionExistsException`, — `StorageException`;
   реэкспорт `SessionBusyException`, `SessionExistsException`,
   `SessionStore`. Тесты: `Flow(store:)` пишет и продолжает там.
5. Тесты пакетов — на новые имена и владельца в вызове.
6. `tests/contract`: места `fs:`/`sqlite:` (`support/places.dart`),
   программы `fixtures/hold.dart` (владеет сессией, пишет по командам stdin)
   и `fixtures/held.dart` (воркфлоу, который убивают в эффекте); набор
   `contract_test.dart` по каждой схеме: создание, id, эффекты/события/
   документы, порядок параллельных событий, `unfinishedSessions`, лог,
   занятость (другой процесс, этот изолят, смерть владельца), лента
   читателя при записи другим процессом, `owner-changed`, лог живьём,
   продолжение воркфлоу другим процессом.

## Этап 2. Id сессии от вызывающего

`Flow.start(…, id:)`: не uuid — `ArgumentError`, занятый —
`SessionExistsException`; `FsStore` считает занятым и `.tmp-<id>`. Тесты в
`nanoflow_store` и `nanoflow`. (Сделан вместе с этапом 1: тот же код.)

## Этап 3. `nanoflow_sqlite`

1. Пакет: `sqlite3: ^3.8.0`, `nanoflow_model`, `nanoflow_process`.
2. `schema.dart`: таблицы спеки §6.5, `nanoflow_meta.schema = 1`, WAL,
   `busy_timeout`; открытие на запись создаёт таблицы, на чтение — нет.
3. `SqliteStore`/`SqliteSession`/`SqliteEffectLog`: транзакции, владелец
   строкой с проверкой жизни через `Processes`, `_held` изолята, `rev`
   эффектов, лог кусками.
4. `SqliteReader`: опрос `PRAGMA data_version`, дочитывание по `seq`/`rev`
   в одной транзакции, `Owners`, лог эффекта живьём, ожидание базы.
5. Схема `sqlite` в `tests/contract`; README пакета.

## Этап 4. nanoflow_ui

1. Зависимость от `nanoflow_sqlite`; `SessionFeed`, `Outcomes`,
   `ReaderFiles` — на `SessionReader`.
2. `StoreDescription` (`fs:`/`sqlite:`, `~`), `GraphModel.open(file,
   store:)`.
3. Аргументы: раннер macOS передаёт `CommandLine.arguments` в Dart; `main`
   разбирает `<граф> [--store] [--session]`; выбор сессии, когда придёт.
4. «Recently opened» с хранилищем.
5. Пути `null` — строки и «показать в Finder» спрятаны (проверить, что уже
   так).

## Этап 5. ideaforge (после перемотки `main` nanoflow)

1. `ideas_store`: миграция без `runs`, без `runStep`/`finishRun`/`failRun`.
2. `ideas_flow`: `ideasFlow(db:)` → `Flow(store: SqliteStore(db))`; без
   `runId`; `generate.dart --session`.
3. Дашборд: прогоны — сессии `generateIdeas` из `SqliteReader`; запуск с
   uuid; «Запускается»/«Ошибка» в памяти; «Прервано»; подписи шагов; кнопка
   «Граф» (`open -n -a nanoflow_ui --args …`).
4. Правка дизайна ideaforge.

## Документация

README корня (репозиторий, хранение, чтение, UI), README пакетов
`nanoflow_model`, `nanoflow_store`, `nanoflow_reader`, `nanoflow_process`,
`nanoflow_sqlite`, `nanoflow`, UI.
