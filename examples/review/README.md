# review

Граф ревью из README — обычной функцией воркфлоу: `review` в
`lib/review.dart`, шаги — вызовы `f.step`, развилка — `if`, петля — `while`,
`publish` и `notify` рядом — `Future.wait`. `bin/main.dart` запускает её как
сессию nanoflow. Шаги работают без сети и всякий раз одинаково: изменение
ветки — один файл, названный по ней; `inspect` проверяет имя файла
программой через `exec` (`sh -c`), как запускался бы ревьюер; `fix`
переименовывает файл в lower_snake_case.

```bash
cd examples/review
dart run bin/main.dart parseConfig          # печатает id сессии
dart run bin/main.dart --resume <id>        # продолжает сессию
```

- Сессии — в `runs/` рядом с `pubspec.yaml`, у собранной программы — рядом
  с бинарником.
- Ctrl+C — `flow.stop()`: программа `exec` останавливается, в сессию больше
  ничего не пишется, код выхода 130; `--resume` доведёт сессию до конца.
  Другой сбой — текст в stderr, код 1; сессию, которую ведёт другой процесс,
  `--resume` не берёт (`SessionBusyException`).

## Что происходит

С веткой `parseConfig`:

- `collect` берёт изменение ветки: файл `lib/parseConfig.dart`;
- `inspect` находит, что имя не в lower_snake_case;
- `fix` переименовывает файл в `lib/parse_config.dart`;
- второй `inspect` замечаний не находит, и `publish` и `notify` идут рядом,
  каждый пишет строку в свой лог.

Ветка с пустым именем ничего не меняет и уходит в `discard`.

## Файл графа

`nanoflow.graph.json` — граф, прочитанный из кода (`nanoflow_describe` —
`dev_dependency` примера); CI проверяет, что он свежий.

```bash
dart run nanoflow_describe            # переписать после правки кода
dart run nanoflow_describe --check    # код 1, если файл устарел
mkdir -p build && dart compile exe bin/main.dart -o build/review
dart run nanoflow_describe stamp build/review   # хэш бинарника в builds и копия файла рядом
```

Запуск, граф, хэш кода, Ctrl+C и продолжение проверяет
`tests/e2e/test/review_example_test.dart`.
