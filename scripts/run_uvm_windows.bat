@echo off
REM ---------------------------------------------------------------------------
REM run_uvm_windows.bat - launcher for run_uvm_windows.ps1
REM ---------------------------------------------------------------------------
REM Exists only so the flow can be run by double-click or from cmd without
REM fighting PowerShell's execution policy. All arguments are passed through to
REM the .ps1 script unchanged.
REM
REM Usage:
REM   scripts\run_uvm_windows.bat
REM   scripts\run_uvm_windows.bat -Test smoke_test
REM   scripts\run_uvm_windows.bat -VivadoPath "D:\Xilinx\Vivado\2019.2"
REM ---------------------------------------------------------------------------

setlocal

set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%run_uvm_windows.ps1"

if not exist "%PS_SCRIPT%" (
    echo ERROR: "%PS_SCRIPT%" not found
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" %*
set "RC=%ERRORLEVEL%"

REM Pause only when launched by double-click, so the window does not close
REM before the result can be read.
echo %CMDCMDLINE% | find /i "%~0" >nul 2>&1
if not errorlevel 1 pause

exit /b %RC%
