@echo off
rem qp-gate one-click start. Picks a usable Python 3, runs --init when gate.json
rem is missing, then serves.
rem
rem ASCII-only on purpose: cmd mis-parses non-ASCII bytes inside a batch body,
rem so every Chinese message comes from qp_gate.py instead (it writes the console
rem through the Unicode API and is not affected by the active codepage).
setlocal
cd /d "%~dp0"

set "PY="
where python >nul 2>nul
if not errorlevel 1 set "PY=python"
if defined PY goto havepy
where py >nul 2>nul
if not errorlevel 1 set "PY=py -3"
if defined PY goto havepy
if exist "%~dp0..\..\python-3.13.0-embed\python.exe" set "PY=%~dp0..\..\python-3.13.0-embed\python.exe"
if defined PY goto havepy
if exist "E:\0_WorkSpace_AI\0_Qcoder\python-3.13.0-embed\python.exe" set "PY=E:\0_WorkSpace_AI\0_Qcoder\python-3.13.0-embed\python.exe"
if defined PY goto havepy

echo [qp-gate] Python 3 not found. Install 3.9+, or set PY to a python.exe path.
pause
exit /b 1

:havepy
if not exist "gate.json" goto setup
goto serve

:setup
%PY% qp_gate.py --init
if not errorlevel 1 goto serve
goto failed

:serve
%PY% qp_gate.py
if not errorlevel 1 goto done
goto failed

:done
endlocal
exit /b 0

:failed
echo [qp-gate] gate did not start. Copy one whole line and retry:
echo   %PY% "%~dp0qp_gate.py" --set-password
echo   %PY% "%~dp0qp_gate.py" --discover
pause
endlocal
exit /b 1
