# PROMT_MAC — что доработать в Vacpack на Mac

Этот файл — готовое задание для Claude Code на **Mac**. Скопируйте его целиком в сессию в корне репозитория (или напишите «выполни PROMT_MAC.md»). Он описывает, что появилось в Windows-версии (`Windows/`, версии 0.4.0 → 0.6.0) и чего ещё нет в macOS-приложении (`App/`, `Packages/CompressorKit/`), а что на Mac уже сделано и нужно лишь проверить.

Связано: [CLAUDE.md](CLAUDE.md) · [BUILD.md](BUILD.md) · [CHANGELOG.md](CHANGELOG.md) · [docs/STRONG_COMPRESSION.md](docs/STRONG_COMPRESSION.md) · [docs/QUALITY.md](docs/QUALITY.md) · [VERSION_MANAGEMENT.md](VERSION_MANAGEMENT.md)

**Актуально для версии 0.6.2** (состояние кода на 23.10.2026). Версия у Mac и Windows общая; после выполнения задания поднимите её (`bump minor`).

## Что появилось по версиям

| Версия | Что нового | На Mac |
|---|---|---|
| 0.4.0 | Windows: окно WPF, FFmpeg, миниатюры, установщик | не нужно (только Windows) |
| 0.4.1 | Windows: разработчик и ссылка на GitHub в шапке | на Mac уже было (About, `ProjectLinks`) ✅ |
| 0.5.0 | Язык интерфейса English / Русский, по умолчанию английский | Mac: `Localizable.xcstrings`, `InterfaceLanguage`; коммиты `98139d6` и `6bcb8f2` сделаны на Mac, считаем собранным, **но проверьте по разделу 1** |
| 0.5.1–0.5.2 | Подсказки у переключателей видео; «Not smaller» вместо «Original kept» | сделано на Mac в `6bcb8f2` ✅ |
| 0.5.3 | Windows: уплотнённое окно (меньше отступов, кнопок и строк списка) | не нужно (другой UI) |
| 0.6.0–0.6.2 | Windows: компактный стартовый размер окна (около 700 × 560, зависит от монитора), окно само растёт при добавлении файлов и сжимается обратно; тонкие полосы прокрутки; блок настроек прокручивается, а не уменьшает шрифт; исправлены обрезанные иконки папок | не нужно, но по желанию раздел 2.10 (то же для окна Mac) |
| **0.6.0** | **Сильное сжатие (экспериментально): AV1 / HEVC / H.266, «Уложить в N МБ», шаблоны, звук Opus моно, чёрно-белое, шумоподавление, пропуск повторных кадров** | **не начато: главное задание, раздел 2** |

Колонку «На Mac» обновляйте по мере работы (✅ + версия), а новые функции Windows добавляйте отдельной строкой.

## 0. Как работать

- Сначала прочитайте `CLAUDE.md`, `BUILD.md`, `docs/STRONG_COMPRESSION.md` и `docs/QUALITY.md`. Windows-версия (`Windows/Vacpack.Core/EncodingCommand.cs`, `CompressionEngine.cs`, `Windows/Vacpack.Tests/Program.cs`) — **эталон поведения и чисел**; Windows-файлы не менять. Если эталон кажется ошибочным, на Mac сделайте правильно и опишите расхождение в итоговом отчёте.
- Код: Swift 6, только системные фреймворки; кодеры — внешние программы через `ProcessRunner`, **не линковать** (лицензии, см. `CLAUDE.md`). Стиль — как в соседнем коде; `swift format lint --strict` (строка до 120 символов) входит в `scripts/check.sh`.
- Команды из корня репозитория: `scripts/bootstrap.sh` (один раз), `scripts/check.sh` (lint, версии, тесты пакета, сборка приложения и тесты; `--ui` добавляет UI-тесты), `swift test --package-path Packages/CompressorKit --filter VideoCommandTests` для одного набора. `Vacpack.xcodeproj` не править: он генерируется `xcodegen generate` из `project.yml`.
- Версия меняется **только** `python3 scripts/update_version.py bump minor|patch` (скрипт правит README, CHANGELOG, `Version.swift`, `project.yml`); `check.sh` падает при расхождении.
- Строки интерфейса — по-английски в коде; перевод на русский добавлять в `App/Resources/Localizable.xcstrings` (все записи `manual`). SwiftUI-литералы переводятся сами, а значение типа `String` нужно оборачивать в `String(localized:)` или `LocalizedStringKey`.
- Правку Swift-файлов через Python/heredoc делайте осторожно: `\n` внутри строкового литерала дважды превращался в настоящий перенос и ломал сборку. В тексте с обратными слэшами используйте инструменты Edit/Write и перечитывайте результат.
- Делайте по одной функции за раз, коммитьте отдельно. Пуш только по моей просьбе, в **оба** remote: `git push origin main` (GitHub) и `git push forgejo main` (Forgejo). Если пуш отклонён, сначала `git fetch` и `git rebase origin/main`.
- После каждой функции: сборка без предупреждений, тесты, запись в `CHANGELOG.md` (раздел `[Unreleased]`, по-английски), правка `README.md`, обновление `CLAUDE.md` (новые типы и связи) и этого файла (колонка «На Mac»).

## 1. Сначала проверьте то, что уже сделано

| Что | Где | Что проверить |
|---|---|---|
| Язык интерфейса | `App/VacpackApp.swift` (`InterfaceLanguage`, меню Language), `App/Resources/Localizable.xcstrings`, `App/Resources/Info.plist` (`CFBundleLocalizations`) | по умолчанию интерфейс английский, даже на русской macOS; пункт Language в меню приложения переключает English / Русский, предлагает перезапуск, после него всё на русском; нет непереведённых строк: Quality, форматы, подсказки, статусы строк («Waiting», «Not smaller»…), About, меню Help; значения типа `String` (названия уровней качества, `kind.title`, `soundHint`, подписи статусов) идут через `String(localized:)` / `LocalizedStringKey` |
| Подсказки у переключателей видео и «Not smaller» (0.5.2) | `ContentView.swift`, `FileList.swift` | подсказки появляются при наведении и переведены; результат не меньше исходника помечен «Not smaller», оригинал не заменён и не отправлен в Корзину |
| `scripts/check.sh` целиком | весь проект | lint, тесты пакета, сборка и тесты приложения зелёные; `swift test` не оставляет мусора |

## 2. Сильное сжатие (экспериментально) — главное задание

**Цель.** Дать на Mac то же, что в Windows 0.6.0: блок **Strong compression (experimental)** для видео, когда нужен очень маленький файл (например, 1 ГБ → 10 МБ ценой разрешения, частоты кадров, цвета и качества звука). Все правила, числа и порядок фильтров — в `docs/STRONG_COMPRESSION.md`; ниже то, что нужно знать именно про Mac-код.

### 2.1. Что уже есть на Mac (не ломать)

- `Model/VideoSettings.swift`: `VideoSettings` (quality, format, resolution, removeAudio, preserveTransparency, audioProfile), **`VideoCodec` { h264, hevc }** и `VideoEncodingOptions` (codec, `maxFPS`, `hardwareAcceleration` для VideoToolbox, `threads`) — это общие настройки из «Advanced», **не** новый блок.
- `Engines/Video/VideoCommand.swift`: `VideoCommand.build(...)`, `videoCodecArguments(...)` (webm → VP9; иначе x264/x265, при желании VideoToolbox; `softwareCap`, метка `hvc1`), `VideoSizeMath`, `audioArguments`.
- `Engines/Video/VideoEngine.swift` (`encode`, прогресс по `out_time`), `Queue/CompressionPipeline.swift`, `Output/OutputWriter.swift`, `Tools/ToolLocator.swift`, CLI `Sources/vacpack/CompressCommand.swift`.

### 2.2. Модель (CompressorKit)

Добавьте **отдельные** настройки, чтобы не смешивать с `VideoEncodingOptions.codec` (там обычный выбор H.264/HEVC):

```swift
public enum StrongVideoCodec: String, Codable, Sendable, CaseIterable { case av1, hevc, vvc }

public struct StrongCompression: Codable, Hashable, Sendable {
    public var codec: StrongVideoCodec?        // nil — «Standard» (H.264 / VP9 по контейнеру, как сейчас)
    public var targetSizeMB: Double?           // nil — выключено; допустимо от 0.05 до 1 000 000
    public var audioKbps: Int?                 // nil — обычные правила; иначе Opus, 0…320
    public var monoAudio: Bool
    public var grayscale: Bool
    public var denoise: Bool
    public var dropDuplicateFrames: Bool
}
```

Положите её в `VideoSettings` (по умолчанию «всё выключено»: старое поведение и все существующие тесты не меняются). Валидацию делайте при построении команды (как `Validate()` в Windows): неверные значения → понятная ошибка.

### 2.3. Команда ffmpeg (`VideoCommand.build`)

Повторите Windows-`EncoderCommands.Build` для видео:

- **Фильтры** — порядок строго такой: `fps=N` (только вниз) → `scale=W:H:flags=lanczos` → `setsar=1` → `hqdn3d=3:2:6:4` (denoise) → `hue=s=0` (grayscale) → `mpdecimate` (dropDuplicateFrames); при `mpdecimate` добавить `-fps_mode vfr`.
- **Кодеки и контейнеры:** AV1 — `libsvtav1 -preset 6 -g 240 -pix_fmt yuv420p`, CRF по уровням качества `[26, 32, 38, 44, 50]`, контейнер `.mp4` (или `.webm`, если выбран WebM; `.mkv`, если исходник `.mkv`). HEVC — взять **существующие** `libx265` и таблицу `VideoQualityTable.x265`, метка `hvc1` для MP4/MOV, `.mp4` или `.mkv`. VVC — `libvvenc -preset medium -pix_fmt yuv420p10le` (только 10-бит!), QP `[26, 30, 34, 38, 42]`, **всегда `.mkv`**. HEVC и VVC в WebM не кладутся → ошибка; видео с прозрачностью — только стандартный кодек в WebM.
- **VideoToolbox не использовать** (ни `hardwareAcceleration`, ни `hevc_videotoolbox`) в сильном режиме и при заданном целевом размере: он не держит заданный битрейт.
- **Звук** (`AudioPlan`): если `audioKbps` задан — первая дорожка, `-map 0:a:0?`, `-c:a libopus -b:a Nk`, `-ac 1` при `monoAudio` или ≤ 32 кбит/с, `-application voip` при ≤ 24 кбит/с; если задан только размер — около 8 % бюджета, от 16 до 96 кбит/с (≤ 32 → моно); если только `monoAudio` — 64 кбит/с моно; иначе существующие правила.
- **Целевой размер:** при `targetSizeMB` вместо CRF — битрейт: бюджет `N × 1048576 × 8 × 0.95` бит делится на длительность; видео = `(бюджет − звук) × 0.92`; при < 20 кбит/с на видео — отказ с сообщением, сколько МБ нужно хотя бы. Аргументы: `-b:v Nk` (x264 и x265 ещё `-maxrate` = 1.25× и 1.2×, `-bufsize` = 2×; AV1 и VVC — только `-b:v`). Длительность неизвестна → отказ.

### 2.4. Цикл попыток (VideoEngine / CompressionPipeline)

Скопируйте логику `CompressionEngine.CompressAsync` из Windows: кодируем одним проходом, меряем размер; если больше цели — следующий битрейт `kbps × (цель / получилось)^1.25 × 0.94` и снова, **всего до 4 попыток**; не уложились — ошибка «Could not fit into N MB: got M MB. Lower the resolution or the frame rate.»; файл меньше цели — норма. Перед повтором удалять промежуточный файл (ffmpeg запускается с `-n`). Прогресс на повторе начинается заново. Отмена работает на любой попытке и не оставляет временных файлов. После цикла — обычные проверки (размеры, длительность) и правило «результат не меньше исходника не заменяет его».

### 2.5. Доступность кодеров на Mac

`brew install ffmpeg` содержит SVT-AV1 и x265, а **libvvenc обычно нет**. Один раз за запуск выполните `ffmpeg -hide_banner -encoders` и запомните наличие `libsvtav1`, `libx265`, `libvvenc`; в интерфейсе недоступные кодеки показывайте серыми с подсказкой «Not in this FFmpeg build» (а не скрывайте), в CLI — понятная ошибка. Это же нужно для пропуска интеграционных тестов.

### 2.6. Интерфейс (ContentView, строка видео)

В `VideoOptionsRow` добавьте `DisclosureGroup("Strong compression (experimental)")`, по умолчанию свёрнутый, показывать только когда формат вывода — видео (не звук и не GIF). Содержимое:

- **Preset** (Menu/Picker): Own settings, Strong, Maximum, Extreme. Шаблон лишь выставляет значения ниже (их можно менять после): длинная сторона `640 / 480 / 320` px (через `VideoResolution.maxLongEdge`), кадры `15 / 10 / 6` (`VideoEncodingOptions.maxFPS`), звук моно `32 / 16 / 8` кбит/с, качество `Medium / Acceptable / Acceptable`, denoise и dropDuplicateFrames включены. Для этого в списках «Resolution» и частоты кадров должны быть значения до 320 px и 6 кадров/с.
- **Video codec:** Standard (H.264 / VP9), AV1 (SVT-AV1), HEVC (H.265), H.266 / VVC · very slow.
- **Fit into [ N ] MB** — `Toggle` + `TextField` (принимает «10», «10.5», «10,5»; ошибка ввода — сообщение «Enter the target size in MB, for example 10.», запуск не начинать).
- **Sound:** As usual, Mono · 32 kbps, Mono · 16 kbps, Mono · 8 kbps.
- Переключатели **Black and white**, **Smooth noise**, **Drop repeated frames** (с подсказками `.help`).
- Строка-предупреждение: «Experimental: slower, and the picture loses detail. AV1, H.266 and Opus sound in MP4 may not open in older players.»

Русские переводы для `Localizable.xcstrings`: Strong compression (experimental) — «Сильное сжатие (экспериментально)»; Preset — «Шаблон»; Own settings — «Свои настройки»; Strong — «Сильное»; Maximum — «Максимальное»; Extreme — «Предельное»; Video codec — «Видеокодек»; Standard (H.264 / VP9) — «Стандартный (H.264 / VP9)»; H.266 / VVC · very slow — «H.266 / VVC · очень медленно»; Fit into — «Уложить в»; MB — «МБ»; Sound — «Звук»; As usual — «Как обычно»; Mono · 32 kbps — «Моно · 32 кбит/с» (так же 16 и 8); Black and white — «Чёрно-белое»; Smooth noise — «Убрать шум»; Drop repeated frames — «Пропускать повторы кадров»; Not in this FFmpeg build — «Нет в этой сборке FFmpeg»; тексты ошибок и подсказок — по смыслу из `Windows/Vacpack.Core/Loc.cs` (там готовые пары).

### 2.7. CLI

`vacpack video` (разбор аргументов в `Sources/vacpack/CompressCommand.swift`) получает те же возможности. Уже существуют `--codec h264|hevc` (обычный выбор, **не менять**), `--fps`, `--resolution`, `--max-long-edge`, `--remove-audio`, `--hw`/`--no-hw`, поэтому новые флаги назовите так: `--strong-codec av1|hevc|vvc`, `--target-size <МБ>`, `--audio-kbps <N>`, `--mono`, `--grayscale`, `--denoise`, `--drop-duplicates`. `--hw` вместе с ними — ошибка с понятным текстом. `--help` описывает новые флаги; `--json` выдаёт итоговый размер и число попыток.

### 2.8. Тесты (портировать из `Windows/Vacpack.Tests/Program.cs`)

Добавьте в `Packages/CompressorKit/Tests/CompressorKitTests/VideoCommandTests.swift` и `VideoPipelineTests.swift` (интеграционные — пропускать, если кодера нет в `ffmpeg -encoders`, как это делают соседние тесты):

- AV1 + все фильтры + `AudioKbps 16`: фильтры строго `fps=12,scale=640:360:flags=lanczos,setsar=1,hqdn3d=3:2:6:4,hue=s=0,mpdecimate`, `-fps_mode vfr`, `-c:v libsvtav1`, `-crf 38` (Good), `-c:a libopus`, `-b:a 16k`, `-ac 1`, `-map 0:a:0?`.
- HEVC: `libx265`, метка `hvc1` в MP4; VVC: `.mkv`, `libvvenc`, `yuv420p10le`, `-qp 34`; AV1 в WebM — `.webm`; HEVC и VVC в WebM — ошибка; прозрачность + новый кодек — ошибка.
- Целевой размер: 1 МБ на 100 с → звук 16 кбит/с моно, видео **58 кбит/с**, `-b:v 58k`, x264 `-maxrate 72k`; `nextBitrate(100 кбит/с, получилось 2× цели) == 39`; 0,05 МБ на 3600 с и нулевая длительность — отказ; без цели `targetVideoKbps == nil`; валидация (0,01 МБ, 400 кбит/с звука, NaN — ошибки).
- Интеграционные (короткий ролик 320×240, 2 с, два аудио): AV1 и HEVC укладываются в 0,3 МБ, длительность ±0,2 с, кодек в `ffprobe` `av1` / `hevc`; стандартный кодек с целью 0,08 МБ, длинная сторона 160, 10 кадров/с, моно Opus 16 кбит/с, ч/б, denoise, dedup → 160×120, ≤ 10,1 кадров/с, одна дорожка `opus`; VVC (если есть) → `.mkv`, кодек `vvc`.

### 2.9. Документы

`README.md` (раздел про Mac: что делает режим), `CHANGELOG.md` (`[Unreleased]`), `docs/QUALITY.md` (таблица CRF/QP для AV1 и VVC и правило подбора битрейта), `CLAUDE.md` (новые типы `StrongCompression`, `StrongVideoCodec` и где цикл попыток), этот файл (строка 0.6.0 → ✅), а в `docs/STRONG_COMPRESSION.md` раздел «Для macOS» замените описанием того, что сделано.

### 2.10. Компактное окно (по желанию, из 0.6.0–0.6.2)

В Windows пустое окно было слишком большим: зона «Drop files here» занимала половину экрана. Теперь оно открывается маленьким и растёт по мере надобности. На Mac проверьте и, если там то же, повторите идею (решение за вами; опишите его в отчёте):

- **Что сейчас на Mac:** `VacpackApp.swift` — `.defaultSize(width: 900, height: 600)`; `ContentView.swift` — `.frame(minWidth: 760, minHeight: 540)`; `DropZone.swift` — значок 104 pt, заголовок `.title`, три плашки видов файлов, отступы 28/18.
- **Что сделано в Windows (эталон):** стартовый размер = доля рабочей области экрана с границами (ширина 700–800, высота 560–640 единиц), минимальный 680 × 540; при добавлении первых файлов окно растёт до ширины 720–860 и высоты 600–800 (но не больше экрана, при необходимости сдвигается, чтобы не выйти за край); когда очередь снова пуста — возвращается к стартовому размеру, **только если пользователь не менял размер сам**; развёрнутое на весь экран окно не трогать. Зона перетаскивания компактнее (значок 48, заголовок 17).
- **Mac:** начните с `.defaultSize` около 720 × 520 и `minWidth` около 640, уменьшите `DropZone` (значок до 64 pt, меньше отступов, плашки видов в один ряд без лишней высоты). Рост окна при добавлении файлов — через `NSWindow.setContentSize` (с анимацией и в пределах `NSScreen.visibleFrame`), запускать из `onChange(of: model.items.isEmpty)`; возврат назад — только если размер окна всё ещё тот, что поставило приложение. Проверьте тёмную тему, полноэкранный режим, два монитора, и что панель настроек и новый блок «Strong compression» (раздел 2.6) помещаются в минимальную высоту (в `DisclosureGroup` можно прокручивать `ScrollView`).

## 3. Порядок и критерии готовности

1. Раздел 1 — проверить сделанное, исправить найденное.
2. Раздел 2 по шагам 2.2 → 2.3 → 2.4 → 2.8 (тесты) → 2.5 → 2.6 → 2.7 → 2.9 → 2.10 (по желанию); после каждого шага `swift test --package-path Packages/CompressorKit`.
3. Готово, когда: `scripts/check.sh --ui` зелёный; в сильном режиме на реальном ролике (около минуты, любой исходник) «Fit into 10 MB» даёт файл ≤ 10 МБ с нужным кодеком (проверить `ffprobe`) и исходник не тронут; без включённого блока поведение и вывод прежние; отмена посреди работы не оставляет временных файлов; русский и английский интерфейс без непереведённых строк.
4. В конце: `python3 scripts/update_version.py bump minor` (в `git diff` — только строки версии), `scripts/package.sh`, `scripts/install.sh`, краткий отчёт: что сделано, что не удалось проверить, что отличается от Windows и почему.
