# BUILD — сборка Vacpack

Как собрать Vacpack из исходников: приложения для Windows и macOS, CLI, тесты, установщик, ZIP и DMG.

Windows пока выпускается как предварительная версия из `codex/experimental-platform-support`. Возможности и отличия — в [Windows/README.md](Windows/README.md). Сначала описана Windows-сборка, затем прежний порядок для macOS.

Связано: [README.md](README.md) · [VERSION_MANAGEMENT.md](VERSION_MANAGEMENT.md) · [CHANGELOG.md](CHANGELOG.md) · [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

## Что получается

| Что | Чем собирается | Где лежит |
|---|---|---|
| Приложение Debug (для разработки и тестов) | `scripts/check.sh` или Xcode | `.build/xcode/Build/Products/Debug/Vacpack.app` |
| Приложение Release (универсальное: Apple Silicon и Intel) | `scripts/package.sh` | `.build/release/Build/Products/Release/Vacpack.app` |
| DMG для установки | `scripts/package.sh` | `.build/dist/Vacpack-X.Y.Z.dmg` |
| Команда `vacpack` | `swift build` | `Packages/CompressorKit/.build/{debug,release}/vacpack` |
| Windows Debug | `scripts/windows.ps1 -Mode check` | `Windows/Vacpack.Windows/bin/Debug/net8.0-windows/Vacpack.exe` |
| Windows x64, со встроенной .NET | `scripts/windows.ps1 -Mode package` | `.build/windows/Vacpack/Vacpack.exe` и соседние файлы |
| Установщик Windows | `scripts/windows.ps1 -Mode installer` | `.build/windows/Vacpack-Setup-X.Y.Z.exe` |
| Windows-релиз: установщик, ZIP, SHA-256 | `scripts/release-windows.ps1` | `.build/dist/vX.Y.Z-windows-preview.1/` |

Всё собранное лежит в `.build/` и в git не попадает. Проект Xcode `Vacpack.xcodeproj` тоже не коммитится: его генерирует XcodeGen из `project.yml`.

## Windows: подготовка и разработка

Для сборки нужны Windows 10/11 x64, [PowerShell 7](https://github.com/PowerShell/PowerShell/releases) (`pwsh`),
[.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0),
FFmpeg с `ffmpeg.exe` и `ffprobe.exe`. Для установщика нужен [Inno Setup 6](https://jrsoftware.org/isdl.php),
для проверки версии перед релизом — Python 3. Консольные проекты используют только
SDK и системные библиотеки; UI — WPF. Версия читается из `project.yml`.

Все примеры набираются в `pwsh`, а не во встроенном Windows PowerShell 5.1
(`powershell.exe`). `windows.ps1` работает в обоих, но `release-windows.ps1`
в 5.1 обрывается: тамошний `Compress-Archive` пишет имена записей в ZIP через
обратный слеш, и проверка содержимого архива их не находит.

```powershell
.\scripts\windows.ps1 -Mode run -ToolsDirectory 'C:\ffmpeg\bin'
.\scripts\windows.ps1 -Mode check -ToolsDirectory 'C:\ffmpeg\bin' -RequireMediaTests
```

`check` собирает WPF, запускает 27 проверок движка, 8 проверок миниатюр и снимок
окна с заполненной очередью. Проверяются фото/GIF, кадр короткого видео, EXIF-поворот,
кэш, отсутствие блокировки исходника и отказ миниатюры без отказа сжатия.
Для снимка нужен рабочий стол Windows. Без `-RequireMediaTests` и без FFmpeg
проверки внешних кодеров явно пропускаются; перед релизом пропуск запрещён.

Миниатюры загружаются в фоне двумя работниками, до 160 px по длинной стороне.
Фото читаются WPF, видео и неподдерживаемые системным декодером форматы — FFmpeg.
В памяти хранится не больше 128 записей кэша сервиса; временные PNG удаляются.
При недоступном/повреждённом файле остаётся значок его типа.

## Windows: папка и установщик

```powershell
.\scripts\windows.ps1 -Mode package
.\scripts\windows.ps1 -Mode installer
# Если прежний EXE запущен, публикуйте в другую папку:
.\scripts\windows.ps1 -Mode package -DestinationDirectory .build\windows\Vacpack-preview
```

Оба варианта self-contained, `win-x64`: .NET входит в поставку. Пакет runtime
закреплён в `scripts/windows.ps1` (`8.0.32`), для его первого получения нужен
nuget.org из `Windows/NuGet.Publish.Config`. `check` и `run` используют локальные
SDK reference packs и `Windows/NuGet.Config` без внешних источников.
FFmpeg и ffprobe устанавливаются отдельно. Установщик не подписан, ставит приложение
в профиль пользователя и включает деинсталлятор. Самопроверки не устанавливают его
в пользовательский профиль автоматически.

В опубликованной папке есть `BUILD.json`: версия, коммит, признак незакоммиченных
изменений и runtime. Обычная разработческая сборка может иметь `sourceDirty: true`;
релизная — только `false`.

## Windows: подготовка релиза

```powershell
python scripts/update_version.py bump minor --release-date 19.10.2026
python scripts/update_version.py status
# Дописать CHANGELOG и закоммитить все исходники, включая миниатюры и тесты.
# Только в PowerShell 7: в Windows PowerShell 5.1 релизный ZIP собирается неверно.
.\scripts\release-windows.ps1 -ToolsDirectory 'C:\ffmpeg\bin'
# При необходимости явно указать Python:
# .\scripts\release-windows.ps1 -ToolsDirectory 'C:\ffmpeg\bin' -PythonExecutable 'C:\Python313\python.exe'
```

Для текущего предварительного релиза версия — `0.4.0`, тег — `v0.4.0-windows-preview.1`.
Не запускайте `bump` повторно, если версия уже подготовлена. Полный порядок и текст
релиза — в [docs/releases/v0.4.0-windows-preview.1.md](docs/releases/v0.4.0-windows-preview.1.md).

`release-windows.ps1` отказывается работать с грязным Git, сверяет версии, выполняет
все проверки, создаёт новую staging-папку, собирает установщик и ZIP из одной папки
приложения и пишет `SHA256SUMS.txt`. `BUILD.json` должен указывать на зафиксированный
коммит и `sourceDirty: false`. Это исключает выпуск установщика с изменениями,
которых нет в соответствующем теге.

Публикуйте этот же тег и эти же три файла на GitHub и Forgejo с признаком
**pre-release**, без изменения `main` и без замены стабильного `v0.3.1`.
Из этого Windows-релиза DMG не собирается; изменения macOS требуют проверки на Mac.

## macOS: требования

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

Скриншоты для README — `scripts/snapshot.sh --readme`: берёт демо-файлы из `scripts/make-demo.sh` (три пейзажа, нарисованные кодом в `design/DemoImages.swift`, видео с фракталом и GIF «Жизнь» из генераторов ffmpeg — всё своё, публиковать можно), снимает пустое окно и результаты в светлой и тёмной теме и сжимает PNG в `docs/images/` через pngquant.

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

**Windows: `Release archive is incomplete`** — релиз собирался во встроенном Windows PowerShell 5.1. Его `Compress-Archive` записывает имена в ZIP как `Vacpack\BUILD.json`, а проверка ищет `Vacpack/BUILD.json`. Запускайте `scripts/release-windows.ps1` в `pwsh`.

**Windows: `Get-FileHash : The term 'Get-FileHash' is not recognized`** — `powershell.exe` 5.1 запущен из сессии `pwsh` и унаследовал её `PSModulePath`, поэтому грузит модули PowerShell 7 вместо своих, и часть команд пропадает. Лечится тем же — собирайте в `pwsh`. Проверить подмену: `Get-Module Microsoft.PowerShell.Utility | Format-List Name,Version,Path`.

## Правило

Версию меняем только `scripts/update_version.py`. Для macOS установка собирается
`scripts/package.sh`, проверки — `scripts/check.sh` (перед релизом с `--ui`). Для
Windows проверяем `scripts/windows.ps1 -Mode check -RequireMediaTests`, установщик
собираем через `-Mode installer`, полный релиз — `scripts/release-windows.ps1`.
Windows-скрипты запускаем в PowerShell 7 (`pwsh`).
