# Управление версиями

Как Vacpack хранит версию, как её менять и какие файлы держатся в согласии.

Связано: [BUILD.md](BUILD.md) · [CHANGELOG.md](CHANGELOG.md) · [README.md](README.md)

## Источник правды

Версия в формате **MAJOR.MINOR.PATCH** ([Semantic Versioning](https://semver.org/)) и дата релиза живут только в `project.yml`:

```yaml
settings:
  base:
    MARKETING_VERSION: "X.Y.Z"
    VACPACK_RELEASE_DATE: "DD.MM.YYYY"
```

- **MAJOR** — несовместимые изменения: другой формат флагов CLI, другие правила вывода файлов.
- **MINOR** — новая возможность без поломки старого: новый формат, новый этап из [docs/PLAN.md](docs/PLAN.md).
- **PATCH** — исправления без новых возможностей.

Xcode берёт `MARKETING_VERSION` напрямую: из него `CFBundleShortVersionString` в Info.plist.

Windows берёт эту же версию при сборке через `Windows/Directory.Build.props`:
отдельно менять `.csproj` или скрипт Inno Setup не нужно. Предварительный тег может
иметь суффикс, например `v0.4.0-windows-preview.1`, при числовой версии `0.4.0` в
`project.yml`. Такой релиз отмечается как pre-release, пока Windows экспериментальна.

## Команды

`scripts/update_version.py` использует только стандартную библиотеку Python; виртуальное окружение не нужно.

| Команда | Версия | Дата релиза |
|---|---|---|
| `status` | показывает каждый файл; код выхода 1, если что-то разошлось | — |
| `bump patch\|minor\|major` | следующая по semver | сегодня |
| `sync X.Y.Z` | ставит `X.Y.Z` | сегодня |
| `sync` | заново раскладывает текущую версию источника | берётся из источника |

Флаги для `bump` и `sync`: `--release-date DD.MM.YYYY`, `--dry-run` (показать, что изменится, ничего не записывая).

```bash
python3 scripts/update_version.py status
python3 scripts/update_version.py bump patch
python3 scripts/update_version.py sync 0.2.0 --dry-run
```

`bump` и `sync` сначала печатают цель, потом каждый изменённый файл:

```text
Target version:      0.1.1
Target release date: 25.10.2026

Updated project.yml
Updated Packages/CompressorKit/Sources/CompressorKit/Version.swift
Updated README.md
Updated CHANGELOG.md
```

## Что синхронизирует скрипт

| Метка в `status` | Файл | Что меняется |
|---|---|---|
| `source` | `project.yml` | `MARKETING_VERSION` и `VACPACK_RELEASE_DATE` |
| `kit` | `Packages/CompressorKit/Sources/CompressorKit/Version.swift` | `number` и `releaseDate` — их показывают `vacpack --version` и окно About Vacpack |
| `readme` | `README.md` | строка `**Version:** …` под описанием |
| `changelog` | `CHANGELOG.md` | заголовок `## [X.Y.Z] - YYYY-MM-DD`: новая версия забирает заметки из `## [Unreleased]`, сверху появляется пустой `Unreleased` |

Текст заметок в CHANGELOG пишется руками; скрипт трогает только заголовки.

## Номер сборки

`CFBundleVersion` — не часть semver. `scripts/package.sh` при каждой сборке ставит его по времени UTC, например `20261018.143629`. Так macOS не путает новую сборку той же версии со старой: иначе Dock может показывать старую иконку из кэша. В окне About номер сборки стоит в скобках: «Version 0.1.0, released 18.10.2026 (build 20261018.143629)».

## Порядок релиза

1. Поднять версию:
   ```bash
   python3 scripts/update_version.py bump patch
   ```
2. Дописать в `CHANGELOG.md` заметки под новой версией (скрипт уже перенёс туда всё из `Unreleased`).
3. Проверить, что ничего не разошлось, и прогнать тесты — `scripts/check.sh` вызывает `status` сам:
   ```bash
   scripts/check.sh --ui
   ```
4. Коммит и push в `main`.
5. Собрать DMG: `scripts/package.sh`. Он откажется собирать, если `status` не `OK`, и назовёт файл `Vacpack-X.Y.Z.dmg`.

### Windows

После `bump` и заметок выполните `scripts/windows.ps1 -Mode check -RequireMediaTests`,
включите в коммит все исходники и тесты, затем запустите `scripts/release-windows.ps1`.
Он требует чистого Git и согласованных версий, собирает в новой staging-папке
установщик и ZIP со встроенной .NET и формирует `SHA256SUMS.txt`.
`BUILD.json` содержит коммит, runtime и `sourceDirty: false`.

Тег `vX.Y.Z-windows-preview.N` должен указывать на этот же коммит в обоих
репозиториях. Публикуется один набор файлов на GitHub и Forgejo с признаком
pre-release; стабильный macOS-релиз и `main` остаются самостоятельными.
Нельзя публиковать установщик из грязной рабочей копии, даже если `X.Y.Z` совпадает.

## Если что-то не так

**`status` показывает `DIFF`** — файл поправили руками. Запустите `sync`: он оставит версию и дату из `project.yml`.

**`status` показывает `MISSING` у `changelog`** — в `CHANGELOG.md` нет заголовка текущей версии. `sync` создаст его из `## [Unreleased]`.

**`error: Could not update …`** — строку, которую ищет скрипт, переформатировали. Верните вид из таблицы выше и запустите `sync` ещё раз. Скрипт сначала готовит все файлы и только потом пишет, так что после этой ошибки ничего не изменено.

**В приложении старая версия** — пересоберите DMG и переустановите приложение; проверьте `status`.

## Правило

Версию меняем только через `scripts/update_version.py` — никогда поиском и заменой по репозиторию. Источник правды — `project.yml`. Перед релизом всегда `status`.
