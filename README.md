# mpv_tc

SMPTE-таймкод для [mpv](https://mpv.io) — Lua-скрипт, без пересборки плеера.

## Что умеет

- Показывает таймкод `HH:MM:SS:FF` поверх видео; drop-frame — `HH:MM:SS;FF` (29.97, 59.94).
- Стартовый таймкод берёт из файла:
  1. сообщение `set-start` (задаётся во время просмотра);
  2. опция `start_tc`;
  3. метаданные контейнера, которые отдаёт mpv (MXF);
  4. `ffprobe` — теги потоков/контейнера (трек `tmcd` в MOV/MP4);
  5. иначе `00:00:00:00`.
- Публикует текущий таймкод в свойство `user-data/smpte_timecode`.

## Установка

```sh
cp scripts/smpte_timecode.lua     ~/.config/mpv/scripts/
cp script-opts/smpte_timecode.conf ~/.config/mpv/script-opts/   # необязательно
```

Windows: `%APPDATA%\mpv\scripts\` и `%APPDATA%\mpv\script-opts\`.

Для MOV/MP4 нужен `ffprobe` в `PATH` (или путь в `ffprobe_path`).

## Управление

| Действие | Как |
|---|---|
| Вкл/выкл | `Ctrl+T` (опция `key_toggle`) или в `input.conf`: `KEY script-binding smpte_timecode/toggle` |
| Задать старт | `script-message-to smpte_timecode set-start 01:00:00:00` |
| Сбросить старт из `set-start` | `script-message-to smpte_timecode set-start` |

Таймкод в своих строках OSD/терминала:

```sh
mpv --term-status-msg='TC ${user-data/smpte_timecode}' file.mov
```

## Таймкод в панели управления (OSC)

`osc/osc.lua` — стандартный OSC из mpv 0.41.0, у которого вместо текущего времени слева от
полосы перемотки показывается SMPTE-таймкод. Рассчитан на mpv 0.40–0.41 (`mpv --version`).

1. Скопировать `osc/osc.lua` в папку `scripts` рядом с `smpte_timecode.lua`
   (Windows: `%APPDATA%\mpv\scripts\osc.lua`). Имя файла должно остаться `osc.lua`.
2. В `mpv.conf` (Windows: `%APPDATA%\mpv\mpv.conf`) отключить встроенный OSC:
   ```
   osc=no
   ```
3. Чтобы таймкод не дублировался поверх видео, в `script-opts/smpte_timecode.conf`:
   ```
   enabled=no
   ```
   `Ctrl+T` по-прежнему включает и выключает таймкод поверх видео.

Клик по таймкоду в OSC переключает: таймкод → время → время с миллисекундами → таймкод.
Показ по умолчанию отключается в `script-opts/osc.conf`: `smpte_timecode=no`.

Для другой версии mpv: взять `player/lua/osc.lua` этой версии и наложить `osc/osc-smpte.patch`.

## Опции

Файл `script-opts/smpte_timecode.conf` или `--script-opts=smpte_timecode-<опция>=<значение>`.

| Опция | По умолчанию | Описание |
|---|---|---|
| `enabled` | `yes` | Показывать при запуске |
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

## Ограничения

- Таймкод считается как `старт + round(time-pos × fps)`. Для VFR и файлов с разрывами таймкода
  (несколько сегментов, SEI-таймкод в H.264/HEVC) он будет приблизительным.
- Отрицательный `time-pos` или `--rebase-start-time=no` дадут смещённый результат.

## Вывод на Blackmagic DeckLink / UltraStudio (форк mpv)

Патч `mpv-patches/0001-vo-add-DeckLink-mirror-output.patch` к mpv 0.41.0 добавляет зеркало:
окно mpv на мониторе работает как обычно (OSC, таймкод), а на карту параллельно идёт чистая
картинка без OSD и субтитров. Только Windows, нужен установленный Blackmagic Desktop Video.

Сборка: GitHub Actions → **Windows build** → артефакт `mpv-decklink-win64`
(`mpv.exe` с DLL; скрипты этого репозитория — в папке `mpv_tc`).

Включение: меню mpv (кнопка ☰ в OSC, `g m` или `Ctrl+P`) → **DeckLink output** → карта.
Выбор запоминается в `%APPDATA%\mpv\decklink.state` и применяется при следующем запуске;
«Off» в том же меню выключает вывод. Из командной строки:

```
mpv --decklink-mirror=auto file.mov
```

| Опция | Описание |
|---|---|
| `--decklink-mirror=<устройство>` | `auto` — первая карта с выходом, число — по номеру, иначе часть имени. Пусто — выключено |
| `--decklink-mode=<режим>` | `auto` (по частоте кадров и размеру видео) или `1080p25`, `1080i50`, `2160p25`, код `Hp25`. Список — `mpv -v` |
| `--decklink-delay=<сек>` | Дополнительная задержка вывода, если на карте повторяются/пропадают кадры |

Вместо меню можно прописать в `mpv.conf` (тогда сохранённый выбор из меню не применяется):

```
decklink-mirror=auto
```

Особенности:
- Видео, не совпадающее с размером режима, вписывается с чёрными полями.
- Карта показывает кадр примерно на 3 кадра позже окна (собственный тактовый генератор карты).
- Звук идёт через звуковую карту ПК, на DeckLink выводится только видео (8 бит 4:2:2).
- При `--hwdec` кадры копируются из видеопамяти; при проблемах — `--hwdec=auto-copy`.
