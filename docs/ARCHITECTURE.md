# ARCHITECTURE — своя реализация по SPEC.md

Чистая реализация с нуля. Источник требований — только [SPEC.md](SPEC.md) и, позже, замеры оригинала (`docs/REFERENCE.md`). Код Compresto 1.27 не читаем и не копируем: так у собственного кода остаётся свобода выбора лицензии.

Рабочее имя — **MyCompressor**, bundle id `xyz.kurein.mycompressor`, URL-схема `mycompressor://`. Название, иконку и оформление нужно выбрать до релиза (этап 13).

## 1. Ключевые решения

| # | Решение | Почему | Альтернатива |
|---|---|---|---|
| D1 | **macOS 14+**, Swift 6, SwiftUI + AppKit там, где SwiftUI не хватает | `@Observable`, SwiftData/современные API; оригинал поддерживает 13+, но одна лишняя версия ОС стоит дорого | macOS 13 — придётся отказаться от Observation |
| D2 | Логика в **Swift Package `CompressorKit`**, приложение — тонкая оболочка | `swift test` за секунды без запуска UI; агенты и CI проверяют движки из терминала | всё в одном Xcode-таргете — медленные и хрупкие тесты |
| D3 | Утилита **`mycompressor-cli`** в том же пакете | каждый движок можно прогнать на корпусе файлов без интерфейса; основа приёмочных тестов | — |
| D4 | Проект Xcode генерируется из **`project.yml` (XcodeGen)**, `.xcodeproj` не хранится в git | текстовый, читаемый конфиг без конфликтов в `project.pbxproj`; XcodeGen уже установлен | Tuist; ручной `.xcodeproj` |
| D5 | Кодеры — **внешние программы через `Process`**, без линковки | собственный код не наследует GPL/AGPL утилит; любую утилиту можно заменить или обновить отдельно | линковка libav*/libwebp — лицензионные обязательства распространяются на приложение |
| D6 | **Без App Sandbox**: Developer ID + Hardened Runtime + нотаризация, распространение вне App Store | запуск Homebrew-Ghostscript, произвольные папки вывода, мониторинг любых папок, AppleEvents не нужны; так же делает оригинал | Sandbox + security-scoped bookmarks — несовместимо с внешним `gs` |
| D7 | Утилиты: в разработке — из Homebrew; в релизе — **установщик с закреплёнными версиями и SHA-256** в `~/Library/Application Support/MyCompressor/tools` | как у оригинала: маленький бандл, обновление утилит без перевыпуска приложения | вложить статические бинарники в бандл (+~100 МБ) |
| D8 | Ghostscript **не распространяем**: пользователь ставит его сам, при наличии Homebrew — кнопкой | AGPL; совпадает с поведением из SPEC §5 | — |
| D9 | История — **SQLite через GRDB**; настройки — `UserDefaults` (Codable); пресеты — JSON-файл | GRDB надёжен и даёт постраничную загрузку (50/100/200/500); пресеты удобно экспортировать | SwiftData — меньше зависимостей, но менее предсказуем |
| D10 | Локализация — **String Catalogs** (`.xcstrings`), 6 языков из SPEC §16; смена языка через `AppleLanguages` и перезапуск | штатный механизм Xcode | — |
| D11 | Уровни качества → параметры кодеров — **своя таблица `docs/QUALITY.md`**, откалиброванная по замерам оригинала | в SPEC их нет (§21); подбирать числа по наблюдаемому результату законно и проверяемо | — |

## 2. Модули

```
my-compressor/
├── project.yml                 # XcodeGen: таргеты App, AppTests, UITests
├── App/                        # SwiftUI + AppKit, без логики сжатия
│   ├── MyCompressorApp.swift   # @main: WindowGroup, Settings, MenuBarExtra
│   ├── MainWindow/             # список/сетка/дерево, боковая панель, пресеты, per-file
│   ├── Settings/               # вкладки General, Drop Zone, Folder Monitoring, Presets,
│   │                           #   PDF, AI Renaming, File Management, Appearance, Advanced
│   ├── DropZone/               # NSPanel у «чёлки», детектор перетаскивания, HUD
│   ├── Onboarding/
│   ├── Services/               # уведомления, сон, keep-awake, deep links, Open With
│   └── Resources/              # Localizable.xcstrings, Assets, Info.plist, entitlements
├── Packages/CompressorKit/
│   ├── Sources/CompressorKit/
│   │   ├── Model/              # FileKind, настройки по типам, Preset, OutputPolicy, Job
│   │   ├── Queue/              # JobQueue (actor), Scheduler, пауза/резюм/отмена
│   │   ├── Engines/            # Image, Video, Audio(MP3), GIF, PDF, EPUB + TargetSize
│   │   ├── Tools/              # ToolLocator, ToolInstaller (манифест версий+sha256), ProcessRunner
│   │   ├── Output/             # имена, коллизии, папки, корзина, «не больше оригинала»
│   │   ├── Metadata/           # EXIF/IPTC/XMP, ICC, DPI, даты файла, Finder-теги
│   │   ├── Automation/         # FolderWatcher (FSEvents), ClipboardWatcher, DeepLinkParser
│   │   ├── History/            # GRDB-хранилище и постраничная выборка
│   │   └── AIRename/           # протокол + OpenAI и Ollama
│   ├── Sources/mycompressor-cli/
│   └── Tests/CompressorKitTests/  + Fixtures/ (генерируются скриптом, не храним мегабайты)
├── scripts/                    # make-fixtures.sh, bootstrap.sh, release.sh
└── docs/                       # SPEC, ARCHITECTURE, PLAN, QUALITY, REFERENCE
```

Зависимости `CompressorKit`: GRDB (история) и ZIPFoundation (EPUB). Всё остальное — системные фреймворки (ImageIO, AVFoundation, PDFKit, UniformTypeIdentifiers) и внешние утилиты.

## 3. Ядро: модель и очередь

```swift
enum FileKind { case video, image, gif, pdf, epub }

struct CompressionSettings: Codable, Hashable {   // одна «боковая панель»
    var video: VideoSettings   // quality | targetSize, resolution, format, removeAudio, transparency
    var image: ImageSettings   // quality | targetSize, size, format
    var gif: GIFSettings       // quality, dimension, fps (для video→gif)
    var pdf: PDFQuality        // best/high/balance/low
    var epub: EPUBQuality      // best/high/balance/low
}

struct Job: Identifiable {
    let input: URL
    let kind: FileKind
    var override: PartialSettings?   // per-file, живёт только в сессии (SPEC §10)
    var state: JobState               // pending/running/done(result)/failed/skipped
}

protocol CompressionEngine: Sendable {
    associatedtype Settings
    func compress(_ input: URL, settings: Settings, to output: URL,
                  progress: @Sendable (Double) -> Void) async throws -> EngineResult
}
```

`JobQueue` — `actor`:
- параллелизм ограничен настройкой ядер CPU (SPEC §2);
- **Pause after current file**, **Resume (N files)**, **Cancel all** (SPEC §8);
- файлы можно добавлять во время работы;
- события (`AsyncStream<QueueEvent>`) отдаются в UI, HUD, уведомления и историю.

Общие правила вывода (модуль `Output`) применяются одинаково для всех движков:
1. пишем во временный файл рядом с целью;
2. если результат не меньше исходника — оставляем исходник и помечаем «не уменьшилось» (SPEC §6, §8);
3. имя по формату с токенами `{timestamp}` `{datetime}` `{date}` `{time}` `{quality}` `{resolution}`; при совпадении добавляем номер;
4. переносим метаданные и даты, ставим Finder-теги;
5. по флагу **Remove input file** исходник уходит в Корзину (`FileManager.trashItem`), и только после успешной записи результата.

## 4. Движки

| Движок | Чем | Ключевые моменты из SPEC |
|---|---|---|
| **Image** | декодирование — ImageIO (JPEG, PNG, HEIC, TIFF, BMP, DNG, WebP, AVIF; SVG — через рендер в `CGImage`); JPEG/TIFF — ImageIO; PNG — `pngquant` (+ без потерь `oxipng`, опционально); WebP — `cwebp`; AVIF — `avifenc` | 5 уровней качества и целевой размер (бинарный поиск по quality, результат JPG, «Couldn't reach target size»); 6 режимов размера, только уменьшение; сохранение DPI для JPEG/PNG; прозрачность при PNG→JPG — подложка, а не чёрный фон (§3) |
| **Video** | `ffmpeg` / `ffprobe`; кодеры `h264_videotoolbox`/`hevc_videotoolbox` или `libx264`/`libx265`; WebM — `libvpx-vp9`; альфа — VP9 в WebM, ProRes 4444/HEVC с альфой в MOV | прогресс из `-progress pipe:1`; 5 уровней + целевой размер (битрейт = цель/длительность − звук, двухпроходно); разрешения и Max-режимы без увеличения; FPS только вниз; звук копируется без перекодирования, все дорожки; нечётные размеры → чётные (§2) |
| **Audio (MP3)** | `ffmpeg -c:a libmp3lame -q:a 0` | каналы как в исходнике; ошибка, если звука нет (§7) |
| **GIF** | кадры из `ffmpeg` → `gifski` | качество → `--quality`, FPS 10–50, размеры 25/50/75%/процент/max width (§4) |
| **PDF** | Ghostscript `pdfwrite` с `-dPDFSETTINGS=/prepress\|/printer\|/ebook\|/screen` | поиск `gs` по абсолютным путям (Homebrew, MacPorts), а не через shell — у пользователя `gs` может быть алиасом; кнопка установки через Homebrew (§5) |
| **EPUB** | ZIPFoundation + Image engine | только JPEG/PNG/WebP; длинная сторона 2048/1536/1024; имя и формат файла сохраняются; картинка заменяется только при уменьшении; `mimetype` первым и без сжатия; DRM определяется по `META-INF/encryption.xml` (зашифрованы не только шрифты) → книга не меняется (§6) |

Все внешние вызовы проходят через `ProcessRunner`: аргументы массивом (без shell), таймаут, отмена (SIGTERM, затем SIGKILL), лимит ядер (`-threads`), сбор stderr в лог.

## 5. Приложение

| Часть | Реализация |
|---|---|
| Главное окно | `WindowGroup`; превью одного файла / сетка / дерево (порог — **Thumbnail preview limit**); боковая панель настроек по типам; **Preset** picker; per-file поповер; закрепление поверх окон |
| Строка меню | `MenuBarExtra`; приложение живёт после закрытия последнего окна; иконку в Dock и в строке меню можно скрыть |
| Drop Zone | неактивирующий `NSPanel` над «чёлкой»; глобальный монитор `leftMouseDragged` + `NSPasteboard(name: .drag)` показывает зону только для подходящих файлов; режимы Compress и Compress & Open in App; HUD прогресса и переименование результата |
| Настройки | сцена `Settings` с вкладками из SPEC §16–§17 |
| Автоматизация | `FolderWatcher` на FSEvents (глубина, время стабилизации, фильтр типов, пропуск скрытых и `.crdownload`); `ClipboardWatcher` — опрос `NSPasteboard.changeCount`, объединение быстрых копирований в партию |
| Deep links | `DeepLinkParser` — чистая функция `URL → Command` (`open`/`import`, все параметры SPEC §18), покрыта юнит-тестами; при сжатии через ссылку окно не показывается |
| Open With | типы документов в `Info.plist` с `LSHandlerRank = Alternate`, чтобы не стать обработчиком по умолчанию (SPEC §6, §16) |
| Сон и бодрствование | `IOPMAssertion` во время работы; после — алерт с отсчётом 10 с и `pmset sleepnow` |
| Уведомления | `UNUserNotificationCenter`; опция «только в фоне» |
| AI-переименование | протокол `Renamer`; OpenAI (ключ в Keychain) и Ollama (`localhost:11434`); картинка уменьшается до 512 px |

## 6. Тестирование

- **Юнит-тесты `CompressorKit`**: разбор deep links, имена и коллизии, правило «не больше оригинала», парсинг прогресса ffmpeg, отображение качества в параметры, детектор DRM в EPUB.
- **Тесты движков на корпусе**: `scripts/make-fixtures.sh` генерирует маленькие файлы (тестовое видео `ffmpeg -f lavfi testsrc`, картинки с альфой, EXIF и DPI, EPUB с картинками и обфусцированным шрифтом, PDF). Проверяем формат, размеры, уменьшение размера, сохранённые метаданные.
- **Приёмка по эталонам**: после этапа замеров (`docs/REFERENCE.md`) — размер результата в пределах ±15% от оригинала на тех же файлах, разрешение и формат совпадают.
- **UI**: дымовые XCUITest — запуск, добавление файла, сжатие, результат.
- Один скрипт для всего: `scripts/check.sh` = `swift test` + `xcodebuild test`.

## 7. Риски

| Риск | Что делаем |
|---|---|
| Drop Zone у «чёлки» — нестандартный UI, глобальный перехват перетаскивания | отдельный этап 10, прототип до полировки остального |
| Нет числовых параметров качества в SPEC | замеры оригинала + `docs/QUALITY.md`; до замеров — разумные значения по умолчанию |
| Лицензии утилит (pngquant GPLv3, gifski AGPL, FFmpeg с x264/x265 — GPL) | только как отдельные программы, ссылки на исходники и тексты лицензий в экране Acknowledgments; Ghostscript не распространяем |
| Gatekeeper и нотаризация для скачанных утилит | качаем через `URLSession` (без атрибута карантина) и сверяем SHA-256 из манифеста; запасной вариант — подписанные бинарники внутри бандла. Окончательно решаем на этапе 13 после пробной нотаризации |
| Сжатие портит файлы пользователя | запись во временный файл, атомарная замена, удаление исходника только после успеха, тесты на корпусе |
