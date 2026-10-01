# nanoflow_cli

Движок — команда `nanoflow`. Пока в нём только
[`nanoflow check`](../../README.md#nanoflow-check); `run` будет следом.

```bash
nanoflow check -- dart run graph.dart   # граф из --graph программы графа
nanoflow check < описание.json          # описание графа из stdin, как его даёт UI
```

## Что внутри

- **Проверка графа** (`src/check/`). `checkGraph` даёт ошибки графа в JSON,
  по строке `<место>: <что не так>`; место — путь в графе (`start`,
  `nodes.verdict.then.accepted`, `start[1]`), у самого графа — `graph`.
  - **Структура** — JSON Schema графа (draft 2020-12, `graph_schema.dart`),
    её выполняет `package:ack` (`Ack.fromJsonSchema`). ack останавливается
    на первой ошибке, поэтому ошибка структуры одна. Узел — рабочий или
    развилка через `oneOf`: `if`/`then`/`else` ack не импортирует. Когда
    `oneOf` не проходит, узел проверяется ещё раз схемой своего вида — по
    `command` или `decide`, — чтобы назвать настоящую ошибку.
  - **Смысл** — только если структура прошла: цели называют существующие
    узлы, в списке целей нет повторов и не одно имя, `start` не пуст, до
    каждого узла можно дойти от `start`. Строки — в порядке мест в графе.
  - `checkDescription` читает описание графа `{file, graph}` и проверяет его
    граф.
- **Программа графа** (`src/program.dart`). `GraphProgram` запускает её:
  `describe()` — `--graph`, описание с графом, прошедшим проверку;
  `validateInput()` — `--input`; `startCall()` — `--call <узел>`.
- **Команда** (`src/cli.dart`, `src/check/check_command.dart`). Ошибки — в
  stdout по одной в строке, код 0, если граф прошёл, иначе 1. Нет описания —
  одна строка `cannot read the graph: <причина>`; stderr программы графа
  идёт в stderr. Не те аргументы — usage в stderr, код 2.

## Тесты

```bash
dart test
```

Программы графа в тестах — короткие скрипты `sh` во временном каталоге.
