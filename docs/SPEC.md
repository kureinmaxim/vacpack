# SPEC — функции Compresto по публичным источникам

Функциональная спецификация macOS-приложения [Compresto](https://compresto.app/) (бывший CompressX), собранная только по официальным публичным страницам compresto.app и открытому репозиторию автора. Текст оригинала пересказан своими словами, названия элементов интерфейса оставлены как в приложении. У каждого пункта — ссылка на источник: `[S…]` ведёт на страницу из таблицы [Источники](#источники); для changelog в скобках указана версия.

- Дата сбора: 2026-10-18.
- Актуальная версия оригинала: **1.31.1** от 3 октября 2026 [S6].
- Пометка **(вывод)** — моя интерпретация, а не утверждение источника.

---

## 0. Ключевые факты

| Факт | Источник |
|---|---|
| Нативное macOS-приложение: пакетное сжатие видео, изображений, PDF и GIF, работает офлайн на Mac | [S1] |
| Требования: macOS 13+, Intel и Apple Silicon | [S1] |
| **Исходный код открыт под GPLv3**: репозиторий `dqhieu/ComprestoApp` | [S2], [S3] |
| В репозитории версия **1.27** (`MARKETING_VERSION = 1.27`, последний коммит 2026-04-17). Функций из 1.28–1.31 (EPUB, переводы, per-file, буфер обмена, Ollama и др.) в открытом коде нет | [S3], [S6] |
| Условия использования не запрещают реверс-инжиниринг; там только отказ от ответственности и запрет незаконного использования | [S4] |
| Цена: Personal $49 (1 Mac), Standard $69 (2 Mac), разовая покупка, пожизненные обновления; есть подписка и скидка для образования; распространяется и через Setapp | [S5], [S8] |
| Windows-версия в разработке (лист ожидания), лицензия Mac будет действовать и на Windows | [S38] |

**(вывод)** Для своего приложения есть два законных пути: (а) форк кода 1.27 под GPLv3 — производная обязана остаться GPLv3 с открытыми исходниками; (б) собственная реализация по этой спецификации. В обоих случаях нужны своё название, иконка и оформление: GPL не даёт прав на чужой товарный знак.

### Открытые компоненты оригинала

| Компонент | Назначение | Источник |
|---|---|---|
| FFmpeg | видео, GIF, MP3; на Apple Silicon ставится нативная arm64-сборка (с 1.30) | [S2], [S8], [S36] |
| gifski | качественные GIF | [S2], [S8] |
| pngquant | оптимизация PNG | [S2], [S8] |
| Ghostscript | PDF; **не поставляется** с приложением, пользователь ставит сам (AGPL) | [S9] |
| Sparkle | автообновления | [S2] |
| TelemetryDeck SwiftClient | анонимная аналитика (с 1.7 есть отказ) | [S2], [S6] (1.7) |
| SDWebImageWebPCoder | WebP | [S2] |
| KeyboardShortcuts, LaunchAtLogin-Modern, DockProgress, SettingsAccess, SwiftDate, SwiftDraw, Puppy (логирование) | UI и системные мелочи | [S2] |

FFmpeg, gifski и pngquant **скачиваются при первом запуске** в приватную папку приложения, а не лежат в бандле [S8].

---

## 1. Поддерживаемые типы файлов

| Тип | Вход | Выход | Источник |
|---|---|---|---|
| Видео | MP4, MOV, WebM, AVI, MKV, FLV, Transport Stream и др. | MP4, WebM, MOV, GIF, MP3 или «как вход» | [S10], [S13], [S6] (1.20, 1.21) |
| Изображения | JPG/JPEG, PNG, WebP, AVIF, HEIC/HEIF, DNG, TIFF, BMP, SVG (SVG → JPG или PNG) | JPG, PNG, WebP, AVIF или «как вход» | [S11] |
| GIF | анимированный GIF | GIF | [S12] |
| PDF | PDF | PDF (нужен Ghostscript) | [S14], [S9] |
| EPUB | EPUB 2/3 | EPUB | [S15], [S7] |

---

## 2. Видео

| Параметр | Значения | Источник |
|---|---|---|
| **Video quality** | Highest, High (по умолчанию), Good, Medium, Acceptable, **File size** (целевой размер в KB/MB/GB) | [S10] |
| **Video resolution** | Same as input (по умолчанию), 4K 3840×2160, Full HD 1920×1080, HD 1280×720, Max Width, Max Height, Max Long Edge, Max Short Edge (своё значение в px) | [S10], [S6] (1.25) |
| Только уменьшение | при Max-режимах видео не увеличивается; пропорции сохраняются | [S10] |
| **Video format** | Same as input, MP4, WebM, MOV, GIF, MP3 | [S10] |
| **Remove audio** | убрать звуковую дорожку | [S10] |
| **Preserve transparency** | для видео с альфа-каналом: в WebM всегда, в MOV — при наличии альфы; при этом доступны не все уровни качества | [S10] |
| Кодек | H.264 (рекомендуется) или H.265/HEVC — в Settings → Advanced | [S29] |
| Целевой FPS | Same as input, 60, 30, 24, 15; только понижает, никогда не повышает | [S30], [S6] (1.8) |
| Аппаратное ускорение | VideoToolbox; включено по умолчанию, отключается в Settings → Advanced | [S32] |
| Ограничение ядер CPU | 2, 4 или Max (по умолчанию) | [S28], [S6] (1.22) |
| Обрезка видео (trim) | есть с 1.4, работает и для нескольких видео | [S6] (1.4, 1.16) |
| Звук | сохраняется без потерь; несколько звуковых дорожек сохраняются | [S6] (1.9, 1.17.1) |
| Прочее | нечётная ширина/высота поддерживаются; оценка итогового размера до сжатия | [S6] (1.21, 1.4) |

> Расхождение в источниках: на вводной странице документации у кодека указаны «H.264, H.265, or VP9», а на странице кодека только H.264 и H.265 [S39], [S29]. **(вывод)** VP9, вероятно, используется только для WebM.

---

## 3. Изображения

| Параметр | Значения | Источник |
|---|---|---|
| **Image quality** | Highest, High, Good, Medium, Acceptable, **Target file size** | [S11] |
| Target file size | размер в KB/MB/GB (по умолчанию 200 KB); результат всегда JPG, выбор формата блокируется; качество снижается пошагово до попадания; если цель недостижима — сохраняется самый маленький вариант с пометкой «Couldn't reach target size» | [S11], [S6] (1.30) |
| Где доступен Target file size | главное окно, пресеты, per-file. Drop Zone, мониторинг папок и deep links — только уровни качества | [S11] |
| **Image size** | Same as input (по умолчанию), Percentage, Max width, Max height, Max long edge, Max short edge; пропорции сохраняются | [S11] |
| **Image format** | Same as input (по умолчанию), JPG, PNG, WebP, AVIF (с прозрачностью) | [S11], [S6] (1.21) |
| DPI | JPEG и PNG сохраняют исходное разрешение печати; WebP и прочие — нет; файлы без DPI не трогаются | [S11], [S7] |
| Прозрачность | при PNG → JPG прозрачность не превращается в чёрный фон; непрозрачные JPEG не белеют | [S6] (1.25, 1.30) |

---

## 4. GIF и видео → GIF

| Параметр | Значения | Источник |
|---|---|---|
| **GIF quality** | Highest, High (по умолчанию), Good, Medium, Acceptable | [S12] |
| **GIF dimension** | Same as input (по умолчанию), 75%, 50%, 25%, Percentage, Max width (без увеличения); пропорции сохраняются; своё значение подтверждается кнопкой **Update** | [S12], [S6] (1.30) |
| Видео → GIF | формат GIF в настройках видео; кнопка меняется на **Convert** | [S13] |
| FPS для GIF | ползунок 10–50 | [S13], [S10] |
| Прогресс | в реальном времени при конвертации в GIF | [S6] (1.5) |

---

## 5. PDF

| Параметр | Значения | Источник |
|---|---|---|
| **PDF quality** | Best (Prepress), High (Printer), Balance (eBook, по умолчанию), Low (Screen) | [S14] |
| Движок | Ghostscript, путь задаётся в Settings → **PDF Compression** | [S14], [S9] |
| Нет Ghostscript | предупреждение при выборе PDF; если есть Homebrew — кнопка **Install Ghostscript via Homebrew** (`brew install ghostscript`), а при запуске приложение ставит его в фоне автоматически | [S9], [S6] (1.25) |
| Типовые пути `gs` | `/opt/homebrew/bin/gs` (Apple Silicon), `/usr/local/bin/gs` (Intel), `/opt/local/bin/gs` (MacPorts) | [S9] |

**(вывод)** Названия уровней совпадают с пресетами Ghostscript `-dPDFSETTINGS=/prepress, /printer, /ebook, /screen`.

---

## 6. EPUB (с 1.31)

| Правило | Источник |
|---|---|
| Сжимаются только JPEG, PNG и WebP внутри книги; текст, CSS, шрифты, GIF, SVG и всё остальное не меняются | [S15], [S7] |
| **EPUB quality**: Best — исходный размер; High — длинная сторона до 2048 px; Balance (по умолчанию) — до 1536 px; Low — до 1024 px. Картинки только уменьшаются | [S15], [S7] |
| Каждая картинка сохраняет свой формат и имя файла, поэтому ссылки внутри книги не ломаются | [S15] |
| Картинка заменяется, только если сжатая версия меньше; книга заменяется, только если итоговый EPUB меньше исходного | [S15], [S7] |
| Книги с DRM (зашифрованные картинки) не меняются, пользователь видит объяснение; книги только с обфускацией шрифтов сжимаются | [S15], [S7] |
| Доступно: главное окно, Drop Zone, буфер обмена, пресеты, per-file, deep links (`epubQuality`). **Не** поддерживается в мониторинге папок | [S15] |
| Двойной клик по EPUB в Finder по-прежнему открывает читалку: приложение не регистрируется обработчиком EPUB по умолчанию | [S15], [S7] |

---

## 7. Извлечение MP3 из видео

| Параметр | Значение | Источник |
|---|---|---|
| Выбор | формат **MP3** в настройках видео | [S16] |
| Кодирование | `libmp3lame`, VBR V0 (~245 кбит/с), каналы как в исходнике | [S16] |
| Пакетный режим | по отдельному MP3 на каждое видео | [S16] |

---

## 8. Главное окно и очередь

| Функция | Источник |
|---|---|
| Выбор файлов кликом по панели или перетаскиванием файлов и папок; видео, изображения и GIF можно выбирать вместе | [S10], [S6] (1.6) |
| Вставка файлов и картинок из буфера (⌘V); добавление новых файлов прямо во время сжатия — встают в очередь | [S6] (1.9) |
| Включение подпапок рекурсивно; фильтр по типу файлов при добавлении папки (поповер) | [S6] (1.19, 1.25, 1.27) |
| Поведение при перетаскивании в окно: Replace или Append; Option временно переключает режим | [S6] (1.21) |
| Режим одного файла — превью; несколько файлов — сетка с наложенными размерами в пикселях; лимит превью (**Thumbnail preview limit**), выше которого включается дерево файлов | [S6] (1.19, 1.25, 1.17), [S19] |
| Результаты показываются по мере готовности каждого файла: размер до/после, экономия в байтах и процентах | [S6] (1.18, 1.19) |
| Удаление ожидающих файлов во время сжатия; кнопка корзины в превью одного файла | [S6] (1.20, 1.28) |
| **Pause after current file** — дождаться текущего файла и остановиться; **Resume (N files)** — продолжить с первого несжатого; **Cancel all** | [S17] |
| На время сжатия Mac не засыпает | [S26], [S6] (1.13) |
| Защита от роста: если результат больше исходника, оригинал не заменяется | [S6] (1.4), [S15] |
| Окно можно закрепить поверх остальных (есть горячая клавиша) | [S6] (1.17) |
| Горячие клавиши: ⌘, — настройки; ⌘Y — история; своя комбинация для вызова окна | [S6] (1.22, 1.15), [S23] |
| Оформление Liquid Glass (с 1.23) | [S6] (1.23) |

---

## 9. Пресеты (с 1.27)

| Правило | Источник |
|---|---|
| Строка **Preset** появляется в боковой панели после добавления файлов; группы **Built-in** и **My Presets**; при изменении любого параметра переключается на **Custom**; во время сжатия заблокирован | [S18] |
| Встроенные: **High Quality** (всё Highest или Best, формат и размер как вход), **Web Optimized** (изображения Good + WebP; видео Good + MP4 + Full HD; GIF Good + 50%; PDF и EPUB Balance), **Smallest File Size** (изображения Acceptable + WebP; видео Acceptable + MP4 без звука; GIF Acceptable + 50%; PDF и EPUB Low). Встроенные нельзя изменить или удалить | [S18] |
| Пресет хранит: изображение — качество, формат, размер; видео — качество, формат, разрешение, удаление звука; GIF — качество и размеры; PDF и EPUB — качество. **Не хранит**: папку вывода, формат имени, удаление исходника, FPS, целевой размер | [S18] |
| Управление в Settings → Presets: краткая сводка, **Edit** (переименование и все параметры), **Delete** с подтверждением | [S18] |

---

## 10. Настройки для отдельного файла (с 1.28)

| Правило | Источник |
|---|---|
| Иконка-ползунок на файле (при наведении; в превью одного файла видна всегда) открывает поповер только с параметрами этого типа; точка на иконке — признак переопределения | [S19] |
| Что можно переопределить: видео (формат, качество с целевым размером, разрешение, прозрачность, звук), видео → GIF (FPS, качество, размеры), изображение (качество с целевым размером, размер, формат), GIF, PDF, EPUB | [S19] |
| **Reset to global settings**; возврат значения к значению панели снимает это переопределение | [S19] |
| Переопределения живут до конца сессии: сбрасываются при загрузке новых файлов и очистке списка; недоступны в режиме дерева; смена пресета их не трогает; во время сжатия иконка скрыта | [S19] |

---

## 11. Drop Zone (зона у «чёлки»)

| Правило | Источник |
|---|---|
| Включается в Settings → Drop Zone (**Enable Drop Zone**); появляется только при перетаскивании файлов к «чёлке» или верху экрана и следует за курсором | [S20], [S6] (1.20, 1.17) |
| Типы: видео, изображения, GIF, PDF, EPUB, папки (рекурсивно, скрытые файлы пропускаются; зона появляется, только если в папке есть подходящие файлы) | [S20], [S6] (1.26) |
| Режимы: **Compress** (по умолчанию) и **Compress & Open in App** — зона делится на две половины | [S20], [S6] (1.26) |
| Какие настройки брать: **Last used settings** (по умолчанию), **Custom** (свои параметры для видео, изображений, GIF, PDF и EPUB), **Preset** (папка вывода и удаление исходника — из главного окна) | [S20] |
| Вывод: Same as input, Subfolder (по умолчанию «compressed»), Custom; опция **Remove input file** | [S20] |
| «Чёлка» показывает прогресс, уведомление о завершении, статус AI-переименования; после одного файла его можно переименовать (карандаш, Return — сохранить, Esc — отмена; нужен стиль **Expanded** в Settings → Appearance) | [S20], [S33], [S6] (1.19, 1.29) |
| К результату применяются Finder-теги | [S20], [S6] (1.29) |

---

## 12. Мониторинг папок

| Правило | Источник |
|---|---|
| Settings → Folder Monitoring → **Add folder**; у каждой папки свои настройки | [S21] |
| Типы: Image, Video, Video and image (по умолчанию). GIF, PDF, EPUB, скрытые файлы и `.crdownload` игнорируются | [S21] |
| **Wait for file to finish writing**: 0–60 с (по умолчанию 0) — ждать, пока размер файла перестанет меняться | [S21], [S6] (1.28) |
| Параметры видео и изображений — как в Drop Zone (без целевого размера) | [S21] |
| **Include subfolders**: None (по умолчанию), Custom (с **Max depth**), All | [S21], [S6] (1.23) |
| Вывод: Same as input, Subfolder («compressed»), Custom; **Remove input file**; свой формат имени для каждой папки | [S21], [S6] (1.15) |

---

## 13. Сжатие из буфера обмена (с 1.28)

| Правило | Источник |
|---|---|
| Включатель **Auto-compress clipboard contents** во вкладке Folder Monitoring, по умолчанию выключен | [S22] |
| Файлы из Finder сжимаются на месте; картинка из буфера сохраняется как PNG и сжимается; данные PDF, GIF и видео — через временный файл. Типы: видео, изображения, GIF, PDF, EPUB (PDF — только при наличии Ghostscript) | [S22] |
| Используются настройки Drop Zone; исходник не удаляется; целевой размер не применяется | [S22] |
| Результат кладётся обратно в буфер, приходит уведомление; быстрые копирования объединяются в одну партию, а во время работы встают в очередь | [S22] |
| Отдельная опция: копировать результаты в буфер после любого сжатия | [S6] (1.12) |

---

## 14. История сжатий

| Правило | Источник |
|---|---|
| Открывается по ⌘Y, через меню приложения или иконку в строке меню | [S23] |
| Общие итоги (число файлов, сэкономленный объём) и по каждому файлу: размер до/после и экономия; клик показывает файл в Finder | [S23], [S6] (1.7, 1.11) |
| Ленивая подгрузка от новых к старым; порция 50, 100 (по умолчанию), 200 или 500 | [S23], [S6] (1.29) |
| **Keep compression history** — отключение стирает историю; хранится только локально | [S23] |

---

## 15. Вывод файлов и метаданные

| Правило | Источник |
|---|---|
| Папка вывода: как у входа, подпапка или своя; несуществующая папка создаётся | [S20], [S6] (1.10, 1.20) |
| Формат имени: суффикс к исходному имени с токенами `{timestamp}`, `{datetime}` (`yyyy-MM-dd'T'HHmmss`), `{date}`, `{time}`, `{quality}`, `{resolution}` | [S21], [S34] |
| Совпадение имён — добавляется номер, а не метка времени; при **Remove input file** результат получает исходное имя | [S6] (1.5.3) |
| Исходник не удаляется, если сжатие не удалось | [S6] (1.5.3) |
| По умолчанию метаданные удаляются. Опции в Settings → Advanced: **Retain image metadata (EXIF, IPTC)** с XMP — копируется без повторного кодирования (JPEG, PNG, TIFF; в блоге ещё PSD; не работает с целевым размером); **Preserve color profile (ICC)**; **Retain creation date** (и у пересоздаваемых папок); **Retain modification date** | [S31], [S7], [S6] (1.24, 1.28) |
| Всегда сохраняются: DPI у JPEG и PNG, Finder-теги исходника | [S31] |
| **Apply Finder tags to compressed files** (Settings → File Management): добавить свои теги ко всем результатам (главное окно, Drop Zone, мониторинг) | [S31] |

---

## 16. Прочие настройки и поведение

| Настройка | Источник |
|---|---|
| Язык: System, English, Deutsch, Español, Français, Português (Brasil), 简体中文; выбор в Settings → General или на экране приветствия; нужен перезапуск (**Restart** или **Later**) | [S24], [S7] |
| Уведомления: о количестве и месте сохранения; клик открывает Finder; опция **Only show notification when switched to other apps** (уведомления об ошибках показываются всегда) | [S25], [S6] (1.28) |
| **Sleep when finish**: усыпить Mac после завершения, с 10-секундным отсчётом (**Sleep Now** или **Cancel**) | [S26], [S6] (1.25) |
| Конфетти через `raycast://confetti`; опция сама отключается, если Raycast нет | [S27] |
| Иконка в строке меню (можно скрыть), иконка в Dock (можно скрыть), скрытие при запуске, альтернативные иконки приложения | [S6] (1.14–1.16, 1.8, 1.22.2) |
| **Open With** в Finder: файлы сжимаются в фоне с последними настройками; приложение не регистрируется обработчиком по умолчанию для видео, PNG и JPEG | [S6] (1.30, 1.30.1) |
| Просмотр логов, встроенная доска обратной связи, отказ от анонимной аналитики | [S6] (1.22, 1.7) |
| После закрытия последнего окна приложение остаётся в строке меню и освобождает декодированные превью | [S6] (1.30) |

---

## 17. AI-переименование

| Правило | Источник |
|---|---|
| Только для изображений; имя по содержимому картинки; расширение сохраняется | [S33] |
| Провайдеры: **OpenAI** (ключ API в Keychain, кнопка **Verify**, выбор модели, таблица **Compare model pricing**) или **Ollama (Local)** (по умолчанию `http://localhost:11434`, **Test**, автоматический список установленных vision-моделей) | [S33], [S6] (1.25, 1.29) |
| Картинка уменьшается до 512 px перед отправкой | [S33] |
| Стили имени: Descriptive, SEO Friendly, Short, Technical, Custom (свой промпт); **Max filename length** 20–200 символов | [S33] |
| Работает в пакетном режиме, по одному запросу на картинку | [S33] |

---

## 18. Интеграции

### Deep links

| Правило | Источник |
|---|---|
| Схема: `compresto://open?path=<путь1>\|<путь2>&<параметры>` — сжать; `compresto://import?path=...` — загрузить в окно без сжатия; пути разделяются `\|`, допускаются папки | [S34], [S6] (1.17) |
| Из терминала: `open "compresto://open?path=..."` | [S34] |
| Параметры: `quality` (highest…acceptable), `pdfQuality` и `epubQuality` (best/high/balance/low; при отсутствии `epubQuality` берётся `quality`), `videoFormat` (same/mp4/webm/mov/gif/mp3), `imageFormat` (same/webp/jpg/png/avif), `format` (запасной вариант для обоих), `removeAudio`, `fileNameFormat`, `outputFileName` (имя без расширения, приоритетнее `fileNameFormat`; для нескольких файлов — `name`, `name 1`, `name 2`), `outputFolder`/`outputPath`/`outputDirectory`, `removeInputFile`, `subfolderProcessing` (all/none/число — глубина) | [S34], [S6] (1.28.1) |
| Неуказанные параметры берутся из настроек приложения (с 1.29) | [S34], [S6] (1.29) |
| При сжатии через deep link главное окно остаётся скрытым, прогресс показывается в «чёлке» | [S6] (1.19, 1.16) |

### Raycast

Расширение с командами **Compress Files** и **Import Files**; требует установленного приложения [S35].

---

## 19. Первый запуск, лицензия, обновления

| Правило | Источник |
|---|---|
| Мастер: Welcome (выбор языка) → Installation (скачивание FFmpeg, gifski, pngquant с прогрессом и кнопкой **Try Again**) → License Activation (ключ вида `XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX`; для Setapp — **Continue**) → Done | [S8] |
| Сброс настроек: Option + меню Compresto → **Reset Preferences** | [S8] |
| Лицензия сохраняет состояние при сбоях сетевой проверки | [S6] (1.25) |
| Обновления через Sparkle и карточка о новой версии в приложении | [S2], [S6] (1.3) |

---

## 20. Вне рамок проекта

| Продукт | Суть | Источник |
|---|---|---|
| Compresto Image Compression API | REST `POST https://api.compresto.app/v1/compress` (PNG/JPEG/WebP, ключ в заголовке `X-API-Key`), `/v1/usage`; бесплатно 500 сжатий в месяц | [S37], [S39] |
| Веб-инструменты | PDF в картинки, удаление EXIF, просмотр метаданных и др. | [S1] |
| Windows-версия | в разработке | [S38] |

---

## 21. Чего нет в публичных источниках

Эти детали придётся взять из открытого кода 1.27 [S3] или измерить на оригинале (шаг 3 плана — `docs/REFERENCE.md`):

- соответствие уровней качества параметрам кодеров (CRF/битрейт FFmpeg, quality и speed pngquant, качество JPEG, WebP и AVIF, параметры gifski);
- алгоритм подбора качества под целевой размер (шаг, число попыток) для видео и изображений;
- точные флаги Ghostscript помимо пресета (DPI картинок, понижение разрешения);
- чем кодируются JPEG, WebP и AVIF (ImageIO, libwebp, libavif или FFmpeg);
- правила для HEIC, DNG, TIFF и BMP на выходе при «Same as input»;
- обработка нестандартных EPUB (несколько OPF, ссылки на картинки из CSS, порядок записи `mimetype` в ZIP);
- макет и визуальный дизайн окон (их всё равно нужно делать своими).

**Противоречия в источниках:**
- видеокодеки: «H.264, H.265, or VP9» на вводной странице документации [S39] против только H.264/H.265 на странице кодеков [S29];
- метаданные: JPEG, PNG, TIFF в документации [S31] против ещё и PSD в блоге [S7];
- pricing до сих пор перечисляет «video, image, GIF & PDF» без EPUB [S5].

---

## Источники

| ID | Страница |
|---|---|
| S1 | [compresto.app — главная](https://compresto.app/) |
| S2 | [Acknowledgments](https://compresto.app/acknowledgments) |
| S3 | [github.com/dqhieu/ComprestoApp (GPL-3.0)](https://github.com/dqhieu/ComprestoApp) |
| S4 | [Terms of Service](https://compresto.app/terms-of-service) |
| S5 | [Pricing](https://compresto.app/pricing) |
| S6 | [Changelog](https://compresto.app/changelog) |
| S7 | [Блог: Compresto v1.31](https://compresto.app/blog/compresto-1-31) |
| S8 | [Docs: Setting up](https://compresto.app/docs/guides/getting-started/setting-up) |
| S9 | [Docs: Install Ghostscript](https://compresto.app/docs/guides/getting-started/install-ghostscript) |
| S10 | [Docs: How to compress video](https://compresto.app/docs/guides/file-compression/how-to-compress-video) |
| S11 | [Docs: How to compress image](https://compresto.app/docs/guides/file-compression/how-to-compress-image) |
| S12 | [Docs: How to compress GIF](https://compresto.app/docs/guides/file-compression/how-to-compress-gif) |
| S13 | [Docs: How to convert video to GIF](https://compresto.app/docs/guides/file-compression/how-to-convert-video-to-gif) |
| S14 | [Docs: How to compress PDF](https://compresto.app/docs/guides/file-compression/how-to-compress-pdf) |
| S15 | [Docs: How to compress EPUB](https://compresto.app/docs/guides/file-compression/how-to-compress-epub) |
| S16 | [Docs: How to extract MP3 from video](https://compresto.app/docs/guides/file-compression/how-to-extract-mp3-from-video) |
| S17 | [Docs: Pause and resume](https://compresto.app/docs/guides/file-compression/pause-and-resume) |
| S18 | [Docs: Compression presets](https://compresto.app/docs/customization/presets) |
| S19 | [Docs: Per-file settings](https://compresto.app/docs/customization/per-file-settings) |
| S20 | [Docs: Drop Zone](https://compresto.app/docs/customization/drop-zone) |
| S21 | [Docs: Folder monitoring](https://compresto.app/docs/customization/folder-monitoring) |
| S22 | [Docs: Clipboard compression](https://compresto.app/docs/customization/clipboard-compression) |
| S23 | [Docs: Compression history](https://compresto.app/docs/customization/compression-history) |
| S24 | [Docs: App language](https://compresto.app/docs/customization/language) |
| S25 | [Docs: Notifications](https://compresto.app/docs/customization/notifications) |
| S26 | [Docs: Sleep after compression](https://compresto.app/docs/customization/sleep-after-compression) |
| S27 | [Docs: Confetti](https://compresto.app/docs/customization/conffeti) |
| S28 | [Docs: CPU cores limit](https://compresto.app/docs/customization/cpu-cores-limit) |
| S29 | [Docs: Video codec](https://compresto.app/docs/customization/video-codec) |
| S30 | [Docs: Video FPS](https://compresto.app/docs/customization/video-fps) |
| S31 | [Docs: File metadata](https://compresto.app/docs/customization/file-metadata) |
| S32 | [Docs: Hardware acceleration](https://compresto.app/docs/customization/hardware-acceleration) |
| S33 | [Docs: AI renaming](https://compresto.app/docs/customization/ai-renaming) |
| S34 | [Docs: Deep linking](https://compresto.app/docs/integrations/deep-linking) |
| S35 | [Docs: Raycast extension](https://compresto.app/docs/integrations/raycast-extension) |
| S36 | [Docs: «bad CPU type in executable»](https://compresto.app/docs/troubleshooting/bad-cpu-type-in-executable) |
| S37 | [API Service](https://compresto.app/api) |
| S38 | [Windows (waitlist)](https://compresto.app/windows) |
| S39 | [Docs: Introduction и индекс llms.txt](https://compresto.app/docs/llms.txt) |

[S1]: https://compresto.app/
[S2]: https://compresto.app/acknowledgments
[S3]: https://github.com/dqhieu/ComprestoApp
[S4]: https://compresto.app/terms-of-service
[S5]: https://compresto.app/pricing
[S6]: https://compresto.app/changelog
[S7]: https://compresto.app/blog/compresto-1-31
[S8]: https://compresto.app/docs/guides/getting-started/setting-up
[S9]: https://compresto.app/docs/guides/getting-started/install-ghostscript
[S10]: https://compresto.app/docs/guides/file-compression/how-to-compress-video
[S11]: https://compresto.app/docs/guides/file-compression/how-to-compress-image
[S12]: https://compresto.app/docs/guides/file-compression/how-to-compress-gif
[S13]: https://compresto.app/docs/guides/file-compression/how-to-convert-video-to-gif
[S14]: https://compresto.app/docs/guides/file-compression/how-to-compress-pdf
[S15]: https://compresto.app/docs/guides/file-compression/how-to-compress-epub
[S16]: https://compresto.app/docs/guides/file-compression/how-to-extract-mp3-from-video
[S17]: https://compresto.app/docs/guides/file-compression/pause-and-resume
[S18]: https://compresto.app/docs/customization/presets
[S19]: https://compresto.app/docs/customization/per-file-settings
[S20]: https://compresto.app/docs/customization/drop-zone
[S21]: https://compresto.app/docs/customization/folder-monitoring
[S22]: https://compresto.app/docs/customization/clipboard-compression
[S23]: https://compresto.app/docs/customization/compression-history
[S24]: https://compresto.app/docs/customization/language
[S25]: https://compresto.app/docs/customization/notifications
[S26]: https://compresto.app/docs/customization/sleep-after-compression
[S27]: https://compresto.app/docs/customization/conffeti
[S28]: https://compresto.app/docs/customization/cpu-cores-limit
[S29]: https://compresto.app/docs/customization/video-codec
[S30]: https://compresto.app/docs/customization/video-fps
[S31]: https://compresto.app/docs/customization/file-metadata
[S32]: https://compresto.app/docs/customization/hardware-acceleration
[S33]: https://compresto.app/docs/customization/ai-renaming
[S34]: https://compresto.app/docs/integrations/deep-linking
[S35]: https://compresto.app/docs/integrations/raycast-extension
[S36]: https://compresto.app/docs/troubleshooting/bad-cpu-type-in-executable
[S37]: https://compresto.app/api
[S38]: https://compresto.app/windows
[S39]: https://compresto.app/docs/llms.txt
