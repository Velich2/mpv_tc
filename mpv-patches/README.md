# Патчи к mpv

Применяются к mpv `v0.41.0` (`git apply mpv-patches/*.patch`), собираются
workflow `.github/workflows/windows-build.yml` и `.github/workflows/macos-build.yml`.

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
