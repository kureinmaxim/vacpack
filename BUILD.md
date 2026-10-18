# BUILD — сборка Vacpack

Как собрать Vacpack из исходников: приложение для разработки, команду `vacpack`, тесты и DMG для установки.

Связано: [README.md](README.md) · [VERSION_MANAGEMENT.md](VERSION_MANAGEMENT.md) · [CHANGELOG.md](CHANGELOG.md) · [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

## Что получается

| Что | Чем собирается | Где лежит |
|---|---|---|
| Приложение Debug (для разработки и тестов) | `scripts/check.sh` или Xcode | `.build/xcode/Build/Products/Debug/Vacpack.app` |
| Приложение Release (универсальное: Apple Silicon и Intel) | `scripts/package.sh` | `.build/release/Build/Products/Release/Vacpack.app` |
| DMG для установки | `scripts/package.sh` | `.build/dist/Vacpack-X.Y.Z.dmg` |
| Команда `vacpack` | `swift build` | `Packages/CompressorKit/.build/{debug,release}/vacpack` |

Всё собранное лежит в `.build/` и в git не попадает. Проект Xcode `Vacpack.xcodeproj` тоже не коммитится: его генерирует XcodeGen из `project.yml`.

## Требования

- **macOS 14** или новее — чтобы запускать приложение. Собирать — на **Xcode 26** (проверено: Xcode 26.5, Swift 6.3, macOS 26.6). Форматтер `swift format` входит в Xcode.
- **Утилиты из Homebrew** — XcodeGen для проекта и программы, которые запускают движки:
  ```bash
  brew install xcodegen ffmpeg pngquant gifski webp libavif ghostscript
  ```
  Приложение ищет утилиты по абсолютным путям — `/opt/homebrew/bin`, `/usr/local/bin`, `/opt/local/bin` — и не через shell, поэтому алиасы вроде `gs=git status` не мешают.
- **Python 3** — только для `scripts/update_version.py` (стандартная библиотека, подойдёт и системный `/usr/bin/python3` 3.9).

## Шаг 1. Подготовить копию

```bash
git clone https://github.com/kureinmaxim/vacpack.git
cd vacpack
scripts/bootstrap.sh
```

`bootstrap.sh` ничего не ставит сам. Он проверяет Xcode, XcodeGen и утилиты. Если чего-то нет, печатает нужную команду `brew install …` и выходит с кодом 1. Затем генерирует `Vacpack.xcodeproj` и тестовые файлы (`scripts/make-fixtures.sh` → `Packages/CompressorKit/Tests/Fixtures/generated/`, в git их нет).

После установки или обновления Xcode нужен один раз (спросит пароль администратора):

```bash
sudo xcodebuild -runFirstLaunch
```

## Шаг 2. Разработка

```bash
open Vacpack.xcodeproj
```

Схема **Vacpack**, ⌘R — запуск, ⌘U — тесты. После правки `project.yml`, а также после добавления или удаления файлов в `App/`, `AppTests/`, `UITests/` перегенерируйте проект — Xcode сам новые файлы не увидит:

```bash
xcodegen generate
```

Движки — Swift-пакет `Packages/CompressorKit` с командой `vacpack`; его можно собирать и запускать без Xcode-проекта:

```bash
swift run --package-path Packages/CompressorKit vacpack --version
swift run --package-path Packages/CompressorKit vacpack tools
swift build --package-path Packages/CompressorKit -c release --product vacpack
```

Форматирование перед коммитом (проверка в `check.sh` строгая):

```bash
swift format --in-place --recursive App AppTests UITests Packages/CompressorKit/Sources Packages/CompressorKit/Tests
```

Посмотреть окно без запуска руками — снимки пустого окна, списка файлов и результатов в светлой и тёмной теме:

```bash
scripts/snapshot.sh     # → .build/snapshots/*.png
```

Скрипт собирает Debug и запускает приложение в режиме снимка (`VACPACK_SNAPSHOT`): окно прозрачное, рисует себя в PNG и закрывается, разрешение на запись экрана не нужно. Прокрутки в этом режиме нет, поэтому список и окно в снимке выше обычного.

## Шаг 3. Проверки

```bash
scripts/check.sh        # всё, кроме UI-тестов
scripts/check.sh --ui   # плюс UI-тесты
```

По порядку: `swift format lint --strict`, сверка версий (`update_version.py status`), тесты пакета `CompressorKit`, `xcodegen generate`, сборка приложения и его тесты. В конце — `All checks passed.`; при ошибке скрипт выходит с ненулевым кодом. Полный журнал сборки приложения — `.build/xcodebuild.log`.

При первом запуске UI-тестов macOS просит разрешить управление компьютером программе, которая их запускает (`VacpackUITests-Runner` или Xcode): **Системные настройки → Конфиденциальность и безопасность → Универсальный доступ**.

## Шаг 4. Версия — перед релизом

Версия MAJOR.MINOR.PATCH живёт только в `project.yml` и меняется только скриптом — подробно в [VERSION_MANAGEMENT.md](VERSION_MANAGEMENT.md):

```bash
python3 scripts/update_version.py bump patch
python3 scripts/update_version.py status
```

Затем допишите заметки под новой версией в `CHANGELOG.md` и прогоните `scripts/check.sh --ui`.

## Шаг 5. Release и DMG

```bash
scripts/package.sh   # → .build/dist/Vacpack-X.Y.Z.dmg
scripts/install.sh   # поставить этот DMG в «Программы»
```

Что делает `package.sh`:

1. Отказывается собирать, если версии разошлись (`update_version.py status`).
2. `xcodegen generate` и сборка Release для arm64 и x86_64 — журнал в `.build/release-build.log`.
3. Ставит номер сборки `CFBundleVersion` по времени UTC, например `20261018.144243`, и проверяет, что он попал в приложение.
   Туда же пишет коммит и дату push (`VacpackSource`, `VacpackSourceDate`) — их показывает About Vacpack. Дата push берётся из журнала `origin/main`; собранное до push помечено «not pushed yet», с незакоммиченными правками — «with local changes, not committed yet».
4. Проверяет подпись (`codesign --verify --deep --strict`).
5. Собирает DMG со ссылкой на «Программы» и проверяет его (`hdiutil verify`).

В конце печатает строку вида `Created .build/dist/Vacpack-0.1.0.dmg (3.7M, version 0.1.0, build 20261018.144243, x86_64 arm64)`.

**Установка на этот Mac** — `scripts/install.sh`. Он закрывает запущенный Vacpack, перекладывает прежнюю копию в Корзину (ничего не удаляет), копирует новую из DMG, заново регистрирует её в Launch Services, «забывает» копии в Корзине и перезапускает Dock. Без этого Dock может показывать пустую иконку из кэша, даже при новом номере сборки.

`scripts/package.sh --open` вместо этого открывает DMG в Finder — чтобы посмотреть его так, как увидят другие, и поставить вручную перетаскиванием. Для своего Mac это хуже `install.sh` (Dock не обновится), а DMG, который вы будете публиковать, в Finder лучше не открывать: однажды после этого локальный файл изменился, и его контрольная сумма перестала совпадать. Опубликованные копии остались верными, но проверяйте копию.

## Иконка

Иконка нарисована кодом в `design/AppIcon.swift`. Готовые PNG всех размеров лежат в `App/Resources/Assets.xcassets/AppIcon.appiconset` и коммитятся. После правки рисунка:

```bash
scripts/make-icon.sh
```

Затем пересоберите приложение.

## Подпись и другие Mac

Сборка подписана ad-hoc с hardened runtime, без нотаризации — Developer ID и нотаризация будут на этапе 13 ([docs/PLAN.md](docs/PLAN.md)). На Mac, где собирали, приложение открывается без вопросов. На другом Mac macOS его заблокирует: **Системные настройки → Конфиденциальность и безопасность → Всё равно открыть**. Там тоже нужны утилиты Homebrew из раздела «Требования» (без XcodeGen).

## Частые проблемы

**`Xcode needs its first-launch system components`** — выполните `sudo xcodebuild -runFirstLaunch` (шаг 1).

**`Missing prerequisites: … brew install …`** — выполните напечатанную команду и снова `scripts/bootstrap.sh`.

**`xcodebuild failed; full log: .build/xcodebuild.log`** — ищите в журнале первую строку с `error:`. Если новый файл «не найден», запустите `xcodegen generate`.

**UI-тесты висят или падают при первом запуске** — не выдано разрешение «Универсальный доступ» (шаг 3).

**`package failed: version files are out of sync`** — кто-то поправил версию руками. `python3 scripts/update_version.py status` покажет файл, `sync` вернёт версию из `project.yml`.

**В Dock старая или пустая иконка** — ставьте через `scripts/install.sh`: он перезапускает Dock. Если иконка всё равно старая:

```bash
touch /Applications/Vacpack.app
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Vacpack.app
killall Dock
```

**Сжатый файл не появился, в строке «would not get smaller — original kept»** — так и задумано: результат вышел не меньше исходника, и оригинал оставлен. Попробуйте уровень качества ниже или меньшее разрешение.

## Правило

Сборку для установки делаем только `scripts/package.sh`, версию меняем только `scripts/update_version.py`. Перед коммитом — `scripts/check.sh` (перед релизом — с `--ui`).
