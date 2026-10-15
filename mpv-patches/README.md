# Патчи к mpv

Применяются к mpv `v0.41.0` (`git apply mpv-patches/*.patch`), собираются
workflow `.github/workflows/build.yml`.

- `0001-vo-add-DeckLink-mirror-output.patch` — вывод на карты Blackmagic
  DeckLink/UltraStudio (`--decklink-mirror`).
- `0002-decklink-runtime-and-menu.patch` — включение на лету, свойство
  `decklink-devices`, пункт «DeckLink output» в меню и запоминание выбора.
- `0003-decklink-audio-sync.patch` — `--decklink-audio-sync` и свойство
  `decklink-latency`: звук задерживается на задержку карты; переключатель в меню.
- `0004-decklink-respect-explicit-options.patch` — выбор из меню не перебивает опции,
  явно заданные в командной строке или `mpv.conf`.
- `0005-decklink-macos-backend.patch` — вывод на DeckLink в macOS (C++ API Desktop Video,
  заголовки SDK 12.0 для macOS).
- `0006-select-timecode-overlay-menu-entry.patch` — пункт «Timecode overlay: on/off» в меню,
  если загружен скрипт `smpte_timecode.lua`.
- `0007-select-lut-menu-entry.patch` — пункт «LUT» в меню (если загружен `luts.lua`),
  подменю скрипта открываются поверх меню.
- `0008-osc-smpte-timecode.patch` — встроенный OSC показывает SMPTE-таймкод (то же, что
  `osc/osc.lua`), копировать `osc.lua` и ставить `osc=no` не нужно.
- `0009-decklink-fixes-from-review.patch` — исправления по ревизии кода: буфер кадров растёт по
  частоте кадров и задержке (не было пропусков при `decklink-delay` и 50/60p), время показа для
  `--video-sync=display-*`, устойчивый выбор режима для файлов без частоты кадров, учёт обрезки
  (`--video-crop`), допустимый диапазон SDI-кодов, закрытие вывода до VO, смена
  `decklink-delay` без перезапуска, синхронизация звука на старте без двойного учёта задержки.
- `0010-select-decklink-menu-fixes.patch` — меню DeckLink сохраняет только выбранное в меню,
  выделяет текущую карту по номеру или части имени, показывает, работает ли вывод.
- `0011-decklink-fixes-from-second-review.patch` — исправления по второй ревизии: при закрытии
  VO освобождаются кадры direct rendering (не было падения на выходе), буфер кадров считает
  частоту контента и при заданном `--decklink-mode` и уменьшается после снижения
  `decklink-delay`, частота файлов без fps определяется по таймкодам кадров (не зависит от
  `--speed`, различает 23.976 и 24), неровное время показа кадров сглаживается, а до перемотки кадры
  идут строго по порядку (нет повтора/пропуска кадров на нагруженной машине), кадры для опоздавших слотов не выбрасываются раньше времени, опоздавший слот
  повторяет кадр вместо чёрного, звук с
  `--decklink-audio-sync` стартует после запуска вывода (до 2 с ожидания), при перезапуске
  вывода задержка меняется один раз, сборка Windows зависит от всех IDL-файлов SDK.
