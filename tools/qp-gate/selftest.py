#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""qp-gate 自检：安全边界 + 流式转发。

自带一个桩上游（JSON / 慢速 SSE / 大请求体 / 二进制），因此不依赖桌面端，在任何
机器上都能跑，也不会误碰用户真实的 ~/.qwenpaw 工作目录。

    python selftest.py
"""
from __future__ import annotations

import asyncio
import builtins
import collections
import concurrent.futures
import contextlib
import hashlib
import http.client
import io
import ipaddress
import json
import os
import random
import socket
import subprocess
import sys
import tempfile
import threading
import time
import types
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")
sys.path.insert(0, str(Path(__file__).resolve().parent))
import qp_gate  # noqa: E402

USER = "selftest-user"
PASSWORD = "selftest-passw0rd"
CREDENTIAL = qp_gate.hash_password(PASSWORD)
SECRET = "11" * 32
SSE_CHUNKS = 6
SSE_DELAY = 0.15
BIG_BODY = 8 * 1024 * 1024
BINARY_BYTES = 1024 * 1024

RESULTS: list = []
STUB: dict = {"auth_hits": [], "requests": 0}


def check(name: str, ok: bool, detail: str = "") -> None:
    RESULTS.append((name, bool(ok)))
    line = f"{'PASS' if ok else 'FAIL'}  {name}"
    if detail and not ok:
        line += f"  -- {detail}"
    # 走 RAW_OUT：静音小节里被收走的只有被测程序打的话，断言永远上屏。
    print(line, file=RAW_OUT, flush=True)


# ---------------------------------------------------------------- 输出排版
#
# 正文此前是 79 行 PASS 夹着 50 行守门代理自己的日志。那些日志正是被测系统在被请求时
# 打的东西，但逐条读 PASS 的人只能把它们当噪声跳过，一行都读不进去。现在按小节分组，
# 日志先按小节攒起来：全过时不出现，某一节有 FAIL 时在那一节末尾整段回显——那种时候
# 它是定位线索，不是噪声。

SECTIONS: list = []
LOG_PREFIX = "[qp-gate "
RAW_OUT = sys.stdout


class GateLogTee(io.TextIOBase):
    """把被测程序自己打的行收进当前小节，PASS/FAIL 与小节标题照常上屏。

    默认只截 [qp-gate ...] 这一种；小节标了 mute=True 时该节内一切 print 都收走
    （--edit 那几节里，被 fake 掉的输入让六行提问原样刷出来，把断言埋了）。
    自检自己打的话走 RAW_OUT，不经过本类，所以静音绝不会把 PASS/FAIL 一起吞掉。

    截的是 stdout 而不是把 log() 换成替身：断言里用 redirect_stdout 换掉 sys.stdout
    时本类根本不在链上，"日志必须点出被拒地址""stdout 关掉时 log 不抛"那两条测的
    仍是模块里原样的 log()。
    """

    def __init__(self, out) -> None:
        self._out = out
        self._sink = None
        self._mute = False
        self._pending = False
        self._lock = threading.Lock()

    def writable(self) -> bool:
        return True

    def set_sink(self, sink) -> None:
        self._sink = sink

    def set_mute(self, on: bool) -> None:
        self._mute = on

    def write(self, text: str) -> int:
        with self._lock:
            if self._pending and text == "\n":
                self._pending = False
                return len(text)
            self._pending = False
            captured = self._sink is not None and (
                self._mute or text.startswith(LOG_PREFIX))
            if not captured:
                try:
                    return self._out.write(text)
                except (OSError, ValueError, RuntimeError):
                    return len(text)
            self._sink.append(text[:-1] if text.endswith("\n") else text)
            self._pending = not text.endswith("\n")
            return len(text)

    def flush(self) -> None:
        try:
            self._out.flush()
        except (OSError, ValueError, RuntimeError):
            pass

    def close(self) -> None:
        self.flush()

    def __getattr__(self, name):
        if name.startswith("_"):
            raise AttributeError(name)
        return getattr(self._out, name)


TEE = GateLogTee(RAW_OUT)
sys.stdout = TEE


@contextlib.contextmanager
def section(title: str, mute: bool = False):
    logs: list = []
    start = len(RESULTS)
    print(f"\n── {title} ──", file=RAW_OUT, flush=True)
    TEE.set_sink(logs)
    TEE.set_mute(mute)
    try:
        yield
    finally:
        TEE.set_sink(None)
        TEE.set_mute(False)
        SECTIONS.append((title, start, len(RESULTS), logs))


# ---------------------------------------------------------------- 桩上游


async def read_stub_request(reader):
    raw = await reader.readuntil(b"\r\n\r\n")
    parsed = qp_gate.parse_head(raw)
    if parsed is None:
        return None
    _line, _headers, method, path, fields = parsed
    size = int(fields.get("content-length") or 0)
    body = b""
    while len(body) < size:
        chunk = await reader.read(min(64 * 1024, size - len(body)))
        if not chunk:
            break
        body += chunk
    return method, path, fields, body


async def stub_serve(reader, writer):
    """One request per connection: qp-gate rewrites Connection to close."""
    try:
        request = await read_stub_request(reader)
        if request is None:
            return
        method, path, fields, body = request
        STUB["requests"] += 1
        # 守门代理自己发现上游时会带 UA=qp-gate 打这里；那不算客户端漏转发。
        if path.startswith("/api/auth") and fields.get("user-agent") != "qp-gate":
            STUB["auth_hits"].append(f"{method} {path}")
        if path == "/api/auth/status":
            # 上游自己回"未开鉴权"，用来证明本地应答的 enabled=true 覆盖了它。
            await reply(writer, 200, {"enabled": False, "has_users": False})
        elif path == "/ping":
            await reply(writer, 200, {
                "pong": True,
                "connection": fields.get("connection", ""),
                "xff": fields.get("x-forwarded-for", ""),
                "auth_seen": bool(fields.get("authorization")),
            })
        elif path == "/slow-sse":
            writer.write(b"HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\n"
                         b"Cache-Control: no-cache\r\nConnection: close\r\n\r\n")
            await writer.drain()
            for index in range(SSE_CHUNKS):
                writer.write(f"data: frame-{index}\n\n".encode())
                await writer.drain()
                await asyncio.sleep(SSE_DELAY)
        elif path in ("/echo-size", "/upload"):
            await reply(writer, 200, {"bytes": len(body),
                                      "sha256": hashlib.sha256(body).hexdigest()})
        elif path == "/bin":
            blob = deterministic(BINARY_BYTES)
            writer.write(f"HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\n"
                         f"Content-Length: {len(blob)}\r\nConnection: close\r\n\r\n".encode())
            writer.write(blob)
            await writer.drain()
        else:
            await reply(writer, 404, {"detail": "stub: no such route"})
    except (asyncio.LimitOverrunError, asyncio.IncompleteReadError, ConnectionError):
        pass
    finally:
        try:
            writer.close()
        except Exception:
            pass


async def reply(writer, status: int, payload: dict) -> None:
    body = json.dumps(payload).encode()
    reason = "OK" if status == 200 else "Not Found"
    writer.write(f"HTTP/1.1 {status} {reason}\r\nContent-Type: application/json\r\n"
                 f"Content-Length: {len(body)}\r\nConnection: close\r\n\r\n".encode())
    writer.write(body)
    await writer.drain()


def deterministic(size: int) -> bytes:
    rng = random.Random(20261003)
    block = bytes(rng.getrandbits(8) for _ in range(4096))
    return (block * (size // len(block) + 1))[:size]


# ---------------------------------------------------------------- 客户端


def call(method: str, path: str, port: int, token: str = "", body: bytes = b"",
         ctype: str = "application/json", timeout: float = 60.0):
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=timeout)
    headers = {"Content-Type": ctype}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    conn.request(method, path, body=body or None, headers=headers)
    res = conn.getresponse()
    payload = res.read()
    conn.close()
    return res.status, dict(res.getheaders()), payload


def login(password: str = PASSWORD) -> bytes:
    return json.dumps({"username": USER, "password": password,
                       "expires_in": 0}).encode()


def raw(port: int, data: bytes, timeout: float = 10.0, allow_reset: bool = False) -> bytes:
    with socket.create_connection(("127.0.0.1", port), timeout=timeout) as sock:
        sock.sendall(data)
        chunks = []
        try:
            while True:
                got = sock.recv(65536)
                if not got:
                    break
                chunks.append(got)
        except socket.timeout:
            chunks.append(b"<timeout>")
        except ConnectionResetError:
            # 超长请求头会被直接掐断：Windows 在有未读数据时 close 会发 RST。
            if not allow_reset:
                raise
            chunks.append(b"<reset>")
        return b"".join(chunks)


def sse_arrivals(port: int, token: str) -> list:
    """Client-side arrival time of each SSE frame — proves nothing got buffered."""
    stamps = []
    with socket.create_connection(("127.0.0.1", port), timeout=30.0) as sock:
        sock.sendall(f"GET /slow-sse HTTP/1.1\r\nHost: 127.0.0.1\r\n"
                     f"Authorization: Bearer {token}\r\n"
                     f"Accept: text/event-stream\r\n\r\n".encode())
        started = time.monotonic()
        buf = b""
        while b"\r\n\r\n" not in buf:
            got = sock.recv(4096)
            if not got:
                return stamps
            buf += got
        buf = buf.split(b"\r\n\r\n", 1)[1]
        while True:
            try:
                got = sock.recv(4096)
            except socket.timeout:
                break
            if not got:
                break
            now = time.monotonic() - started
            buf += got
            while b"\n\n" in buf:
                stamps.append(now)
                buf = buf.split(b"\n\n", 1)[1]
    return stamps


# ---------------------------------------------------------------- 用例


def gate_config(path: Path, stub_port: int, **over) -> dict:
    raw_cfg = {
        "listen_host": "127.0.0.1",
        "listen_port": 0,
        "upstream_host": "127.0.0.1",
        "upstream_port": stub_port,
        "username": USER,
        "credential": CREDENTIAL,
        "token_secret": SECRET,
        "token_ttl_seconds": 0,
        "max_connections": 8,
        "login_max_failures": 3,
        "login_window_seconds": 300,
        "allow_cidrs": ["127.0.0.0/8"],
    }
    raw_cfg.update(over)
    return raw_cfg


def suite(port: int) -> str:
    """Main suite against a gate forwarding to the asyncio stub. Returns a token."""
    status, _, body = call("GET", "/api/auth/status", port)
    before = len(STUB["auth_hits"])
    doc = json.loads(body)
    check("/auth/status 由本地应答 enabled=true",
          status == 200 and doc.get("enabled") is True and doc.get("has_users") is True,
          str(doc))
    check("/auth/status 没有漏转发给上游", before == 0, str(STUB["auth_hits"]))

    status, _, body = call("POST", "/api/auth/login", port, body=login())
    token = json.loads(body).get("token", "")
    check("登录 200 且返回 token/username",
          status == 200 and token.count(".") == 1
          and json.loads(body).get("username") == USER, f"{status} {body[:80]!r}")

    check("永久令牌可解出用户名", qp_gate.Tokens(SECRET).check(token) == USER)
    check("异密钥签发的令牌不被接受",
          qp_gate.Tokens("22" * 32).check(token) is None)
    expired = qp_gate.Tokens(SECRET).issue(USER, -5)
    check("过期令牌 401", call("GET", "/ping", port, token=expired)[0] == 401)

    wrong = call("POST", "/api/auth/login", port, body=login()
                 .replace(b"selftest-passw0rd", b"wrong-password"))
    check("口令错误 401", wrong[0] == 401, str(wrong[0]))
    limited = None
    for _ in range(4):
        limited = call("POST", "/api/auth/login", port, body=login()
                       .replace(b"selftest-passw0rd", b"another-wrong"))
        if limited[0] == 429:
            break
    check("连续失败触发限流 429", limited[0] == 429, str(limited[0]))
    blocked = call("POST", "/api/auth/login", port, body=login())
    check("限流窗口内正确口令也被拒", blocked[0] == 429, str(blocked[0]))

    for name, path in (("register", "/api/auth/register"),
                       ("update-profile", "/api/auth/update-profile"),
                       ("revoke-token", "/api/auth/revoke-token"),
                       ("revoke-all-tokens", "/api/auth/revoke-all-tokens")):
        code, _, _ = call("POST", path, port, body=b"{}")
        check(f"{name} 被接管为 403", code == 403, str(code))
    check("被接管的 auth 端点始终没到上游", len(STUB["auth_hits"]) == 0,
          str(STUB["auth_hits"]))

    check("无令牌访问业务路由 401", call("GET", "/ping", port)[0] == 401)
    head, sig = token.split(".")
    flipped = head + "." + (("A" if sig[-1] != "A" else "B") + sig[:-1])
    check("篡改签名 401", call("GET", "/ping", port, token=flipped)[0] == 401)
    check("畸形令牌 401", call("GET", "/ping", port, token="abc")[0] == 401)

    status, _, body = call("GET", "/ping", port, token=token)
    echoed = json.loads(body)
    check("带令牌转发到上游 200", status == 200 and echoed.get("pong") is True, str(status))
    check("转发时改写 Connection: close", echoed.get("connection") == "close",
          str(echoed.get("connection")))
    check("注入 X-Forwarded-For", echoed.get("xff") == "127.0.0.1", str(echoed.get("xff")))
    check("Authorization 原样透传", echoed.get("auth_seen") is True)

    stamps = sse_arrivals(port, token)
    gaps = [round(b - a, 3) for a, b in zip(stamps, stamps[1:])]
    spread = (stamps[-1] - stamps[0]) if len(stamps) >= 2 else 0.0
    check("SSE 分帧按时间到达、未被攒成一坨",
          len(stamps) == SSE_CHUNKS and spread > SSE_DELAY * (SSE_CHUNKS - 1) * 0.6
          and (not gaps or max(gaps) < SSE_DELAY * 5),
          f"frames={len(stamps)} spread={spread:.2f}s gaps={gaps}")

    blob = os.urandom(BIG_BODY)
    status, _, body = call("POST", "/upload", port, token=token, body=blob,
                           ctype="multipart/form-data; boundary=qp")
    echoed = json.loads(body)
    check(f"{BIG_BODY // (1024 * 1024)}MB 请求体流式转发、字节一致",
          status == 200 and echoed.get("bytes") == BIG_BODY
          and echoed.get("sha256") == hashlib.sha256(blob).hexdigest(), str(echoed)[:160])

    status, _, got = call("GET", "/bin", port, token=token)
    expect = hashlib.sha256(deterministic(BINARY_BYTES)).hexdigest()
    check("二进制响应逐字节完整",
          status == 200 and len(got) == BINARY_BYTES
          and hashlib.sha256(got).hexdigest() == expect, f"{len(got)} bytes")

    abs_form = raw(port, f"GET http://127.0.0.1:{port}/api/auth/status HTTP/1.1\r\n"
                         f"Host: 127.0.0.1\r\n\r\n".encode())
    connect = raw(port, b"CONNECT example.com:443 HTTP/1.1\r\nHost: example.com:443\r\n\r\n")
    check("绝对形式请求行 400（防绕过鉴权面）", abs_form.startswith(b"HTTP/1.1 400"),
          abs_form[:48].decode("latin-1"))
    check("CONNECT 隧道请求 400", connect.startswith(b"HTTP/1.1 400"),
          connect[:48].decode("latin-1"))

    giant = raw(port, b"GET /ping HTTP/1.1\r\nHost: x\r\nX-Big: " + b"a" * (256 * 1024)
                + b"\r\n\r\n", allow_reset=True)
    check("超长请求头被拒绝（431 或直接掐断）",
          giant.startswith(b"HTTP/1.1 431") or b"<reset>" in giant,
          giant[:48].decode("latin-1"))

    junk = raw(port, b"\x00\x01\x02not http\r\n\r\n")
    check("畸形报文被拒绝且进程存活", junk.startswith(b"HTTP/1.1 400"),
          junk[:48].decode("latin-1"))
    check("畸形报文之后守门代理仍在服务",
          call("GET", "/api/auth/status", port)[0] == 200)
    return token


def cidr_suite(tmp: Path, stub_port: int) -> None:
    holder = {}

    async def scenario():
        config = qp_gate.Config(gate_config(tmp, stub_port,
                                            allow_cidrs=["10.99.0.0/16"]), tmp)
        gate = qp_gate.Gate(config)
        server = await asyncio.start_server(gate.serve, "127.0.0.1", 0)
        holder["port"] = server.sockets[0].getsockname()[1]
        async with server:
            await asyncio.sleep(10)

    _in_thread(scenario, lambda: holder.get("port"))
    port = holder["port"]
    probe = call("GET", "/api/auth/status", port)
    check("网段外的地址连鉴权面都摸不到", probe[0] == 403, str(probe[0]))
    code, _, _ = call("GET", "/ping", port, token="whatever")
    check("网段外的地址业务路由也 403", code == 403, str(code))
    # The response alone is not the contract: a first-time user with a wrong
    # allow_cidrs sees a 403 on the phone and has no way to learn which address
    # to whitelist. The gate log has to name it.
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        call("GET", "/api/auth/status", port)
    check("网段拒绝在守门代理日志里点出被拒地址与生效网段",
          "403 拒绝" in buf.getvalue() and "10.99.0.0/16" in buf.getvalue(),
          repr(buf.getvalue()[:160]))


def upstream_missing_suite(tmp: Path, stub_port: int) -> None:
    holder = {}

    async def scenario():
        config = qp_gate.Config(gate_config(tmp, stub_port), tmp)
        gate = qp_gate.Gate(config)
        gate.upstream.resolve = lambda: None  # 模拟桌面端没启动
        server = await asyncio.start_server(gate.serve, "127.0.0.1", 0)
        holder["port"] = server.sockets[0].getsockname()[1]
        async with server:
            await asyncio.sleep(10)

    _in_thread(scenario, lambda: holder.get("port"))
    port = holder["port"]
    token = json.loads(call("POST", "/api/auth/login", port, body=login())[2])["token"]
    status, _, body = call("GET", "/ping", port, token=token)
    check("上游发现失败 502 且文案可行动",
          status == 502 and "QwenPaw" in body.decode("utf-8"),
          f"{status} {body[:120].decode('utf-8')}")


def _in_thread(coroutine_factory, ready) -> None:
    thread = threading.Thread(target=lambda: asyncio.run(coroutine_factory()),
                              daemon=True)
    thread.start()
    deadline = time.monotonic() + 8
    while time.monotonic() < deadline and not ready():
        time.sleep(0.05)
    if not ready():
        raise RuntimeError("场景服务未能启动")


def discovery_suite(stub_port: int) -> None:
    """--discover 的依赖路径：config.json 的 last_api 优先，且必须验形状。"""
    with tempfile.TemporaryDirectory() as tmpdir:
        home = Path(tmpdir)
        prev = os.environ.get("QWENPAW_WORKING_DIR")
        os.environ["QWENPAW_WORKING_DIR"] = str(home)
        try:
            (home / "config.json").write_text(
                json.dumps({"last_api": {"host": "127.0.0.1", "port": stub_port}}),
                encoding="utf-8")
            check("config_candidates 读到 last_api.port",
                  stub_port in qp_gate.config_candidates(),
                  str(qp_gate.config_candidates()))
            path = home / "gate.json"
            config = qp_gate.Config(gate_config(path, 0), path)
            check("Upstream 从配置文件自动发现上游",
                  qp_gate.Upstream(config).resolve() == stub_port)

            (home / "config.json").write_text(
                json.dumps({"last_api": {"host": "127.0.0.1", "port": 59999}}),
                encoding="utf-8")
            check("无人监听的端口不算命中",
                  qp_gate.probe_upstream("127.0.0.1", 59999, timeout=1.0) is False)

            decoy = _decoy_server()
            try:
                check("非 QwenPaw 形状的 HTTP 服务被排除",
                      qp_gate.probe_upstream("127.0.0.1", decoy, timeout=2.0) is False)
            finally:
                _shutdown_decoy()

            gremlin = _gremlin_server()
            try:
                check("乱协议端口不会把发现流程炸掉",
                      qp_gate.probe_upstream("127.0.0.1", gremlin, timeout=2.0) is False)
            finally:
                _shutdown_gremlin()
        finally:
            if prev is None:
                os.environ.pop("QWENPAW_WORKING_DIR", None)
            else:
                os.environ["QWENPAW_WORKING_DIR"] = prev


_decoy: dict = {}
_gremlin: dict = {}


def _decoy_server() -> int:
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            payload = json.dumps({"ok": True, "service": "not-qwenpaw"}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

        def log_message(self, *_args):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    _decoy["server"] = server
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server.server_address[1]


def _shutdown_decoy() -> None:
    server = _decoy.get("server")
    if server:
        server.shutdown()
        server.server_close()
        _decoy.pop("server", None)


def _gremlin_server() -> int:
    """回一条非 HTTP 状态行就挂断：模拟回环上别的协议的服务。"""
    sock = socket.socket()
    sock.bind(("127.0.0.1", 0))
    sock.listen(8)

    def loop():
        while not _gremlin.get("stop"):
            try:
                conn, _ = sock.accept()
            except OSError:
                break
            with conn:
                try:
                    conn.sendall(b'{"ok":false,"error":"invalid_request"}\n')
                except OSError:
                    pass

    _gremlin["sock"] = sock
    _gremlin["stop"] = False
    threading.Thread(target=loop, daemon=True).start()
    return sock.getsockname()[1]


def _shutdown_gremlin() -> None:
    _gremlin["stop"] = True
    sock = _gremlin.get("sock")
    if sock:
        try:
            socket.socket().connect(sock.getsockname())
        except OSError:
            pass
        sock.close()
        _gremlin.pop("sock", None)


def external_output_suite() -> None:
    """外部命令的输解决不开时，不能把网关带走。

    用户真机踩过：ensure_firewall_rule 用 text=True 捕 netsh 的中文报错，Python 按本地
    编码（GBK）解不动其中一个字节，解码线程炸掉、stdout 变成 None，`FIREWALL_RULE in
    None` 抛 TypeError —— gate.json 已经写好了却起不来，整个 --init 白跑一遍。
    """
    emits = ("import sys;"
             "sys.stdout.buffer.write(b'\\xff\\xa7\\xfe\\x80 bad'"
             " + b'name=qp-gate localport: 61700')")
    done = qp_gate.run_captured([sys.executable, "-c", emits], 30)
    check("解不开的字节不再抛异常，stdout 仍是 str",
          isinstance(done.stdout, str), type(done.stdout).__name__)
    check("乱码里仍能认出 ASCII 规则名与端口",
          qp_gate.FIREWALL_RULE in done.stdout and "61700" in done.stdout,
          repr(done.stdout[:80]))
    missing = qp_gate.run_captured(
        [sys.executable, "-c", "import sys; sys.exit(3)"], 30)
    check("非零退出不抛，交回调用方判断", missing.returncode == 3,
          str(missing.returncode))

    # Same family: log() sits on the request path, and serve()'s except branch
    # logs too, so a print that raises would abort an in-flight transfer.
    dead = io.StringIO()
    dead.close()
    saved, raised = sys.stdout, None
    sys.stdout = dead
    try:
        qp_gate.log("stdout 已经关掉了")
    except BaseException as exc:  # noqa: BLE001 - the check is exactly this
        raised = repr(exc)
    finally:
        sys.stdout = saved
    check("stdout 关掉时 log 不抛，正在转发的请求不会被一行日志带走",
          raised is None, str(raised))


def address_suite(tmp: Path) -> None:
    """首启那三个新函数：探测本机地址、折成 /24、把手机该填的地址说出来。"""
    check("suggest_cidr 把本机地址折成它所在的 /24",
          qp_gate.suggest_cidr("192.168.13.7") == "192.168.13.0/24")
    found = qp_gate.local_ipv4s()
    check("local_ipv4s 只给可解析的非回环 IPv4",
          all(ipaddress.ip_address(a).version == 4 and not a.startswith("127.")
              for a in found),
          str(found))

    loopback = qp_gate.Config(gate_config(tmp, 0, listen_host="127.0.0.1"), tmp)
    lines = qp_gate.phone_urls(loopback)
    check("只绑回环时横幅直说手机连不到，而不是打一个填不了的地址",
          any("连不到" in line for line in lines), str(lines))

    wide = qp_gate.Config(gate_config(tmp, 0, listen_host="0.0.0.0",
                                      listen_port=61700), tmp)
    saved = qp_gate.local_ipv4s
    qp_gate.local_ipv4s = lambda: ["192.168.13.7", "10.0.0.5"]
    try:
        lines = qp_gate.phone_urls(wide)
    finally:
        qp_gate.local_ipv4s = saved
    check("多网卡时逐条列出手机要填的地址，默认路由出口在最前",
          lines == ["手机填: http://192.168.13.7:61700",
                    "手机填: http://10.0.0.5:61700"], str(lines))
    check("横幅里不会出现 0.0.0.0 这种填不进手机的地址",
          all("0.0.0.0" not in line for line in lines), str(lines))

    path = Path(tmp) / "no-user.json"
    raw = gate_config(path, 0)
    raw.pop("username")
    raw.pop("credential")
    path.write_text(json.dumps(raw), encoding="utf-8")
    check("--show 读得动还没设账号的配置（只解析不校验）",
          qp_gate.Config.read(path).username == "")
    try:
        qp_gate.Config.load(path)
        accepted = True
    except SystemExit:
        accepted = False
    check("真正启动仍然要求账号", accepted is False)


def config_suite(tmp: Path) -> None:
    """日常改配置那条路：回车必须等于不动，改端口不许顺手把令牌作废。

    --init --force 会重生成 token_secret，拿它当"改配置"用等于每改一次端口手机就得
    重新登录一次；--edit 存在的全部意义就是把这两件事拆开。
    """
    check("parse_port 空回答保持原值", qp_gate.parse_port("", 61700) == 61700)
    check("parse_port 非数字保持原值", qp_gate.parse_port("abc", 61700) == 61700)
    check("parse_port 越界端口保持原值",
          qp_gate.parse_port("70000", 61700) == 61700
          and qp_gate.parse_port("80", 61700) == 61700)
    check("parse_port 接受自定义的合法端口", qp_gate.parse_port("8088", 61700) == 8088)

    real_input = builtins.input
    saved_ipv4s = qp_gate.local_ipv4s
    qp_gate.local_ipv4s = lambda: ["192.168.13.7"]

    def answers(values):
        queue = collections.deque(values)
        builtins.input = lambda prompt="": queue.popleft()

    try:
        answers([""])
        check("ask_cidrs 回车拿的是当前网段，不是这一刻探测到的网卡",
              qp_gate.ask_cidrs(["10.0.0.0/24"]) == ["10.0.0.0/24"])
        answers(["192.168.9.0/24"])
        check("ask_cidrs 仍然可以自定义成别的网段",
              qp_gate.ask_cidrs(["10.0.0.0/24"]) == ["192.168.9.0/24"])
        answers(["-"])
        check("ask_cidrs 输入 - 仍然表示不限网段",
              qp_gate.ask_cidrs(["10.0.0.0/24"]) == [])
        answers(["192.168.9.0/24,10.7.7.0/24", "10.8.0.0/16"])
        check("ask_cidrs 用逗号隔开多个网段（提示写的是空格）会重问，第二次填对就采纳",
              qp_gate.ask_cidrs(["10.0.0.0/24"]) == ["10.8.0.0/16"])
        answers(["192.168.13.0/33", "0.0.0.0/x", "abc"])
        try:
            qp_gate.ask_cidrs(["10.0.0.0/24"])
            refused = False
        except SystemExit:
            refused = True
        check("ask_cidrs 连着填错到上限就不出结果（调用方因此一个字都不写）", refused)
    finally:
        builtins.input = real_input

    path = Path(tmp) / "edit.json"
    raw_cfg = gate_config(path, 59999, listen_port=61700)
    raw_cfg["allow_cidrs"] = ["10.0.0.0/24"]
    path.write_text(json.dumps(raw_cfg), encoding="utf-8")
    before = json.loads(path.read_text(encoding="utf-8"))

    calls = []
    saved_probe = qp_gate.probe_upstream
    saved_firewall = qp_gate.ensure_firewall_rule
    saved_show = qp_gate.show_config
    saved_default = qp_gate.DEFAULT_CONFIG
    qp_gate.probe_upstream = lambda host, port, timeout=2.0: True
    qp_gate.ensure_firewall_rule = lambda port: calls.append(port) or True
    qp_gate.show_config = lambda config: calls.append("shown")
    try:
        answers(["n", "", "", ""])
        qp_gate.edit_config(path)
        after = json.loads(path.read_text(encoding="utf-8"))
        check("一路回车 = 配置文件一个字都不变", after == before, str(after))
        check("没改端口就不会去动防火墙", calls == ["shown"], str(calls))

        answers(["n", "61701", "-", ""])
        qp_gate.edit_config(path)
        after = json.loads(path.read_text(encoding="utf-8"))
        check("--edit 能把监听端口改成自定义值", after["listen_port"] == 61701)
        check("--edit 换端口绝不重生成 token_secret（手机不该被登出）",
              after["token_secret"] == before["token_secret"])
        check("--edit 不动登录口令", after["credential"] == before["credential"])
        check("上游端口可以从钉死改回自动发现", after["upstream_port"] == 0)
        check("演练用的 --config 改端口不动系统防火墙"
              "（README 教人拿临时文件演练，留下永久放行没人会想起来删）",
              61701 not in calls, str(calls))

        qp_gate.DEFAULT_CONFIG = path
        answers(["n", "61700", "", ""])
        qp_gate.edit_config(path)
        check("改真实配置的端口会补防火墙规则（旧规则只放行旧端口）",
              61700 in calls, str(calls))

        answers(["n", "", "59999", "-"])
        qp_gate.DEFAULT_CONFIG = Path(tmp) / "somewhere-else.json"
        qp_gate.edit_config(path)
        after = json.loads(path.read_text(encoding="utf-8"))
        check("--edit 能把网段清空成不限，同时保留没问的字段",
              after["allow_cidrs"] == [] and after["listen_port"] == 61700, str(after))

        answers(["n", "", "", "192.168.9.0/24,10.7.7.0/24", "10.7.7.0/24"])
        qp_gate.edit_config(path)
        after = json.loads(path.read_text(encoding="utf-8"))
        check("--edit 里用逗号隔开网段不会把名单悄悄清空：重问一次，落盘的是填对的那条",
              after["allow_cidrs"] == ["10.7.7.0/24"], str(after))

        untouched = path.read_text(encoding="utf-8")
        answers(["n", "", "", "abc", "def", "ghi"])
        try:
            qp_gate.edit_config(path)
            saved_nothing = False
        except SystemExit:
            saved_nothing = path.read_text(encoding="utf-8") == untouched
        check("--edit 连着填错到上限就整个不写（磁盘上还是问之前的那份）",
              saved_nothing)
    finally:
        builtins.input = real_input
        qp_gate.probe_upstream = saved_probe
        qp_gate.local_ipv4s = saved_ipv4s
        qp_gate.ensure_firewall_rule = saved_firewall
        qp_gate.show_config = saved_show
        qp_gate.DEFAULT_CONFIG = saved_default

    # start.bat 的正文只能是 ASCII（cmd 会把非 ASCII 字节解析坏），所以失败收尾和那张
    # 命令表都不写在批处理里，而是由 `--explain <分支>` 打出来。下面钉的是这两处的接缝。
    bat = (Path(__file__).resolve().parent / "start.bat").read_text(
        encoding="ascii").replace("\r\n", "\n")
    branches = [chunk.split()[0] for chunk in bat.split("--explain=")[1:]]
    said = []
    for kind in branches:
        buf = io.StringIO()
        try:
            with contextlib.redirect_stdout(buf):
                qp_gate.explain(kind)
        except SystemExit:
            continue
        said.append((kind, buf.getvalue()))
    check("start.bat 用到的每个 --explain 分支都打得出中文收尾"
          "（改了分支名忘了同步这边，用户收到的就是什么都没有的空收尾）",
          len(said) == len(set(branches)) > 1
          and all(any("\u4e00" <= c <= "\u9fff" for c in text) for _, text in said),
          str(branches))

    quiet = []
    for label in ("failed", "editfailed", "stopfailed", "noconfig", "usage"):
        body = bat.split(f"\n:{label}\n", 1)[1].split("\n:", 1)[0]
        quiet.append("--explain=" in body and "echo " not in body)
    check("四处失败收尾和那张命令表自己不再打英文正文，话全交给 qp_gate.py",
          all(quiet), str(quiet))

    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        code = qp_gate.main(["--explain=failed", "--config", str(Path(tmp) / "none.json")])
    check("--explain 在读不到配置的时候照样说话（配置坏了正是要用收尾的那一次）",
          code == 0 and "网关没能起来" in buf.getvalue())

    try:
        qp_gate.explain("no-such-branch")
        loud = False
    except SystemExit:
        loud = True
    check("--explain 收到不认识的分支名就报错，不静默地什么都不打", loud)


def firewall_suite() -> None:
    """放行成没成，只能回头看规则在不在。

    Start-Process -Verb RunAs 只负责把 netsh 拉起来：UAC 弹窗被取消、或者压根没提升
    权限，它照样返回 0。旧版把"拉起来了"当"已放行"打出去，于是手机连不上而日志里
    写着成功——这台机器上真实发生过一次。
    """
    saved_shown = qp_gate.shown_rule
    saved_run = qp_gate.run_captured
    qp_gate.shown_rule = lambda: "规则名称: qp-gate\n本地端口: 61700"
    check("规则已经覆盖这个端口时不再重复添加",
          qp_gate.firewall_rule_covers(61700)
          and not qp_gate.firewall_rule_covers(61701))

    launched = []

    def fake_run(argv, timeout):
        launched.append(argv)
        return types.SimpleNamespace(returncode=0, stdout="", stderr="")

    qp_gate.run_captured = fake_run
    qp_gate.shown_rule = lambda: "没有匹配的规则。"
    if os.name == "nt":
        check("提权进程返回 0 但规则没落地，也必须报未放行",
              qp_gate.ensure_firewall_rule(61799) is False and bool(launched))
        check("报告未放行时把可以照抄的 netsh 命令打出来",
              launched and "localport=61799" in launched[-1][-1])
        qp_gate.shown_rule = lambda: "规则名称: qp-gate\n本地端口: 61700"
        launched.clear()
        check("删除后规则还在（弹窗没批准）就不能说已删除",
              qp_gate.remove_firewall_rule() is False)
        qp_gate.shown_rule = lambda: "没有匹配的规则。"
        check("规则确实没了才说已删除", qp_gate.remove_firewall_rule() is True)
    else:
        check("非 Windows 上不动防火墙，只提示自行放行",
              qp_gate.ensure_firewall_rule(61799) is True and not launched)
    qp_gate.shown_rule = saved_shown
    qp_gate.run_captured = saved_run


LISTEN_STUB_SRC = (
    "import socket, sys, time\n"
    "s = socket.socket()\n"
    "s.bind(('127.0.0.1', int(sys.argv[1])))\n"
    "s.listen(8)\n"
    "print(s.getsockname()[1], flush=True)\n"
    "time.sleep(120)\n"
)


def _spawn_listener(tmp: Path, name: str) -> tuple:
    """起一个真在 LISTENING 的子进程，返回 (Popen, 端口)。

    必须是真子进程：--stop 读的是操作系统的连接表和进程表，本进程里 bind 一个端口既进不了
    那张表，也证明不了"撞端口时绝不动手"这条最要紧的性质。
    """
    script = tmp / name
    script.write_text(LISTEN_STUB_SRC, encoding="utf-8")
    proc = subprocess.Popen([sys.executable, str(script), "0"],
                            stdout=subprocess.PIPE, text=True, errors="replace",
                            cwd=str(tmp))
    line = proc.stdout.readline().strip()
    if not line.isdigit():
        proc.kill()
        raise RuntimeError(f"桩监听进程起不来: {line!r}")
    return proc, int(line)


def stop_suite(tmp: Path) -> None:
    """--stop 的认领与停实：只停认得出是自己的那一个，而且停了要回头看连接表。"""

    def cfg(port: int):
        path = tmp / f"stop-{port}.json"
        return qp_gate.Config(gate_config(path, 0, listen_port=port), path)

    free = socket.socket()
    free.bind(("127.0.0.1", 0))
    free_port = free.getsockname()[1]
    free.close()
    check("没人监听的端口上 --stop 说「本来就没在跑」，不当成失败",
          qp_gate.stop_gate(cfg(free_port)) is True)

    mine, my_port = _spawn_listener(tmp, "qp_gate_stub.py")
    try:
        check("listening_pids 从系统连接表里认出那个监听进程",
              qp_gate.listening_pids(my_port) == [str(mine.pid)],
              f"{qp_gate.listening_pids(my_port)} != [{mine.pid}]")
        allowed, why = qp_gate.stop_claim(str(mine.pid))
        check("命令行里带 qp_gate 的进程被认领", allowed, why)
        check("--stop 返回成功", qp_gate.stop_gate(cfg(my_port)) is True)
        try:
            mine.wait(timeout=10)
            gone = True
        except subprocess.TimeoutExpired:
            gone = False
        check("说停了就得真的停了（不看返回值，看进程）", gone, "还在跑")
        check("停完连接表里再没有这个端口",
              qp_gate.listening_pids(my_port) == [],
              str(qp_gate.listening_pids(my_port)))
    finally:
        mine.kill()
        mine.wait()

    stranger, its_port = _spawn_listener(tmp, "other_service.py")
    try:
        allowed, why = qp_gate.stop_claim(str(stranger.pid))
        check("撞端口的外来进程不被认领，哪怕它同样是 python", not allowed, why)
        check("--stop 拒绝动它就返回失败", qp_gate.stop_gate(cfg(its_port)) is False)
        check("被拒绝的那个必须还活着——不越权就是这条命令的全部意义",
              stranger.poll() is None)
    finally:
        stranger.kill()
        stranger.wait()


def main() -> int:
    holder = {}

    # 隔离到临时工作目录：否则上游发现会去读真实的 ~/.qwenpaw/config.json，
    # 一个本该打桩上游的请求就会被静默转给用户真跑着的桌面端。
    # 两个目录都走 TemporaryDirectory：这里此前用的是 mkdtemp，每跑一次自检就在 %TEMP%
    # 留下一个 qp-gate-selftest-* 没人收（这台机器上数出来 34 个）。
    async def serve_all(stub_ready: concurrent.futures.Future,
                        gate_ready: concurrent.futures.Future):
        stub = await asyncio.start_server(stub_serve, "127.0.0.1", 0)
        stub_port = stub.sockets[0].getsockname()[1]
        path = Path(holder["tmp"]) / "gate.json"
        config = qp_gate.Config(gate_config(path, stub_port), path)
        gate = qp_gate.Gate(config)
        server = await asyncio.start_server(gate.serve, "127.0.0.1", 0)
        stub_ready.set_result(stub_port)
        gate_ready.set_result(server.sockets[0].getsockname()[1])
        async with stub, server:
            await asyncio.sleep(120)

    with tempfile.TemporaryDirectory() as tmpdir, \
            tempfile.TemporaryDirectory(prefix="qp-gate-selftest-") as workdir:
        os.environ["QWENPAW_WORKING_DIR"] = workdir
        holder["tmp"] = tmpdir
        stub_fut = concurrent.futures.Future()
        gate_fut = concurrent.futures.Future()
        thread = threading.Thread(target=lambda: asyncio.run(
            serve_all(stub_fut, gate_fut)), daemon=True)
        thread.start()
        stub_port = stub_fut.result(timeout=10)
        gate_port = gate_fut.result(timeout=10)
        print(f"桩上游 :{stub_port}   守门代理 :{gate_port}")
        with section("主流程：接管鉴权面 / 令牌 / 限流 / 转发 / SSE / 大 body / 畸形报文"):
            suite(gate_port)
        with section("放行网段"):
            cidr_suite(Path(tmpdir) / "cidr.json", stub_port)
        with section("上游缺席"):
            upstream_missing_suite(Path(tmpdir) / "dead.json", stub_port)
        with section("上游自动发现"):
            discovery_suite(stub_port)
        with section("外部命令输出解码"):
            external_output_suite()
        with section("本机地址与横幅"):
            address_suite(Path(tmpdir))
        with section("配置读写 --edit", mute=True):
            config_suite(Path(tmpdir))
        with section("防火墙规则"):
            firewall_suite()
        with section("--stop 的认领"):
            stop_suite(Path(tmpdir))

    total = len(RESULTS)
    passed = sum(1 for _n, ok in RESULTS if ok)
    print(f"\n{passed}/{total} PASS")
    for title, start, end, logs in SECTIONS:
        failed = [name for name, ok in RESULTS[start:end] if not ok]
        if not failed:
            continue
        print(f"\n「{title}」失败 {len(failed)} 条:")
        for name in failed:
            print(f"  {name}")
        if logs:
            print("  这一节守门代理自己打过的行:")
            for line in logs:
                print(f"    {line}")
    return 0 if passed == total else 1


if __name__ == "__main__":
    sys.exit(main())
