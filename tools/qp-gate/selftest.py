#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""qp-gate 自检：安全边界 + 流式转发。

自带一个桩上游（JSON / 慢速 SSE / 大请求体 / 二进制），因此不依赖桌面端，在任何
机器上都能跑，也不会误碰用户真实的 ~/.qwenpaw 工作目录。

    python selftest.py
"""
from __future__ import annotations

import asyncio
import concurrent.futures
import hashlib
import http.client
import json
import os
import random
import socket
import sys
import tempfile
import threading
import time
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
    print(line, flush=True)


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


def main() -> int:
    holder = {}

    # 隔离到临时工作目录：否则上游发现会去读真实的 ~/.qwenpaw/config.json，
    # 一个本该打桩上游的请求就会被静默转给用户真跑着的桌面端。
    os.environ["QWENPAW_WORKING_DIR"] = tempfile.mkdtemp(prefix="qp-gate-selftest-")

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

    with tempfile.TemporaryDirectory() as tmpdir:
        holder["tmp"] = tmpdir
        stub_fut = concurrent.futures.Future()
        gate_fut = concurrent.futures.Future()
        thread = threading.Thread(target=lambda: asyncio.run(
            serve_all(stub_fut, gate_fut)), daemon=True)
        thread.start()
        stub_port = stub_fut.result(timeout=10)
        gate_port = gate_fut.result(timeout=10)
        print(f"stub={stub_port} gate={gate_port}")
        suite(gate_port)
        cidr_suite(Path(tmpdir) / "cidr.json", stub_port)
        upstream_missing_suite(Path(tmpdir) / "dead.json", stub_port)
        discovery_suite(stub_port)

    total = len(RESULTS)
    passed = sum(1 for _n, ok in RESULTS if ok)
    print(f"\n{passed}/{total} PASS")
    for name, ok in RESULTS:
        if not ok:
            print(f"  FAIL {name}")
    return 0 if passed == total else 1


if __name__ == "__main__":
    sys.exit(main())
