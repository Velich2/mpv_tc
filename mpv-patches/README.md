# Патчи к mpv

Применяются к mpv `v0.41.0` (`git apply mpv-patches/*.patch`), собираются
workflow `.github/workflows/windows-build.yml`.

- `0001-vo-add-DeckLink-mirror-output.patch` — вывод на карты Blackmagic
  DeckLink/UltraStudio (`--decklink-mirror`).
- `0002-decklink-runtime-and-menu.patch` — включение на лету, свойство
  `decklink-devices`, пункт «DeckLink output» в меню и запоминание выбора.
- `0003-decklink-audio-sync.patch` — `--decklink-audio-sync` и свойство
  `decklink-latency`: звук задерживается на задержку карты; переключатель в меню.
- `0004-decklink-respect-explicit-options.patch` — выбор из меню не перебивает опции,
  явно заданные в командной строке или `mpv.conf`.
