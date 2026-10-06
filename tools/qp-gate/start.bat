@echo off
rem qp-gate launcher. With no argument it starts the gate.
rem
rem   start.bat                 start serving (runs --init first when gate.json is missing)
rem   start.bat config          change the settings: login, ports, allowed subnets
rem   start.bat password        change the phone login user and password
rem   start.bat discover        print the desktop upstream port the gate found, then exit
rem   start.bat show            print the effective config with what each field means
rem   start.bat check           run the self test
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
call :tryprobe py -3
if defined PY goto havepy
call :tryprobe python
if defined PY goto havepy
call :tryprobe "%~dp0..\..\python-3.13.0-embed\python.exe"
if defined PY goto havepy
call :tryprobe "%~dp0..\..\..\python-3.13.0-embed\python.exe"
if defined PY goto havepy

echo [qp-gate] Python 3 not found. Install 3.9+, or set PY to a python.exe path.
pause
exit /b 1

:havepy
rem Prove the version floor by parsing the real file with the interpreter just
rem picked. `where python` alone cannot do this: the Microsoft Store stub answers
rem to it, and the user then reads "the gate will not start" while every listed
rem cause in :failed is about something else entirely.
%PY% -c "import io; compile(io.open('qp_gate.py', encoding='utf-8').read(), 'qp_gate.py', 'exec')" >NUL 2>NUL
if not errorlevel 1 goto pyok
echo [qp-gate] picked interpreter cannot parse qp_gate.py. Need Python 3.9+.
echo [qp-gate] picked: %PY%
pause
exit /b 1

:pyok
if /i "%~1"=="password" goto password
if /i "%~1"=="config" goto config
if /i "%~1"=="discover" goto discover
if /i "%~1"=="show" goto show
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
goto editfailed

:serve
%PY% qp_gate.py
if not errorlevel 1 goto done
goto failed

:password
if not exist "gate.json" goto noconfig
%PY% qp_gate.py --set-password
if not errorlevel 1 goto done
goto editfailed

:config
if not exist "gate.json" goto noconfig
rem --edit keeps every value as the prompt default and never regenerates
rem token_secret, so an accidental Enter changes nothing and a port change does
rem not sign the phone out. Rewriting gate.json with --init --force would do both.
%PY% qp_gate.py --edit
if not errorlevel 1 goto done
goto editfailed

:discover
%PY% qp_gate.py --discover
if errorlevel 1 echo [qp-gate] no upstream yet: start the desktop app first, then retry.
goto done

:show
%PY% qp_gate.py --show
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

:noconfig
echo [qp-gate] gate.json is missing. Run start.bat with no argument once to create it.
pause
exit /b 1

:editfailed
rem A refused edit is not a gate that failed to start: --edit and --set-password
rem stop before saving, so the config on disk is exactly what it was. Telling the
rem user about ports in use and a desktop that is not running sends them hunting
rem for a fault that does not exist.
echo [qp-gate] nothing was written - these prompts stop before saving.
echo [qp-gate] usual causes: password shorter than 8 characters, a port out of range,
echo   or running this from a pipe instead of a console window.
echo Copy one whole line and retry:
echo   %PY% "%~dp0qp_gate.py" --edit
echo   %PY% "%~dp0qp_gate.py" --show
pause
exit /b 1

:unknown
echo [qp-gate] unknown command: %~1
echo.

:usage
echo [qp-gate] commands (also: start.bat help):
echo   start.bat                 start serving
echo   start.bat config          change the settings: login, ports, allowed subnets
echo   start.bat password        change the phone login user and password
echo   start.bat discover        print the upstream port the gate found
echo   start.bat show            print the effective config with what each field means
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
echo   - 403 from the phone: wrong allow_cidrs, the gate log names the rejected IP
echo     (run: start.bat show)
echo Copy one whole line and retry:
echo   %PY% "%~dp0qp_gate.py" --set-password
echo   %PY% "%~dp0qp_gate.py" --discover
pause
endlocal
exit /b 1

:tryprobe
rem Run the candidate for real instead of asking PATH whether it exists: the
rem Microsoft Store ships a python.exe stub that answers to `where` and then
rem refuses to run. %* keeps both shapes working - "py -3" and a quoted path.
%* -c "import sys" >NUL 2>NUL
if errorlevel 1 exit /b 0
set "PY=%*"
exit /b 0
