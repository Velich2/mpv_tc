@echo off
chcp 65001 >nul
setlocal
rem Запускать, пока mpv завис: записывает стек каждого потока всех процессов
rem mpv.exe в mpv-hang.txt на Рабочем столе.
for /f "usebackq delims=" %%d in (`%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -Command "[Environment]::GetFolderPath('Desktop')"`) do set "DESKTOP=%%d"
if not defined DESKTOP set "DESKTOP=%USERPROFILE%\Desktop"
set "OUT=%DESKTOP%\mpv-hang.txt"
set "PYTHONHOME=%~dp0debug"
set "FOUND="
> "%OUT%" echo mpv hang report %DATE% %TIME%
for /f "tokens=2 delims=," %%p in ('tasklist /FI "IMAGENAME eq mpv.exe" /FO CSV /NH') do (
    if not "%%~p"=="" (
        set "FOUND=1"
        echo Снимаю стек mpv.exe, PID %%~p ...
        >> "%OUT%" echo.
        >> "%OUT%" echo ===== mpv.exe PID %%~p =====
        "%~dp0debug\bin\gdb.exe" -nx -batch -p %%~p -ex "set pagination off" -ex "info threads" -ex "thread apply all bt" -ex "detach" >> "%OUT%" 2>&1
    )
)
if not defined FOUND (
    echo Процесс mpv.exe не найден.
    >> "%OUT%" echo mpv.exe is not running
)
echo Готово: %OUT%
if defined MPV_TC_NOPROMPT goto :eof
choice /M "Завершить зависший mpv"
if errorlevel 2 goto :eof
taskkill /F /IM mpv.exe
