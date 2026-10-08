@echo off
rem qp-gate launcher. With no argument it starts the gate.
rem
rem   start.bat                 start serving (runs --init first when gate.json is missing)
rem   start.bat stop            stop the gate that is listening (only one it can identify)
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
rem through the Unicode API and is not affected by the active codepage). The
rem failure tails below are the one case where the message is needed after the
rem Python already exited, so each of them calls "qp_gate.py --explain <branch>".
setlocal
cd /d "%~dp0"

rem A Python the caller named beats the search below. The embedded build runs this
rem tool fine - only standard library - and where someone put it is not something
rem this script can guess, so the caller says it with PY instead. PY is probed like
rem every other candidate: a PY pointing at a deleted python.exe falls through to
rem the search rather than failing the run, and that fallback is announced. The
rem value itself is never echoed: cmd expands %VAR% while it parses the echo line,
rem so a path holding & would run as two commands.
set "WANTED=%PY%"
set "PY="
if defined WANTED call :tryprobe %WANTED%
if defined WANTED if not defined PY echo [qp-gate] your PY does not run, searching on its own instead.
if defined PY goto havepy
call :tryprobe py -3
if defined PY goto havepy
call :tryprobe python
if defined PY goto havepy
call :tryprobe "%~dp0..\..\python-3.13.0-embed\python.exe"
if defined PY goto havepy
call :tryprobe "%~dp0..\..\..\python-3.13.0-embed\python.exe"
if defined PY goto havepy

echo [qp-gate] Python 3 not found. Install 3.9+, or set PY to a python.exe path.
echo [qp-gate] to point this at one you already have, in the same window:
echo   set PY=C:\path\to\python.exe
echo [qp-gate] an embedded build is enough. It is looked for under the name
echo   python-3.13.0-embed inside this folder and one level above it.
pause
exit /b 1

:havepy
rem Prove the version floor by parsing the real file with the interpreter just
rem picked. `where python` alone cannot do this: the Microsoft Store stub answers
rem to it, and the user then reads "the gate will not start" while every listed
rem cause in :failed is about something else entirely.
rem
rem The path is passed as an argument instead of being written into the -c string:
rem a folder name holding \0 or \U would be a Python escape sequence there, and an
rem apostrophe in a path would close its quote. And the file is looked for first,
rem so "this interpreter cannot parse it" is only ever said about a file that is
rem there - a half-copied tool folder used to hear that sentence about Python.
if not exist "%~dp0qp_gate.py" goto missingfile
%PY% -c "import io,sys; compile(io.open(sys.argv[1], encoding='utf-8').read(), sys.argv[1], 'exec')" "%~dp0qp_gate.py" >NUL 2>NUL
if not errorlevel 1 goto pyok
echo [qp-gate] picked interpreter cannot parse qp_gate.py. Need Python 3.9+.
echo [qp-gate] picked: %PY%
pause
exit /b 1

:missingfile
echo [qp-gate] qp_gate.py is not beside this script. The two are one tool.
echo [qp-gate] looked in: %~dp0
pause
exit /b 1

:pyok
if /i "%~1"=="stop" goto stop
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

:stop
if not exist "gate.json" goto noconfig
%PY% qp_gate.py --stop
if not errorlevel 1 goto done
goto stopfailed

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
if errorlevel 1 %PY% qp_gate.py --explain=discover
goto done

:show
%PY% qp_gate.py --show
goto done

:check
%PY% selftest.py
if errorlevel 1 %PY% qp_gate.py --explain=check
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
%PY% qp_gate.py --explain=noconfig
pause
exit /b 1

:editfailed
rem A refused edit is not a gate that failed to start: --edit and --set-password
rem stop before saving, so the config on disk is exactly what it was. Telling the
rem user about ports in use and a desktop that is not running sends them hunting
rem for a fault that does not exist.
%PY% qp_gate.py --explain=edit
pause
exit /b 1

:unknown
rem The word itself is what the user typed, so it is echoed as-is; the
rem sentence around it comes from qp_gate.py (ASCII-only body, see the head).
echo %~1
%PY% qp_gate.py --explain=unknown
echo.

:usage
rem The command table is Chinese prose for the console, so it lives in qp_gate.py
rem for the same reason the failure tails do (ASCII-only body, see the head).
%PY% qp_gate.py --explain=usage
goto done

:done
endlocal
exit /b 0

:failed
%PY% qp_gate.py --explain=failed
pause
endlocal
exit /b 1

:stopfailed
rem A gate that is still listening is not a gate that was stopped. --stop only kills a
rem process whose own command line names qp_gate, so a stranger holding the port is
rem left running on purpose, and the lines above name the PID it refused.
%PY% qp_gate.py --explain=stop
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
