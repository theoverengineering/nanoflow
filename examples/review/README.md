# review

Граф ревью из README — графом из узлов: `review` в `lib/review.dart`.
Каждый шаг — узел `node('имя', (вход) async { … })`: единица работы, которая
выполняется как один эффект сессии и ничего не знает о других. Что за чем —
говорят переходы: функции от выхода узла, которые зовут следующий узел с тем,
что ему нужно; вызов `inspect(change)` ничего не выполняет, а говорит «дальше
этот узел с этим входом». `bin/main.dart` запускает граф как сессию nanoflow.

Узлы работают без сети и всякий раз одинаково (`lib/change.dart`): изменение
ветки — один файл, названный по ней; `inspect` проверяет имя файла программой
через `exec` (`sh -c`), как запускался бы ревьюер; `fix` переименовывает файл
в lower_snake_case.

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

- `collect` даёт `Empty` с веткой или `Found` с изменением; переход после
  него — `switch`, и компилятор проверяет, что случаи покрывают оба;
- после `inspect` переход — `?:`: без замечаний `{publish(r), notify(r)}`
  идут рядом, с замечаниями — `fix`;
- `fix` ведёт обратно в `inspect`;
- `Graph.join([publish, notify])` собирает их выходы в запись, и переход
  после неё отдаёт запись узлу `report`; тип записи, `(String, String)`,
  пишется в параметре перехода.

С веткой `parseConfig`: `collect` берёт файл `lib/parseConfig.dart`;
`inspect` находит, что имя не в lower_snake_case; `fix` переименовывает файл в
`lib/parse_config.dart`; второй `inspect` замечаний не находит, `publish` и
`notify` идут рядом, а за ними `report`. Ветка с пустым именем ничего не
меняет и уходит в `discard`.

Эффекты узлов носят имена узлов; их выходы раскодируются при `--resume`
кодеками `Change`, `Report` и `Collected`, и граф идёт той же дорогой: узлы,
которые кончились, берутся из журнала, переходы вычисляются заново по их
выходам, а узел, который не кончился до падения, выполняется заново целиком.

## Файл графа

`lib/review.graph.json` — граф, прочитанный из кода (`nanoflow_describe` —
`dev_dependency` примера), рядом с `lib/review.dart`; CI проверяет, что он
свежий. Его исходники — `lib/review.dart` и `lib/change.dart`, который тот
импортирует. Узел нарисован
эффектом на строке, где граф впервые называет узел, с комментарием над его
переменной. `switch` и `?:`, которыми переход решает сразу после узла, —
выходы этого узла (`collect` — `Empty` и `Found`, `inspect` —
`r.findings.isEmpty` и `else`).

```bash
dart run nanoflow_describe            # переписать после правки кода
dart run nanoflow_describe --check    # код 1, если файл устарел
mkdir -p build && dart compile exe bin/main.dart -o build/review
dart run nanoflow_describe stamp build/review   # хэш бинарника в builds и копия файла в build/lib/
```

`stamp` переписывает и `lib/review.graph.json` из репозитория — в его
`builds` появляется хэш бинарника, и git покажет файл изменённым. `--check`
`builds` не сравнивает, так что CI это не ломает; вернуть файл —
`git checkout lib/review.graph.json`.

Запуск, граф, хэш кода, Ctrl+C и продолжение проверяет
`tests/e2e/test/review_example_test.dart`.
