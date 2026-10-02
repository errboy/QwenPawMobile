@echo off
rem qp-gate 一键启动：自动挑一个可用的 Python；缺配置就先引导设置，再放行防火墙并启动。
setlocal
cd /d "%~dp0"
chcp 65001 >nul

set "PY="
where python >nul 2>nul
if not errorlevel 1 set "PY=python"
if not defined PY (
  where py >nul 2>nul
  if not errorlevel 1 set "PY=py -3"
)
if not defined PY (
  if exist "%~dp0..\..\python-3.13.0-embed\python.exe" set "PY=%~dp0..\..\python-3.13.0-embed\python.exe"
)
if not defined PY (
  if exist "E:\0_WorkSpace_AI\0_Qcoder\python-3.13.0-embed\python.exe" set "PY=E:\0_WorkSpace_AI\0_Qcoder\python-3.13.0-embed\python.exe"
)
if not defined PY goto :nopython

if not exist "gate.json" (
  echo 第一次运行：设置手机端登录用的用户名和口令（输入不回显）。
  %PY% qp_gate.py --init
  if errorlevel 1 goto :failed
)

%PY% qp_gate.py
if errorlevel 1 goto :failed
endlocal
exit /b 0

:nopython
echo 没找到 Python 3。装一个 3.9+，或把嵌入式解释器的完整路径写进本脚本的 PY 变量。
pause
exit /b 1

:failed
echo 守门代理没起来。常见原因：gate.json 里没配账号口令（跑 qp_gate.py --set-password）、
echo 端口被占（改 gate.json 的 listen_port）、或者上游桌面端没开（qp_gate.py --discover 可自查）。
pause
exit /b 1
