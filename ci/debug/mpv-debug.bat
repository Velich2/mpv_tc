@echo off
chcp 65001 >nul
rem Запускает mpv с подробным логом mpv-debug.log на Рабочем столе.
rem Можно перетащить файл на этот .bat или передать аргументы как mpv.
"%~dp0mpv.exe" -v --msg-time --log-file=~~desktop/mpv-debug.log %*
