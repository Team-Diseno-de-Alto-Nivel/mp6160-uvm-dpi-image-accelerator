@echo off
REM ---------------------------------------------------------------------------
REM run_uvm_windows.bat - lanzador de run_uvm_windows.ps1
REM ---------------------------------------------------------------------------
REM Existe solo para poder correr el flujo con doble clic o desde cmd sin pelear
REM con la execution policy de PowerShell. Todos los argumentos se pasan tal
REM cual al script .ps1.
REM
REM Uso:
REM   scripts\run_uvm_windows.bat
REM   scripts\run_uvm_windows.bat -Test smoke_test
REM   scripts\run_uvm_windows.bat -VivadoPath "D:\Xilinx\Vivado\2019.2"
REM ---------------------------------------------------------------------------

setlocal

set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%run_uvm_windows.ps1"

if not exist "%PS_SCRIPT%" (
    echo ERROR: no se encontro "%PS_SCRIPT%"
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" %*
set "RC=%ERRORLEVEL%"

REM Pausa solo si se abrio con doble clic, para que la ventana no se cierre
REM antes de poder leer el resultado.
echo %CMDCMDLINE% | find /i "%~0" >nul 2>&1
if not errorlevel 1 pause

exit /b %RC%
