# MyCompressor

Рабочее название. macOS-приложение для сжатия видео, изображений, GIF, PDF и EPUB — собственная реализация по [docs/SPEC.md](docs/SPEC.md). Устройство — [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), этапы — [docs/PLAN.md](docs/PLAN.md).

## Требования

- macOS 14+, Xcode 26 (после установки или обновления Xcode один раз: `sudo xcodebuild -runFirstLaunch`)
- `brew install xcodegen ffmpeg pngquant gifski webp libavif ghostscript`

## Сборка и проверка

```bash
scripts/bootstrap.sh   # проверить зависимости, сгенерировать проект и тестовые файлы
scripts/check.sh       # swift-format, тесты CompressorKit, сборка и тесты приложения
open MyCompressor.xcodeproj
```

Утилита для движков без интерфейса:

```bash
swift run --package-path Packages/CompressorKit mycompressor-cli tools
swift run --package-path Packages/CompressorKit mycompressor-cli image photos/ --format webp --max-long-edge 2000
swift run --package-path Packages/CompressorKit mycompressor-cli video clip.mov --format mp4 --resolution 1080p
swift run --package-path Packages/CompressorKit mycompressor-cli video clip.mov --format gif --gif-fps 15 --gif-max-width 480
swift run --package-path Packages/CompressorKit mycompressor-cli gif animation.gif --quality good --percent 50
```

`MyCompressor.xcodeproj` генерируется из `project.yml` и в git не хранится.
