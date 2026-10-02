# tool/dev

Помощники для ручной и живой проверки UI. В CI не участвуют.

## `fake-nanoflow-yaml`

Тестовая подмена `nanoflow-yaml` — **не программа для YAML**: программы для
YAML в репозитории нет, YAML здесь никто не разбирает. Подмена нужна, чтобы
открыть в UI граф и смотреть его прогоны вживую.

`fake-nanoflow-yaml <каталог>/<имя>.yaml <аргументы…>` запускает программу
графа на Dart `<каталог>/<имя>.dart` с теми же аргументами, через
`dart run`. Файл `.yaml` только называет файл `.dart`, его содержимое не
читается. Поэтому `--graph --watch` печатает описания программы на Dart, и
правка `.dart` сразу видна в `Current graph`; `--input` и `--call` тоже
работают — `nanoflow run -- fake-nanoflow-yaml graph.yaml` проходит граф.
Программа вне workspace берёт пакеты по `.dart_tool/package_config.json`
workspace (сначала `dart pub get` в корне).

Как поставить вместо `nanoflow-yaml` — рядом с собранным `nanoflow`, первыми
в `PATH`:

```bash
mkdir -p /tmp/nf/bin
dart compile exe apps/nanoflow_cli/bin/nanoflow.dart -o /tmp/nf/bin/nanoflow
ln -s "$PWD/tool/dev/fake-nanoflow-yaml" /tmp/nf/bin/nanoflow-yaml

mkdir /tmp/nf/review
cp examples/review/graph.dart examples/review/input.json /tmp/nf/review/
touch /tmp/nf/review/graph.yaml
cd /tmp/nf/review
PATH=/tmp/nf/bin:$PATH nanoflow run -- nanoflow-yaml graph.yaml < input.json
```

Каталоги сессий называются `graph-…`, как и `graph.yaml`, так что UI,
открывший `/tmp/nf/review/graph.yaml`, видит их. Приложение берёт `PATH` у
login shell; чтобы оно нашло подмену, его запускают из терминала с этим
`PATH` (`build/macos/Build/Products/Debug/nanoflow_ui.app/Contents/MacOS/nanoflow_ui`)
или гоняют живой тест — `apps/nanoflow_ui/README.md`, «Живой тест».
