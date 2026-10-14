# mpv_tc

[English](#english) · [Русский](#русский)

## English

SMPTE timecode for [mpv](https://mpv.io) and an mpv 0.41.0 build for Windows and macOS that
mirrors the video to **Blackmagic DeckLink / UltraStudio** cards.

**Download** ([release notes](https://github.com/Velich2/mpv_tc/releases/tag/MPV_TC)):

- Windows: [mpv-tc-win64.zip](https://github.com/Velich2/mpv_tc/releases/download/MPV_TC/mpv-tc-win64.zip)
- macOS, Apple Silicon: [mpv-tc-macos-arm64.zip](https://github.com/Velich2/mpv_tc/releases/download/MPV_TC/mpv-tc-macos-arm64.zip)

### Features

- **Timecode overlay** (`scripts/smpte_timecode.lua`, works with any mpv): `HH:MM:SS:FF`,
  drop-frame `HH:MM:SS;FF` for 29.97/59.94. The start timecode is read from the file
  (MXF metadata, the `tmcd` track of MOV/MP4 via ffprobe) or set manually.
- **Timecode in the on-screen controller** (`osc/osc.lua`, mpv 0.40–0.41): replaces the
  current time next to the seek bar; click it to cycle timecode → time → time with ms.
- **DeckLink output** (patched mpv, Windows and macOS): the mpv window works as usual (OSC, timecode),
  while the card gets a clean picture without OSD and subtitles. Enabled from the mpv menu,
  remembered across restarts. The output mode follows the video's frame rate and size
  (e.g. 25p → 1080p25); other sizes are letterboxed.
- **Audio sync**: optionally delays the computer's audio by the card latency, so that it
  matches the picture on the DeckLink output.
- **LUTs** (`scripts/luts.lua`): pick a LUT from the mpv menu (Sony S-Log3/S-Log2, ARRI
  LogC3/LogC4, Blackmagic Gen 5 / DaVinci Intermediate to Rec.709 BT.1886 included, or your
  own); applied to the window and the DeckLink output.

### Install (Windows build)

1. Unzip the archive anywhere and run `mpv.exe` from there. Settings and scripts are read
   from `%APPDATA%\mpv\` as usual.
2. Copy `mpv_tc\scripts\smpte_timecode.lua` to `%APPDATA%\mpv\scripts\`. MOV/MP4 timecode
   needs `ffprobe` in `PATH` (or set `ffprobe_path`).
3. Optional, timecode in the OSC:
   - copy `mpv_tc\osc\osc.lua` to `%APPDATA%\mpv\scripts\osc.lua`;
   - add `osc=no` to `%APPDATA%\mpv\mpv.conf`;
   - to hide the overlay over the video, press `Ctrl+T` or pick **Timecode overlay** in the
     menu; the choice is remembered.
4. Optional, LUTs: copy `mpv_tc\scripts\luts.lua` to `%APPDATA%\mpv\scripts\` and the
   `mpv_tc\luts` folder to `%APPDATA%\mpv\luts`.

### Install (macOS build)

1. Unzip the archive and move `mpv.app` to `Applications`. The app is not notarized, so
   before the first start run in Terminal:
   `xattr -dr com.apple.quarantine /Applications/mpv.app`
2. Settings and scripts are read from `~/.config/mpv/`. Copy
   `mpv_tc/scripts/smpte_timecode.lua` to `~/.config/mpv/scripts/`; for MOV/MP4 timecode
   install `ffprobe` (`brew install ffmpeg`) or set `ffprobe_path`.
3. Optional, timecode in the OSC: copy `mpv_tc/osc/osc.lua` to `~/.config/mpv/scripts/osc.lua`
   and add `osc=no` to `~/.config/mpv/mpv.conf`; hide the overlay with `Ctrl+T` or
   **Timecode overlay** in the menu.
4. Optional, LUTs: copy `mpv_tc/scripts/luts.lua` to `~/.config/mpv/scripts/` and the
   `mpv_tc/luts` folder to `~/.config/mpv/luts`.

The script alone works with any mpv on any OS: copy it to `~/.config/mpv/scripts/`.

### DeckLink output

Requires **Blackmagic Desktop Video 12.0 or newer**.

1. Open the menu: ☰ button in the OSC, `Ctrl+P`, or `g` then `m`.
2. **DeckLink output** → pick a card (or **Auto** for the first card with an output).
   **Off** disables it.
3. **Sync audio to DeckLink: on** delays the audio to match the card; fine-tune the rest
   (e.g. the monitor's own latency) with `audio-delay`.

| Option | Description |
|---|---|
| `--decklink-mirror=<device>` | `auto`, an index, or (part of) the card name; empty disables. Overrides the menu choice |
| `--decklink-mode=<mode>` | `auto`, or e.g. `1080p25`, `1080i50`, `2160p25`, or a DeckLink code like `Hp25` (list with `mpv.com -v`) |
| `--decklink-delay=<s>` | Extra output delay if frames repeat or skip on the card |
| `--decklink-audio-sync=yes` | Delay the audio by the output latency (`decklink-latency` property) |

Notes: the card shows each frame about 3 card frames after the window; only video goes to
the card (8-bit 4:2:2), audio stays on the computer; with `--hwdec`, frames are copied back
from the GPU (use `--hwdec=auto-copy` if needed). On macOS, run
`/Applications/mpv.app/Contents/MacOS/mpv -v` from Terminal to see the modes and log.

### Timecode controls

| Action | How |
|---|---|
| Toggle the overlay | `Ctrl+T` (`script-binding smpte_timecode/toggle`) or menu → **Timecode overlay** (patched mpv); remembered across restarts (`remember=no` disables) |
| Set the start timecode | `script-message-to smpte_timecode set-start 01:00:00:00` |
| Use it elsewhere | property `user-data/smpte_timecode`, e.g. `--term-status-msg='TC ${user-data/smpte_timecode}'` |

Font, size, position, colors and the other options are listed with comments in
`script-opts/smpte_timecode.conf`; copy it to `%APPDATA%\mpv\script-opts\`
(`~/.config/mpv/script-opts/` on Linux/macOS) and edit the copy.

### LUTs

`scripts/luts.lua` applies a LUT to the video, chosen from the mpv menu (**LUT** → folder →
LUT; **Off** turns it off). The choice is remembered across restarts. The LUT is applied as a
video filter, so the DeckLink output and screenshots get it too.

LUTs are read from the `luts` folder in the mpv config folder (`%APPDATA%\mpv\luts\`,
`~/.config/mpv/luts/`); every subfolder is a submenu. Supported: `.cube` (3D and 1D), `.3dl`,
`.dat`, `.m3d`, `.csp`. LUT input is the camera RGB with video levels mapped to 0–1, as in
DaVinci Resolve, so manufacturers' LUTs made for Resolve work as is; the output is treated as
Rec.709 / BT.1886.

Included (`luts/`), all to Rec.709 BT.1886:

| Folder | LUTs |
|---|---|
| Sony | S-Log3 S-Gamut3.Cine, S-Log3 S-Gamut3, S-Log3 Venice S-Gamut3.Cine, S-Log3 Venice S-Gamut3, S-Log2 S-Gamut |
| ARRI | LogC3 AWG3 (EI 800), LogC4 AWG4 |
| Blackmagic | Film Gen 5, DaVinci Intermediate / DaVinci Wide Gamut |

These are technical conversions generated by `tools/make_luts.py` from the published log
curves and gamuts (colour-science) with a neutral filmic tone curve (18% grey → 40%,
highlights roll off about 6.5 stops above grey). They are not the manufacturers' LUTs; for
the official looks, download the Sony / ARRI / Blackmagic LUTs and put them in a folder next
to these.

### Building

`mpv-patches/` holds the patches against mpv `v0.41.0`. The **Windows build** GitHub Actions
workflow applies them, builds with MSYS2 and uploads `mpv.exe` with its DLLs; a manual run
with `release_tag` publishes the build and `RELEASE_NOTES.md` to that release. The
**macOS build** workflow builds `mpv.app` with Homebrew libraries (Apple Silicon only); a
manual run with `release_tag` attaches the zip to that release.

### License

GPL-2.0-or-later, see [LICENSE](LICENSE). `osc/osc.lua` and the patches are derived from
mpv (LGPL-2.1-or-later / GPL-2.0-or-later). The DeckLink SDK interface files included in
`mpv-patches/0001-*.patch` and `0005-*.patch` are © Blackmagic Design under the license in
their headers. The builds bundle mpv, FFmpeg and other libraries under their own licenses; their
sources are available from the respective projects, MSYS2 and Homebrew.

## Русский

SMPTE-таймкод для [mpv](https://mpv.io) — Lua-скрипт и панель управления, а также сборка
mpv 0.41.0 для Windows и macOS с выводом на карты Blackmagic DeckLink / UltraStudio.

Скачать ([описание релиза](https://github.com/Velich2/mpv_tc/releases/tag/MPV_TC)):
[Windows](https://github.com/Velich2/mpv_tc/releases/download/MPV_TC/mpv-tc-win64.zip) ·
[macOS Apple Silicon](https://github.com/Velich2/mpv_tc/releases/download/MPV_TC/mpv-tc-macos-arm64.zip).

### Что умеет

- Показывает таймкод `HH:MM:SS:FF` поверх видео; drop-frame — `HH:MM:SS;FF` (29.97, 59.94).
- Стартовый таймкод берёт из файла:
  1. сообщение `set-start` (задаётся во время просмотра);
  2. опция `start_tc`;
  3. метаданные контейнера, которые отдаёт mpv (MXF);
  4. `ffprobe` — теги потоков/контейнера (трек `tmcd` в MOV/MP4);
  5. иначе `00:00:00:00`.
- Публикует текущий таймкод в свойство `user-data/smpte_timecode`.

### Установка

```sh
cp scripts/smpte_timecode.lua     ~/.config/mpv/scripts/
cp script-opts/smpte_timecode.conf ~/.config/mpv/script-opts/   # необязательно
```

Windows: `%APPDATA%\mpv\scripts\` и `%APPDATA%\mpv\script-opts\`.

Для MOV/MP4 нужен `ffprobe` в `PATH` (или путь в `ffprobe_path`).

### Управление

| Действие | Как |
|---|---|
| Вкл/выкл | `Ctrl+T` (опция `key_toggle`), в `input.conf`: `KEY script-binding smpte_timecode/toggle`, или меню mpv → **Timecode overlay** (в сборках этого репозитория). Состояние запоминается в `smpte_timecode.state` в папке настроек |
| Задать старт | `script-message-to smpte_timecode set-start 01:00:00:00` |
| Сбросить старт из `set-start` | `script-message-to smpte_timecode set-start` |

Таймкод в своих строках OSD/терминала:

```sh
mpv --term-status-msg='TC ${user-data/smpte_timecode}' file.mov
```

### Таймкод в панели управления (OSC)

`osc/osc.lua` — стандартный OSC из mpv 0.41.0, у которого вместо текущего времени слева от
полосы перемотки показывается SMPTE-таймкод. Рассчитан на mpv 0.40–0.41 (`mpv --version`).

1. Скопировать `osc/osc.lua` в папку `scripts` рядом с `smpte_timecode.lua`
   (Windows: `%APPDATA%\mpv\scripts\osc.lua`). Имя файла должно остаться `osc.lua`.
2. В `mpv.conf` (Windows: `%APPDATA%\mpv\mpv.conf`) отключить встроенный OSC:
   ```
   osc=no
   ```
3. Чтобы таймкод не дублировался поверх видео, выключите его `Ctrl+T` или пунктом
   **Timecode overlay** в меню mpv — выбор запоминается.

Клик по таймкоду в OSC переключает: таймкод → время → время с миллисекундами → таймкод.
Показ по умолчанию отключается в `script-opts/osc.conf`: `smpte_timecode=no`.

Для другой версии mpv: взять `player/lua/osc.lua` этой версии и наложить `osc/osc-smpte.patch`.

### Опции

Файл `script-opts/smpte_timecode.conf` или `--script-opts=smpte_timecode-<опция>=<значение>`.

| Опция | По умолчанию | Описание |
|---|---|---|
| `enabled` | `yes` | Показывать при первом запуске |
| `remember` | `yes` | Запоминать последнее состояние (`Ctrl+T`, меню); `no` — всегда `enabled` |
| `position` | `top-right` | `top-left`, `top-center`, `top-right`, `bottom-left`, `bottom-center`, `bottom-right` |
| `font` | `monospace` | Шрифт |
| `font_size` | `36` | Размер (относительно OSD высотой 720) |
| `margin` | `20` | Отступ от края |
| `color` / `border_color` | `FFFFFF` / `000000` | Цвета, `RRGGBB` |
| `border_size` | `2` | Толщина обводки |
| `show_info` | `no` | Вторая строка: fps, DF/NDF, источник стартового TC |
| `start_tc` | пусто | Принудительный стартовый таймкод |
| `drop_frame` | `auto` | `auto` (по `;` в стартовом TC), `yes`, `no` |
| `fps` | `0` | Принудительная частота кадров, `0` — авто |
| `use_ffprobe` | `yes` | Искать таймкод через ffprobe |
| `ffprobe_path` | `ffprobe` | Путь к ffprobe |
| `ffprobe_network` | `no` | Запускать ffprobe и для сетевых URL |
| `key_toggle` | `ctrl+t` | Клавиша вкл/выкл |

### Ограничения

- Таймкод считается как `старт + round(time-pos × fps)`. Для VFR и файлов с разрывами таймкода
  (несколько сегментов, SEI-таймкод в H.264/HEVC) он будет приблизительным.
- Отрицательный `time-pos` или `--rebase-start-time=no` дадут смещённый результат.

### Вывод на Blackmagic DeckLink / UltraStudio (форк mpv)

Патч `mpv-patches/0001-vo-add-DeckLink-mirror-output.patch` к mpv 0.41.0 добавляет зеркало:
окно mpv на мониторе работает как обычно (OSC, таймкод), а на карту параллельно идёт чистая
картинка без OSD и субтитров. Windows и macOS (патч `0005`), нужен установленный Blackmagic
Desktop Video.

Сборка: GitHub Actions → **Windows build** → артефакт `mpv-decklink-win64`; ручной запуск с `release_tag` публикует сборку и `RELEASE_NOTES.md` в релиз и ставит его тег на собранный коммит
(`mpv.exe` с DLL; скрипты этого репозитория — в папке `mpv_tc`). **macOS build** собирает
`mpv.app` для Apple Silicon и с `release_tag` добавляет архив в релиз.

macOS: `mpv.app` не нотаризован — перед первым запуском
`xattr -dr com.apple.quarantine /Applications/mpv.app`. Настройки — в `~/.config/mpv/`.

Включение: меню mpv (кнопка ☰ в OSC, `g m` или `Ctrl+P`) → **DeckLink output** → карта.
Выбор запоминается в `decklink.state` в папке настроек mpv и применяется при следующем запуске;
«Off» в том же меню выключает вывод. Там же **Sync audio to DeckLink: on/off** задерживает звук
на задержку карты, чтобы он совпадал с картинкой на карте, а не в окне (тоже запоминается).
Из командной строки:

```
mpv --decklink-mirror=auto file.mov
```

| Опция | Описание |
|---|---|
| `--decklink-mirror=<устройство>` | `auto` — первая карта с выходом, число — по номеру, иначе часть имени. Пусто — выключено |
| `--decklink-mode=<режим>` | `auto` (по частоте кадров и размеру видео) или `1080p25`, `1080i50`, `2160p25`, код `Hp25`. Список — `mpv -v` |
| `--decklink-delay=<сек>` | Дополнительная задержка вывода, если на карте повторяются/пропадают кадры |
| `--decklink-audio-sync=yes` | Задержать звук на задержку карты (свойство `decklink-latency`); `--audio-delay` добавляется сверху — поправка на монитор |

Вместо меню можно прописать в `mpv.conf` (тогда сохранённый выбор из меню не применяется):

```
decklink-mirror=auto
```

Особенности:
- Видео, не совпадающее с размером режима, вписывается с чёрными полями.
- Карта показывает кадр примерно на 3 кадра позже окна (собственный тактовый генератор карты).
- Звук идёт через звуковую карту ПК, на DeckLink выводится только видео (8 бит 4:2:2).
  С синхронизацией звука он совпадает с картинкой на карте, окно при этом чуть опережает звук.
- При `--hwdec` кадры копируются из видеопамяти; при проблемах — `--hwdec=auto-copy`.

### LUT

`scripts/luts.lua` накладывает LUT на видео: меню mpv → **LUT** → папка → LUT (**Off** —
выключить). Выбор запоминается. LUT применяется как видеофильтр, поэтому он есть и на выходе
DeckLink, и на скриншотах.

LUT-ы берутся из папки `luts` в папке настроек mpv (`%APPDATA%\mpv\luts\`,
`~/.config/mpv/luts/`), каждая подпапка — подменю. Форматы: `.cube` (3D и 1D), `.3dl`, `.dat`,
`.m3d`, `.csp`. На вход LUT подаётся RGB камеры с видеоуровнями, растянутыми в 0–1, как в
DaVinci Resolve, — LUT-ы производителей для Resolve подходят без изменений. Выход считается
Rec.709 / BT.1886.

В комплекте (`luts/`), все в Rec.709 BT.1886: Sony — S-Log3 S-Gamut3.Cine, S-Log3 S-Gamut3,
S-Log3 Venice S-Gamut3.Cine / S-Gamut3, S-Log2 S-Gamut; ARRI — LogC3 AWG3 (EI 800),
LogC4 AWG4; Blackmagic — Film Gen 5, DaVinci Intermediate / DWG.

Это технические преобразования, сгенерированные `tools/make_luts.py` по опубликованным
формулам кривых и гамутов (colour-science), с нейтральной плёночной кривой (18% серого → 40%,
мягкий завал светов примерно на 6,5 стопов выше серого). Это не LUT-ы производителей:
официальные LUT-ы Sony / ARRI / Blackmagic можно скачать и положить в отдельную папку рядом.

### Лицензия

GPL-2.0-or-later, см. [LICENSE](LICENSE). `osc/osc.lua` и патчи основаны на mpv
(LGPL-2.1-or-later / GPL-2.0-or-later). Файлы интерфейса DeckLink SDK в
`mpv-patches/0001-*.patch` и `0005-*.patch` — © Blackmagic Design, лицензия в заголовках
файлов. Сборки содержат mpv, FFmpeg и другие библиотеки под их собственными лицензиями.
