# review

Граф из [«Формата»](../../README.md#формат), записанный на Dart, как в
[графе на Dart](../../docs/dart-graph.md): `graph.dart` — сама программа
графа. Имена узлов — имена переменных, поэтому `is-empty` здесь `isEmpty`.

```bash
cd examples/review
nanoflow run -- dart run graph.dart < input.json
```

Без установленного `nanoflow` — `dart run nanoflow_cli:nanoflow` вместо
`nanoflow`. Сессии ложатся в `runs/` рядом с `graph.dart`.

## Что происходит

Со входом из `input.json` — веткой `parseConfig`:

- `collect` берёт изменение ветки: здесь один файл `lib/parseConfig.dart`;
- `isEmpty` — файл есть, дальше `inspect`;
- `inspect` проверяет имя файла программой через `exec` (`sh -c`) и находит,
  что оно не в lower_snake_case;
- `verdict` — `returned`, `fix` переименовывает файл в
  `lib/parse_config.dart`;
- второй `inspect` замечаний не находит, `verdict` — `accepted`, и прогон
  разветвляется на `publish` и `notify`.

Ветка с пустым именем ничего не меняет и уходит в `discard`. Ровно этот
запуск проверяет `tests/e2e/test/review_example_test.dart`.
