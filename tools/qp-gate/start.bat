@echo off
rem qp-gate launcher. With no argument it starts the gate.
rem
rem   start.bat                 start serving (runs --init first when gate.json is missing)
rem   start.bat password        change the phone login user and password
rem   start.bat discover        print the desktop upstream port the gate found, then exit
rem   start.bat check           run the self test (40 checks)
rem   start.bat firewall        add the Windows inbound rule (shows a UAC prompt)
rem   start.bat firewall-remove delete the rule this tool added
rem   start.bat help            show this list
rem
rem Passwords are only ever typed at the prompt: they never become a command-line
rem argument, so they stay out of the process list and the shell history.
rem
rem ASCII-only on purpose: cmd mis-parses non-ASCII bytes inside a batch body,
rem so every Chinese message comes from qp_gate.py instead (it writes the console
rem through the Unicode API and is not affected by the active codepage).
setlocal
cd /d "%~dp0"

set "PY="
where python >NUL 2>NUL
if not errorlevel 1 set "PY=python"
if defined PY goto havepy
where py >NUL 2>NUL
if not errorlevel 1 set "PY=py -3"
if defined PY goto havepy
if exist "%~dp0..\..\python-3.13.0-embed\python.exe" set "PY=%~dp0..\..\python-3.13.0-embed\python.exe"
if defined PY goto havepy
if exist "%~dp0..\..\..\python-3.13.0-embed\python.exe" set "PY=%~dp0..\..\..\python-3.13.0-embed\python.exe"
if defined PY goto havepy

echo [qp-gate] Python 3 not found. Install 3.9+, or set PY to a python.exe path.
pause
exit /b 1

:havepy
if /i "%~1"=="password" goto password
if /i "%~1"=="discover" goto discover
if /i "%~1"=="check" goto check
if /i "%~1"=="firewall" goto firewall
if /i "%~1"=="firewall-remove" goto firewallremove
if /i "%~1"=="help" goto usage
if not "%~1"=="" goto unknown

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

:password
if not exist "gate.json" goto nopassword
%PY% qp_gate.py --set-password
if not errorlevel 1 goto done
goto failed

:discover
%PY% qp_gate.py --discover
if errorlevel 1 echo [qp-gate] no upstream yet: start the desktop app first, then retry.
goto done

:check
%PY% selftest.py
if errorlevel 1 echo [qp-gate] self test failed, see the lines above.
goto done

:firewall
%PY% qp_gate.py --firewall
if not errorlevel 1 goto done
goto failed

:firewallremove
%PY% qp_gate.py --remove-firewall
if not errorlevel 1 goto done
goto failed

:nopassword
echo [qp-gate] gate.json is missing. Run start.bat with no argument once to create it.
pause
exit /b 1

:unknown
echo [qp-gate] unknown command: %~1
echo.

:usage
echo [qp-gate] commands (also: start.bat help):
echo   start.bat                 start serving
echo   start.bat password        change the phone login user and password
echo   start.bat discover        print the upstream port the gate found
echo   start.bat check           run the self test
echo   start.bat firewall        add the Windows inbound rule (UAC prompt)
echo   start.bat firewall-remove delete the rule this tool added
goto done

:done
endlocal
exit /b 0

:failed
echo [qp-gate] the gate did not come up. Usual causes:
echo   - port already in use: another gate is running, only one can hold it
echo   - desktop app not started: the gate has nothing to forward to
echo   - credentials wrong or gate.json damaged: run start.bat password
echo Copy one whole line and retry:
echo   %PY% "%~dp0qp_gate.py" --set-password
echo   %PY% "%~dp0qp_gate.py" --discover
pause
endlocal
exit /b 1
