#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""qp-gate: 让局域网里的手机连上只绑回环的 QwenPaw 桌面端后端。

桌面端零改动：后端继续听 127.0.0.1:<随机端口>，本进程听 0.0.0.0:<对外端口>，
自己扮演 QwenPaw 的鉴权面（/api/auth/status 与 /api/auth/login），其余路由必须
带上本进程签发的 Bearer 令牌才转发。

为什么门禁只能做在这里：转发到后端时源地址是 127.0.0.1，而 QwenPaw 的鉴权按
客户端 IP 免检（security.allow_no_auth_hosts 默认含回环），所以后端那一层在这
个拓扑下根本不参与。指望"后端开鉴权 + 代理只转发"是假安全。

用法:
    python qp_gate.py --init            首启：生成 gate.json，交互设置账号、口令与放行网段
    python qp_gate.py                   启动
    python qp_gate.py --edit            日常改配置：回车保持原样，可改口令/两个端口/放行网段
    python qp_gate.py --show            打印当前生效配置连每一项的含义后退出
    python qp_gate.py --set-password    换口令
    python qp_gate.py --discover        只打印探测到的上游后退出

    任意一条都可以带 --config <路径> 指到临时配置文件；首启演练请用它的临时路径，
    覆盖真实 gate.json 会重生成 token_secret，已签发的令牌全部作废。
"""
from __future__ import annotations

import argparse
import asyncio
import base64
import binascii
import getpass
import hashlib
import hmac
import ipaddress
import json
import os
import re
import secrets
import socket
import subprocess
import sys
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEFAULT_CONFIG = HERE / "gate.json"

# 对外监听的推荐端口：手机里填的就是它，防火墙规则里的 localport 也是它。
# 只在上层网关占用时才需要改，所以向导把它当默认值，而不是替人钉死。
RECOMMENDED_LISTEN_PORT = 61700

# 口令只存 PBKDF2 派生值，明文口令不落盘、不进日志。
PBKDF2_ITERATIONS = 200_000
# 一个请求头读不完就判定为慢速占用，避免守门进程被挂死。
HEAD_READ_TIMEOUT = 30.0
MAX_HEAD_BYTES = 128 * 1024
# 上游端口会随桌面端重启漂移，缓存一会儿，失败时立刻重探。
UPSTREAM_CACHE_SECONDS = 15.0
# 只在这些进程名下找监听端口，命中后还要用 /api/auth/status 的形状确认。
UPSTREAM_PROCESS_HINT = re.compile(r"qwenpaw|python|uvicorn", re.IGNORECASE)
# 这些方法可能带请求体；没有 Content-Length 时要按分块流处理。
BODY_METHODS = ("POST", "PUT", "PATCH")


def log(message: str) -> None:
    """往控制台打一行；控制台没了也绝不抛。

    这条在请求路径上被调用，而 serve() 的 except 分支也要 log()：一个已经关掉的
    stdout（窗口被强杀、被重定向到已关闭的句柄、以 pythonw 起）如果让 print 抛出去，
    就会把正在途的转发一起带走——用户看到的症状是"手机传大附件传到一半断了"，
    而真正的原因是一行日志没地方写。
    """
    try:
        print(f"[qp-gate {time.strftime('%H:%M:%S')}] {message}", flush=True)
    except (OSError, ValueError, RuntimeError):
        pass


def redact(path: str) -> str:
    """Keep query strings out of the log; a preview URL can carry a token."""
    return path.split("?", 1)[0]


def hint(*args: str) -> str:
    """一条能原样粘贴的命令。让用户先 cd 到本目录再敲相对路径，等于没说。"""
    return " ".join([f'"{sys.executable}"', f'"{Path(__file__).resolve()}"', *args])


def run_captured(argv: list, timeout: float) -> subprocess.CompletedProcess:
    """跑外部命令，自己把输出解成文本。

    绝不用 text=True：Windows 上 Python 拿 GBK 去解 netsh / tasklist 的输出，一句中文
    报错里的非法字节就能炸掉解码线程——stdout 变成 None 或者直接抛 UnicodeDecodeError，
    两者都不在调用方的 except 覆盖里，会把已经配好的网关带走。这里只用 errors="replace"
    解，调用方检索的全是 ASCII（规则名、端口号、PID），解出来的乱码无害。
    """
    done = subprocess.run(argv, capture_output=True, timeout=timeout)
    done.stdout = (done.stdout or b"").decode("utf-8", "replace")
    done.stderr = (done.stderr or b"").decode("utf-8", "replace")
    return done


# ---------------------------------------------------------------- 凭据与令牌


def hash_password(password: str) -> str:
    salt = secrets.token_bytes(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt,
                                 PBKDF2_ITERATIONS)
    return (f"pbkdf2_sha256${PBKDF2_ITERATIONS}${salt.hex()}${digest.hex()}")


def verify_password(password: str, credential: str) -> bool:
    try:
        scheme, iterations, salt_hex, digest_hex = credential.split("$")
        if scheme != "pbkdf2_sha256":
            return False
        expected = bytes.fromhex(digest_hex)
        actual = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"),
                                     bytes.fromhex(salt_hex), int(iterations))
    except (ValueError, TypeError):
        return False
    return hmac.compare_digest(expected, actual)


def b64e(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).decode("ascii").rstrip("=")


def b64d(text: str) -> bytes:
    return base64.urlsafe_b64decode(text + "=" * (-len(text) % 4))


class Tokens:
    """自签发的不透明令牌：payload 走 base64url，签名走 HMAC-SHA256。"""

    def __init__(self, secret_hex: str) -> None:
        self._secret = bytes.fromhex(secret_hex)

    def sign(self, payload: dict) -> str:
        body = b64e(json.dumps(payload, separators=(",", ":")).encode("utf-8"))
        return f"{body}.{b64e(self._mac(body.encode('ascii')))}"

    def issue(self, username: str, ttl_seconds: int) -> str:
        if ttl_seconds == 0:
            expiry = 0  # 0 表示永久：手机端登录页不会遇到"过期后只报错不重登"。
        else:
            expiry = int(time.time()) + ttl_seconds  # 负值即已过期，自检用得上。
        return self.sign({"u": username, "exp": expiry, "iat": int(time.time())})

    def check(self, token: str) -> str | None:
        """返回令牌归属的用户名；无效或过期返回 None。"""
        body, _, signature = token.partition(".")
        if not body or not signature:
            return None
        try:
            if not hmac.compare_digest(b64e(self._mac(body.encode("ascii"))),
                                       signature):
                return None
            payload = json.loads(b64d(body))
        except (ValueError, TypeError, binascii.Error):
            return None
        if not isinstance(payload, dict):
            return None
        username = payload.get("u")
        expiry = payload.get("exp")
        if not isinstance(username, str) or not isinstance(expiry, int):
            return None
        if expiry and expiry < time.time():
            return None
        return username

    def _mac(self, data: bytes) -> bytes:
        return hmac.new(self._secret, data, hashlib.sha256).digest()


# ---------------------------------------------------------------- 配置


class Config:
    def __init__(self, raw: dict, path: Path) -> None:
        self.path = path
        self.listen_host: str = str(raw.get("listen_host", "0.0.0.0"))
        self.listen_port: int = int(raw.get("listen_port", RECOMMENDED_LISTEN_PORT))
        self.upstream_host: str = str(raw.get("upstream_host", "127.0.0.1"))
        self.upstream_port: int = int(raw.get("upstream_port", 0))
        self.username: str = str(raw.get("username", ""))
        self.credential: str = str(raw.get("credential", ""))
        self.token_secret: str = str(raw.get("token_secret", ""))
        self.token_ttl_seconds: int = int(raw.get("token_ttl_seconds", 0))
        if self.token_ttl_seconds < 0:
            log("WARN token_ttl_seconds 为负数会得到立刻过期的令牌，按永久(0)处理")
            self.token_ttl_seconds = 0
        self.max_connections: int = int(raw.get("max_connections", 64))
        self.login_max_failures: int = int(raw.get("login_max_failures", 8))
        self.login_window_seconds: int = int(raw.get("login_window_seconds", 60))
        self.allow_cidrs: list = list(raw.get("allow_cidrs", []))
        self._networks = []
        for cidr in self.allow_cidrs:
            try:
                self._networks.append(ipaddress.ip_network(cidr, strict=False))
            except ValueError:
                log(f"WARN 忽略非法 allow_cidrs 条目: {cidr}")
        self._raw = raw

    def permits(self, ip: str) -> bool:
        if not self._networks:
            return True
        try:
            address = ipaddress.ip_address(ip)
        except ValueError:
            return False
        return any(address in network for network in self._networks)

    def save(self) -> None:
        self._raw.update({
            "listen_host": self.listen_host,
            "listen_port": self.listen_port,
            "upstream_host": self.upstream_host,
            "upstream_port": self.upstream_port,
            "username": self.username,
            "credential": self.credential,
            "token_secret": self.token_secret,
            "token_ttl_seconds": self.token_ttl_seconds,
            "max_connections": self.max_connections,
            "login_max_failures": self.login_max_failures,
            "login_window_seconds": self.login_window_seconds,
            "allow_cidrs": self.allow_cidrs,
        })
        text = json.dumps(self._raw, indent=2, ensure_ascii=False) + "\n"
        self.path.write_text(text, encoding="utf-8")
        try:
            os.chmod(self.path, 0o600)
        except OSError:
            pass

    @classmethod
    def read(cls, path: Path) -> "Config":
        """只解析不校验：--show 在账号还没设好的时候也该打得开。"""
        if not path.exists():
            raise SystemExit(f"找不到配置 {path}，先跑: {hint('--init')}")
        try:
            raw = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError) as exc:
            raise SystemExit(f"配置 {path} 读不了: {exc}") from exc
        return cls(raw, path)

    @classmethod
    def load(cls, path: Path) -> "Config":
        config = cls.read(path)
        if not config.username or not config.credential:
            raise SystemExit(f"{path} 里没有账号或口令，跑: {hint('--set-password')}")
        if not config.token_secret:
            config.token_secret = secrets.token_hex(32)
            config.save()
        return config


# ---------------------------------------------------------------- 本机地址


def route_ipv4() -> str | None:
    """默认路由出口上的本机 IPv4。

    UDP connect 一个数据报都不发，只是让内核挑一条路由，所以没联网也问得出现役网卡。
    这比 getaddrinfo(主机名) 可靠——主机名没在 hosts 里登记时后者只会给出 127.0.0.1。
    """
    probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        probe.connect(("8.8.8.8", 53))
        return str(probe.getsockname()[0])
    except OSError:
        return None
    finally:
        probe.close()


def local_ipv4s() -> list:
    """本机可能被局域网里其它设备看到的 IPv4，默认路由出口排在最前。

    多网卡时逐条列出、不替人猜：挑错网段比多看两行麻烦得多。
    """
    found: list = []
    primary = route_ipv4()
    if primary:
        found.append(primary)
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            address = str(info[4][0])
            if address not in found:
                found.append(address)
    except OSError:
        pass
    return [a for a in found if not a.startswith("127.")]


def suggest_cidr(ip: str) -> str:
    """把本机 IPv4 折成它所在的 /24 —— 家用局域网基本都是 /24。"""
    return ip.rsplit(".", 1)[0] + ".0/24"


# ---------------------------------------------------------------- 上游发现


def probe_upstream(host: str, port: int, timeout: float = 2.0) -> bool:
    """只有回环上真有一个 QwenPaw 形状的 /api/auth/status 才算命中。

    这里什么都可能撞上：别的协议的服务、TLS 端口、上来就断连的守门进程。任何异常
    都只意味着"这不是 QwenPaw"，绝不能冒泡出去把正在转发的连接一起弄死。
    """
    url = f"http://{host}:{port}/api/auth/status"
    request = urllib.request.Request(url, headers={"User-Agent": "qp-gate"})
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            body = json.loads(response.read().decode("utf-8"))
    except Exception:
        return False
    return isinstance(body, dict) and "enabled" in body


def working_dir() -> Path:
    return Path(os.path.expanduser(os.environ.get("QWENPAW_WORKING_DIR", "~/.qwenpaw")))


def config_candidates() -> list:
    ports: list = []
    wd = working_dir()
    try:
        cfg = json.loads((wd / "config.json").read_text(encoding="utf-8"))
        last_api = cfg.get("last_api") or {}
        for key in ("port",):
            value = last_api.get(key)
            if isinstance(value, int):
                ports.append(value)
    except (OSError, ValueError, TypeError):
        pass
    for name in ("desktop_port", "port"):
        try:
            value = int((wd / name).read_text(encoding="utf-8").strip())
            if 1024 <= value <= 65535:
                ports.append(value)
        except (OSError, ValueError):
            pass
    return ports


def listening_loopback_ports() -> list:
    """从系统连接表里挑出候选进程占着的回环端口。"""
    ports: set = set()
    try:
        if os.name == "nt":
            out = run_captured(["netstat", "-ano", "-p", "tcp"], 10).stdout
            rows = re.findall(
                r"TCP\s+(127\.0\.0\.1|\[::1\]):(\d+)\s+\S+\s+LISTENING\s+(\d+)", out)
            pids = {row[2] for row in rows}
            names = _windows_process_names(pids)
            for _addr, port, pid in rows:
                name = names.get(pid, "")
                # tasklist can fail or lag behind; an unknown owner still gets
                # probed, because probe_upstream() is the real discriminator.
                if not name or UPSTREAM_PROCESS_HINT.search(name):
                    ports.add(int(port))
        else:
            out = run_captured(["ss", "-ltnp"], 10).stdout
            for match in re.finditer(r":(\d+)\s.*?pid=(\d+)", out):
                ports.add(int(match.group(1)))
    except (OSError, subprocess.SubprocessError, ValueError):
        pass
    return sorted(ports)


def _windows_process_names(pids: set) -> dict:
    names: dict = {}
    if not pids:
        return names
    try:
        out = run_captured(["tasklist", "/FO", "CSV", "/NH"], 10).stdout
        for line in out.splitlines():
            fields = re.findall(r'"([^"]*)"', line)
            if len(fields) >= 2 and fields[1].isdigit() and fields[1] in pids:
                names[fields[1]] = fields[0]
    except (OSError, subprocess.SubprocessError):
        pass
    return names


class Upstream:
    """桌面端重启后端口会换，所以每次失效都要能重新发现。

    发现过程要发真实 HTTP 探测，绝不能在主循环里做：那会把正在推的 SSE 一起卡住。
    """

    def __init__(self, config: Config) -> None:
        self.config = config
        self.host = config.upstream_host
        self.port = config.upstream_port
        self._checked_at = 0.0
        self._scan = None

    def candidates(self) -> list:
        seen, ordered = set(), []
        if self.port:
            ordered.append(self.port)
        for port in config_candidates():
            if port not in seen and port != self.config.listen_port:
                seen.add(port)
                ordered.append(port)
        for port in listening_loopback_ports():
            if port not in seen and port != self.config.listen_port:
                seen.add(port)
                ordered.append(port)
        return ordered

    def resolve(self) -> int | None:
        now = time.time()
        if self.port and now - self._checked_at < UPSTREAM_CACHE_SECONDS:
            return self.port
        ports = self.candidates()
        found = None
        if ports:
            # 并发探测，但按优先级取第一个命中的：配置的端口优先于猜出来的。
            with ThreadPoolExecutor(max_workers=min(16, len(ports))) as pool:
                hits = list(pool.map(lambda p: probe_upstream(self.host, p), ports))
            for port, hit in zip(ports, hits):
                if hit:
                    found = port
                    break
        self._checked_at = time.time()
        if found is None:
            return None
        if found != self.port:
            log(f"上游已定位: http://{self.host}:{found}")
        self.port = found
        return found

    async def aresolve(self) -> int | None:
        """给转发路径用的非阻塞版本；并发请求共用同一次扫描。"""
        if self.port and time.time() - self._checked_at < UPSTREAM_CACHE_SECONDS:
            return self.port
        if self._scan is None:
            loop = asyncio.get_running_loop()
            self._scan = loop.run_in_executor(None, self.resolve)
        try:
            return await asyncio.shield(self._scan)
        finally:
            if self._scan and self._scan.done():
                self._scan = None

    def invalidate(self) -> None:
        self._checked_at = 0.0


# ---------------------------------------------------------------- HTTP 原语


def http_response(status: int, reason: str, payload: dict) -> bytes:
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    head = (
        f"HTTP/1.1 {status} {reason}\r\n"
        "Content-Type: application/json; charset=utf-8\r\n"
        f"Content-Length: {len(body)}\r\n"
        "Connection: close\r\n"
        "\r\n"
    ).encode("ascii")
    return head + body


def parse_head(raw: bytes) -> tuple | None:
    """返回 (请求行, 头列表, 方法, 路径, 头字典)；畸形请求返回 None。"""
    try:
        text = raw.decode("latin-1")
    except UnicodeDecodeError:
        return None
    lines = text.split("\r\n")
    if len(lines) < 2 or not lines[0]:
        return None
    parts = lines[0].split(" ")
    if len(parts) < 3:
        return None
    method, path = parts[0].upper(), parts[1]
    if not path.startswith("/"):
        # Absolute-form ("GET http://host/api HTTP/1.1") and CONNECT would let a
        # client skip our /api/auth rules or tunnel to another host.
        return None
    headers: list = []
    for line in lines[1:]:
        if not line:
            break
        name, sep, value = line.partition(":")
        if not sep:
            return None
        headers.append((name.strip(), value.strip()))
    fields = {name.lower(): value for name, value in headers}
    return lines[0], headers, method, path, fields


def rebuild_head(request_line: str, headers: list) -> bytes:
    """逐字节保留原请求，只把 Connection 改成 close。

    上游会在响应结束后继续等下一个请求，而我们按"一问一答"转发；不关连接就等不
    到 EOF，普通请求会挂成超时。SSE 不受影响，它本来就是服务端主动结束。
    """
    kept = [(name, value) for name, value in headers
            if name.lower() != "connection"]
    kept.append(("Connection", "close"))
    lines = [request_line] + [f"{name}: {value}" for name, value in kept]
    return ("\r\n".join(lines) + "\r\n\r\n").encode("latin-1")


# ---------------------------------------------------------------- 守门代理


class Gate:
    def __init__(self, config: Config) -> None:
        self.config = config
        self.tokens = Tokens(config.token_secret)
        self.upstream = Upstream(config)
        self.active = 0
        self.failures: dict = {}

    # -- 鉴权面（本进程自己实现，绝不转发给上游）

    def owns(self, path: str) -> bool:
        return redact(path) == "/api/auth" or redact(path).startswith("/api/auth/")

    def handle_auth(self, method: str, path: str, fields: dict,
                    body: bytes) -> bytes:
        clean = redact(path)
        if clean == "/api/auth/status":
            # 手机端 AppStore.signIn 先看这里；enabled=false 时它根本不会登录。
            return http_response(200, "OK", {"enabled": True, "has_users": True})
        if clean == "/api/auth/verify":
            username = self.caller(fields)
            if username is None:
                return http_response(401, "Unauthorized",
                                     {"detail": "Invalid or expired token"})
            return http_response(200, "OK", {"valid": True, "username": username})
        if clean == "/api/auth/login" and method == "POST":
            return self.handle_login(fields, body)
        if clean.startswith("/api/auth/"):
            # register / update-profile / revoke-* 都留给桌面端本机用：局域网里
            # 任何访客都不该能在别人机器上建管理员账号。
            return http_response(403, "Forbidden",
                                 {"detail": "此认证端点由守门代理接管，仅限本机"})
        return http_response(404, "Not Found", {"detail": "not found"})

    def handle_login(self, fields: dict, body: bytes) -> bytes:
        ip = fields.get("_client", "")
        if self.rate_limited(ip):
            return http_response(429, "Too Many Requests",
                                 {"detail": "登录尝试过于频繁，稍后再试"})
        try:
            payload = json.loads(body.decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            payload = {}
        username = str(payload.get("username", "")) if isinstance(payload, dict) else ""
        password = str(payload.get("password", "")) if isinstance(payload, dict) else ""
        if not self.config.username or username != self.config.username or \
                not verify_password(password, self.config.credential):
            self.record_failure(ip)
            return http_response(401, "Unauthorized",
                                 {"detail": "用户名或密码错误"})
        self.failures.pop(ip, None)
        requested = payload.get("expires_in") if isinstance(payload, dict) else None
        ttl = self.config.token_ttl_seconds
        if isinstance(requested, (int, float)) and requested <= 0:
            ttl = 0
        token = self.tokens.issue(username, int(ttl))
        log(f"登录成功 user={username} from={ip}")
        return http_response(200, "OK", {"token": token, "username": username})

    def caller(self, fields: dict) -> str | None:
        header = fields.get("authorization", "")
        if not header.startswith("Bearer "):
            return None
        return self.tokens.check(header[7:].strip())

    def record_failure(self, ip: str) -> None:
        window = self.config.login_window_seconds
        stamp = time.time()
        hits = [hit for hit in self.failures.get(ip, []) if stamp - hit < window]
        hits.append(stamp)
        self.failures[ip] = hits

    def rate_limited(self, ip: str) -> bool:
        window = self.config.login_window_seconds
        stamp = time.time()
        hits = [hit for hit in self.failures.get(ip, []) if stamp - hit < window]
        self.failures[ip] = hits
        return len(hits) >= self.config.login_max_failures

    # -- 转发

    async def hangup(self, reader, writer, payload: bytes) -> None:
        """写完本地响应再收线。

        Windows 上 socket 里还留着未读的客户端字节时 close 会发 RST，把刚写进去的
        响应一起毁掉——手机端看到的就成了"连接被中止"，而不是 401/403/502。
        """
        writer.write(payload)
        try:
            await writer.drain()
        except ConnectionError:
            return
        while True:
            try:
                got = await asyncio.wait_for(reader.read(64 * 1024), timeout=0.2)
            except (asyncio.TimeoutError, ConnectionError):
                break
            if not got:
                break
        try:
            writer.close()
        except ConnectionError:
            pass

    async def serve(self, reader, writer) -> None:
        peer = writer.get_extra_info("peername")
        ip = peer[0] if peer else "?"
        if not self.config.permits(ip):
            # 这是整个守门代理唯一一处沉默的拒绝：本地应答、401、502 全都带着
            # from=<ip>，只有网段拒绝打完就挂线。第一次装的人因此既不知道为什么被拒，
            # 也看不到该往 allow_cidrs 里填哪个地址——手机自己不知道自己的局域网 IP。
            log(f"403 拒绝 from={ip}：不在放行网段内（当前 allow_cidrs="
                f"{', '.join(self.config.allow_cidrs) or '空'}）。要放行这台设备，"
                f"把它的网段加进 {self.config.path} 再重启守门代理")
            await self.hangup(reader, writer, http_response(
                403, "Forbidden", {"detail": "该地址不在允许网段内"}))
            return
        if self.active >= self.config.max_connections:
            await self.hangup(reader, writer, http_response(
                503, "Service Unavailable", {"detail": "守门代理连接数已满"}))
            return
        self.active += 1
        try:
            await self.relays(reader, writer, ip)
        except (ConnectionError, asyncio.CancelledError):
            pass
        except Exception as exc:  # 守门进程不能因为一个坏请求就退出
            log(f"ERR 连接异常 from={ip}: {type(exc).__name__}: {exc}")
        finally:
            self.active -= 1
            try:
                writer.close()
            except Exception:
                pass

    async def relays(self, reader, writer, ip: str) -> None:
        try:
            raw = await asyncio.wait_for(reader.readuntil(b"\r\n\r\n"),
                                         timeout=HEAD_READ_TIMEOUT)
        except asyncio.LimitOverrunError:
            # Header is larger than the stream limit; the bytes stay buffered, so
            # the only safe answer is to refuse and hang up.
            await self.hangup(reader, writer, http_response(
                431, "Request Header Fields Too Large", {"detail": "请求头过大"}))
            return
        except (asyncio.IncompleteReadError, asyncio.TimeoutError, ConnectionError):
            return
        parsed = parse_head(raw)
        if parsed is None:
            await self.hangup(reader, writer, http_response(
                400, "Bad Request", {"detail": "畸形请求行或请求路径"}))
            return
        request_line, headers, method, path, fields = parsed
        fields["_client"] = ip

        if self.owns(path):
            body = await self.read_body(reader, fields)
            await self.hangup(reader, writer,
                              self.handle_auth(method, path, fields, body))
            log(f"{method} {redact(path)} -> 本地应答 from={ip}")
            return

        username = self.caller(fields)
        if username is None:
            await self.hangup(reader, writer, http_response(
                401, "Unauthorized", {"detail": "缺少或无效的身份验证令牌"}))
            log(f"{method} {redact(path)} -> 401 from={ip}")
            return

        port = await self.upstream.aresolve()
        if port is None:
            await self.hangup(reader, writer, http_response(
                502, "Bad Gateway", {"detail": "本机没有发现运行中的 QwenPaw 后端，"
                                              "请先启动桌面端再试"}))
            log(f"{method} {redact(path)} -> 502 上游缺失 from={ip}")
            return

        forward = rebuild_head(request_line, headers + [
            ("X-Forwarded-For", ip),
            ("X-Forwarded-Proto", "http"),
        ])
        try:
            up_reader, up_writer = await asyncio.open_connection(
                self.upstream.host, port)
        except OSError as exc:
            self.upstream.invalidate()
            await self.hangup(reader, writer, http_response(
                502, "Bad Gateway", {"detail": f"上游不可达: {exc}"}))
            log(f"{method} {redact(path)} -> 502 from={ip}")
            return

        up_writer.write(forward)
        await up_writer.drain()
        remaining = self.body_remaining(fields)
        if remaining is None:
            if method in BODY_METHODS:
                # 分块请求体（无 Content-Length）等不到结尾：双向并发搬运，否则
                # 客户端在等响应、我们在等请求体结束，两边一起挂住。谁先结束就
                # 取消另一边，连接才不会悬着。
                mover = asyncio.ensure_future(self.pump(reader, up_writer, None))
                backer = asyncio.ensure_future(self.pump_back(up_reader, writer))
                _done, pending = await asyncio.wait((mover, backer),
                                                    return_when=asyncio.FIRST_COMPLETED)
                for task in pending:
                    task.cancel()
                await asyncio.gather(*pending, return_exceptions=True)
            else:
                # GET/HEAD/DELETE 没有请求体，读了只会等到一个永远不来的 EOF。
                await self.pump_back(up_reader, writer)
        else:
            await self.pump(reader, up_writer, remaining)
            await self.pump_back(up_reader, writer)
        for close in (up_writer, writer):
            try:
                close.close()
            except Exception:
                pass
        log(f"{method} {redact(path)} -> 转发 {self.upstream.host}:{port} "
            f"user={username} from={ip}")

    async def read_body(self, reader, fields: dict) -> bytes:
        length = fields.get("content-length")
        if not length:
            return b""
        try:
            size = int(length)
        except ValueError:
            return b""
        if size <= 0 or size > MAX_HEAD_BYTES:
            return b""
        try:
            return await asyncio.wait_for(reader.readexactly(size),
                                          timeout=HEAD_READ_TIMEOUT)
        except (asyncio.IncompleteReadError, asyncio.TimeoutError, ConnectionError):
            return b""

    async def pump(self, reader, up_writer, remaining: int | None) -> None:
        """把请求体原样推给上游，不聚合进内存（附件有 50MB 级别）。"""
        while True:
            try:
                chunk = await reader.read(64 * 1024)
            except (ConnectionError, asyncio.IncompleteReadError):
                break
            if not chunk:
                break
            up_writer.write(chunk)
            await up_writer.drain()
            if remaining is not None:
                remaining -= len(chunk)
                if remaining <= 0:
                    break

    async def pump_back(self, up_reader, writer) -> None:
        """上游响应逐块回吐：SSE 靠这个才不缓冲。"""
        while True:
            try:
                chunk = await up_reader.read(64 * 1024)
            except (ConnectionError, asyncio.IncompleteReadError):
                break
            if not chunk:
                break
            writer.write(chunk)
            await writer.drain()

    @staticmethod
    def body_remaining(fields: dict) -> int | None:
        length = fields.get("content-length")
        if length:
            try:
                return int(length)
            except ValueError:
                return None
        return None


# ---------------------------------------------------------------- 入口


FIREWALL_RULE = "qp-gate"
LOOPBACK_HOSTS = ("127.0.0.1", "localhost", "::1")


def phone_urls(config: Config) -> list:
    """手机上真正要填的那几行地址。

    横幅此前只打 `0.0.0.0:61700` 和回环上游，两个都不能往手机里填：0.0.0.0 不是
    一个地址，回环上游手机够不着。而"猜错网段"比"多列几行"更浪费时间，所以多网卡
    时逐条列出，让人自己挑对的那个。
    """
    if config.listen_host in LOOPBACK_HOSTS:
        return [f"listen_host={config.listen_host} 只绑回环，局域网里的手机连不到；"
                "要让手机连就把它改成 0.0.0.0"]
    addresses = local_ipv4s()
    if not addresses:
        return [f"没探测到本机局域网 IPv4：确认手机与本机同网段后，"
                f"手机填 http://<本机局域网地址>:{config.listen_port}"]
    return [f"手机填: http://{a}:{config.listen_port}" for a in addresses]


def shown_rule() -> str:
    """本工具那条规则的原文输出。规则不存在时 netsh 打的是"没有匹配的规则"。"""
    try:
        return run_captured(["netsh", "advfirewall", "firewall", "show", "rule",
                             f"name={FIREWALL_RULE}"], 15).stdout
    except (OSError, subprocess.SubprocessError, ValueError):
        return ""


def firewall_rule_covers(port: int) -> bool:
    shown = shown_rule()
    return FIREWALL_RULE in shown and str(port) in shown


def ensure_firewall_rule(port: int) -> bool:
    """Windows 默认拦入站，第一次监听必须有规则；没有它手机端只会超时。"""
    if os.name != "nt":
        log(f"非 Windows，请自行放行 TCP {port}（ufw/firewalld）")
        return True
    if firewall_rule_covers(port):
        log(f"防火墙规则已存在（TCP {port} 入站放行）")
        return True
    args = (f"advfirewall firewall add rule name={FIREWALL_RULE} dir=in "
            f"action=allow protocol=tcp localport={port}")
    script = (f"Start-Process -FilePath netsh -Verb RunAs "
              f"-ArgumentList '{args}' -WindowStyle Hidden")
    try:
        done = run_captured(["powershell", "-NoProfile", "-ExecutionPolicy",
                             "Bypass", "-Command", script], 120)
    except (OSError, subprocess.SubprocessError, ValueError) as exc:
        log(f"ERR 无法调用防火墙命令: {exc}")
        return False
    # Start-Process 只负责把 netsh 拉起来：弹窗被取消、或者根本没有提升权限，它照样
    # 返回 0。此前这里把"拉起来了"当成"已放行"打出去，用户看到的是一句已放行而手机
    # 仍然连不上——所以必须回头看规则到底落没落。
    if done.returncode != 0 or not waited_for_rule(port):
        log(f"未放行 TCP {port}：弹窗没批准或权限不够（不是已放行）。请手动用管理员命令行执行：")
        log(f"    netsh {args}")
        return False
    log(f"已放行 TCP {port} 入站（规则名 {FIREWALL_RULE}）")
    return True


def waited_for_rule(port: int, tries: int = 6) -> bool:
    """给提权后的 netsh 一点落地时间；每次都要重新查，不能凭返回值猜。"""
    for attempt in range(tries):
        if firewall_rule_covers(port):
            return True
        if attempt + 1 < tries:
            time.sleep(0.5)
    return False


def remove_firewall_rule() -> bool:
    if os.name != "nt":
        log("非 Windows，无需清理")
        return True
    script = ("Start-Process -FilePath netsh -Verb RunAs -ArgumentList "
              f"'advfirewall firewall delete rule name={FIREWALL_RULE}' -WindowStyle Hidden")
    done = run_captured(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass",
                         "-Command", script], 120)
    if done.returncode != 0 or not waited_for_rule_gone():
        log("删除失败或弹窗没批准，请用管理员命令行执行: netsh advfirewall firewall delete rule "
            f"name={FIREWALL_RULE}")
        return False
    log(f"已删除规则 {FIREWALL_RULE}")
    return True


def waited_for_rule_gone(tries: int = 6) -> bool:
    for attempt in range(tries):
        if FIREWALL_RULE not in shown_rule():
            return True
        if attempt + 1 < tries:
            time.sleep(0.5)
    return False


async def run(config: Config, firewall: bool = True) -> None:
    gate = Gate(config)
    server = await asyncio.start_server(gate.serve, config.listen_host,
                                        config.listen_port,
                                        limit=MAX_HEAD_BYTES)
    port = await gate.upstream.aresolve()
    log(f"守门代理已监听 {config.listen_host}:{config.listen_port}")
    log(f"上游: {'http://' + config.upstream_host + ':' + str(port) if port else '暂未发现，请先启动桌面端'}")
    log(f"账号: {config.username} 令牌: "
        f"{'永久' if config.token_ttl_seconds == 0 else str(config.token_ttl_seconds) + 's'}")
    log(f"放行网段: {', '.join(config.allow_cidrs) or '（空 = 不限网段）'}")
    for line in phone_urls(config):
        log(line)
    if not config.allow_cidrs:
        log("WARN 未设置 allow_cidrs，任何能路由到本机的地址都可尝试登录（口令限流已开）")
    if firewall and config.listen_host not in LOOPBACK_HOSTS:
        gate_firewall(config.path, config.listen_port)
    async with server:
        await server.serve_forever()


def gate_firewall(path: Path, port: int) -> None:
    """只有真实配置才配得上动系统入站规则。

    README 让人拿 `--config %TEMP%\\... --init` 演练首启，而演练若也去加规则，机器上
    就会留下一条针对临时端口的永久放行——演练结束没人会想起来删。
    """
    if path.resolve() == DEFAULT_CONFIG.resolve():
        ensure_firewall_rule(port)
    else:
        log(f"演练配置 {path}，不动防火墙规则（真要上线请用默认 gate.json 再起一次）")


def ask_cidrs(current: list | None = None) -> list:
    """把放行网段问清楚，而不是写死一个别处的 /24。首启和 --edit 都走这里。

    写死是首启陷阱：照 README 跑起来的人第一次连就吃到 403，而手机不知道自己
    的局域网地址，于是没有任何线索可推。探测只走路由出口、不发真包、零第三方依赖。

    current 非空时拿它当默认值：改配置时回车意味着"保持原样"，而不是把这一刻
    探测到的网卡再写一遍——插了 VPN 的那一次就会把用户原来的网段悄悄换掉。
    """
    addresses = local_ipv4s()
    detected = " ".join(suggest_cidr(a) for a in addresses)
    default = " ".join(current) if current else detected
    if addresses:
        print("本机局域网地址: " + ", ".join(addresses))
    elif not current:
        print("没探测到本机局域网地址：这台机器现在没有可对外的 IPv4。")
    answer = input(f"允许连入的网段 [{default or '空 = 不限网段'}]"
                   "（回车采用；多个用空格隔开；输入 - 表示不限网段）: ").strip()
    chosen = [] if answer == "-" else (answer or default).split()
    kept = []
    for cidr in chosen:
        try:
            ipaddress.ip_network(cidr, strict=False)
        except ValueError:
            print(f"  忽略非法网段: {cidr}")
            continue
        kept.append(cidr)
    if not kept:
        print("  不限网段：任何能路由到本机的地址都可尝试登录（口令限流仍在）。"
              "起服务时会再提醒一次。")
    return kept


def init_config(path: Path, force: bool) -> Config:
    if path.exists() and not force:
        raise SystemExit(f"{path} 已存在（要覆盖加 --force）")
    raw = {
        "listen_host": "0.0.0.0",
        "listen_port": RECOMMENDED_LISTEN_PORT,
        "upstream_host": "127.0.0.1",
        "upstream_port": 0,
        "username": "",
        "credential": "",
        "token_secret": secrets.token_hex(32),
        "token_ttl_seconds": 0,
        "max_connections": 64,
        "login_max_failures": 8,
        "login_window_seconds": 60,
        "allow_cidrs": [],
    }
    config = Config(raw, path)
    set_password(config, interactive=True)
    config.allow_cidrs = ask_cidrs()
    config.save()
    log(f"已写入 {path}")
    return config


def parse_port(answer: str, current: int, low: int = 1024, high: int = 65535) -> int:
    """空回答保持原值；说不通的输入也保持原值，并把为什么说出来。

    改配置时最容易发生的事是手滑：一路回车必须等于什么都没动，而不是把配置写成
    一个起不来的端口。
    """
    if not answer:
        return current
    try:
        port = int(answer)
    except ValueError:
        print(f"  {answer} 不是端口号，保持 {current}")
        return current
    if not low <= port <= high:
        print(f"  {port} 不在 {low}-{high} 之间，保持 {current}")
        return current
    return port


def ask_upstream_port(config: Config) -> int:
    """上游端口默认交给自动发现；钉死它等于给自己埋一个第二天早上才炸的坑。

    桌面端每次重启都换一个随机回环端口，所以写死数字的那份配置在重启后就只能收到
    502，而症状看起来像"网关坏了"。自动发现先试 config.json 里记着的端口，再扫
    本机回环监听表，每个候选都要用 /api/auth/status 的真实形状确认才算命中。
    """
    current = "自动发现" if not config.upstream_port else str(config.upstream_port)
    print("桌面端（上游）端口：桌面端每次重启都会换端口，所以默认自动发现，不用填数字。")
    print("只有你给桌面端指定过固定端口，或者自动发现总是找不到它，才需要钉死。")
    answer = input(f"上游端口 [当前 {current}]"
                   "（回车保持；0 或 - = 自动发现；数字 = 钉死）: ").strip()
    kept = config.upstream_port
    if answer in ("-", "0"):
        # 0 在这儿不是"端口 0"，是自动发现的哨兵值，所以必须在 parse_port 之前拦掉。
        port = 0
    else:
        port = parse_port(answer, kept, 1, 65535)
    if port and not probe_upstream(config.upstream_host, port):
        print(f"  提醒: 现在探测不到 http://{config.upstream_host}:{port} 上的桌面端。"
              "桌面端没在跑是正常的；真在跑又填错了，启动时会连不上。")
    return port


def edit_config(path: Path) -> Config:
    """日常改配置：每项都以当前值为默认，一路回车等于什么都不改。

    和 --init 的区别是这条路径不重生成 token_secret、也不逼着重设口令。只想换端口
    或加一个网段时，把已签发的令牌全部作废、让手机重新登录是白白收走的代价——所以
    首启向导和日常修改得分开，不能拿 --init --force 当"改配置"用。
    """
    config = Config.read(path)
    before_port = config.listen_port
    before_user = config.username
    print(f"修改 {path}")
    print("（一路回车 = 保持原样；口令只在提示符里输入，不会进命令行参数）")
    try:
        print(f"当前手机端登录用户: {before_user or '（未设置）'}")
        if input("要改登录用户和口令吗？(y/其他=不改): ").strip().lower() == "y":
            set_password(config, interactive=True)
        print(f"手机连入的端口（对外监听）：推荐 {RECOMMENDED_LISTEN_PORT}，"
              "被别的程序占了才需要换。")
        config.listen_port = parse_port(
            input(f"监听端口 [当前 {config.listen_port}，回车保持]: ").strip(),
            config.listen_port)
        config.upstream_port = ask_upstream_port(config)
        config.allow_cidrs = ask_cidrs(config.allow_cidrs)
    except (EOFError, KeyboardInterrupt):
        raise SystemExit("需要在真正的命令行窗口里运行：配置项从管道喂进来没有意义")
    config.save()
    log(f"已写入 {path}")
    if config.listen_port != before_port:
        log(f"监听端口变成了 {config.listen_port}，防火墙入站规则要跟着放行这个端口")
        gate_firewall(path, config.listen_port)
    if config.username != before_user:
        log(f"登录用户已改成 {config.username}，手机上要用新用户名和口令重新登录")
    print()
    show_config(config)
    return config


def set_password(config: Config, interactive: bool) -> None:
    if not interactive:
        raise SystemExit("请用 --init 交互设置，口令不走命令行参数，避免留在进程列表与历史里")
    try:
        username = input("手机端登录用户名: ").strip()
        while not username:
            username = input("用户名不能为空，再来一次: ").strip()
        first = getpass.getpass("手机端登录口令（输入不回显）: ")
        second = getpass.getpass("再输入一次: ")
    except (EOFError, KeyboardInterrupt):
        raise SystemExit("需要在真正的命令行窗口里运行：口令不能从管道或参数喂进来")
    except OSError as exc:
        raise SystemExit(f"读不到控制台（{exc}）：请在 cmd/PowerShell 窗口里直接运行")
    if first != second:
        raise SystemExit("两次口令不一致，未做任何修改")
    if len(first) < 8:
        raise SystemExit("口令至少 8 位（这台机器会暴露在局域网），未做任何修改")
    config.username = username
    config.credential = hash_password(first)


def show_config(config: Config) -> None:
    """把生效配置连解释一起打出来。

    JSON 写不了注释，而这些字段的含义此前只活在 README 里：upstream_port=0 是自动
    发现、username 是手机端登录名而不是桌面端账号、换 token_secret 会作废已签发的令牌。
    口令与密钥只报"有没有设置"——这份输出是会被原样贴进群聊和工单里的东西。
    """
    print(f"配置文件: {config.path}")
    print(f"  listen_host={config.listen_host}  listen_port={config.listen_port}")
    for line in phone_urls(config):
        print(f"    {line}")
    print(f"  upstream_host={config.upstream_host}  upstream_port={config.upstream_port}   "
          + ("# 0 = 自动发现桌面端正在听的回环端口" if config.upstream_port == 0
             else "# 固定端口，不再自动发现"))
    port = Upstream(config).resolve()
    print("    现在探测到的上游: "
          + (f"http://{config.upstream_host}:{port}" if port else "无（桌面端没在跑？）"))
    print(f"  username={config.username or '（未设置）'}   # 手机端登录名，不是桌面端账号")
    print(f"  credential={'已设置' if config.credential else '未设置'}"
          "   # PBKDF2 派生值，明文口令不落盘")
    print(f"  token_secret={'已设置' if config.token_secret else '未设置'}"
          "   # 换掉它 = 已签发的令牌全部作废，手机要重新登录")
    print(f"  token_ttl_seconds={config.token_ttl_seconds}   # 0 = 永久")
    print(f"  allow_cidrs={', '.join(config.allow_cidrs) or '（空）'}"
          "   # 空 = 任何能路由到本机的地址都可尝试登录")
    print(f"  max_connections={config.max_connections}   "
          f"login_max_failures={config.login_max_failures}/{config.login_window_seconds}s")
    print("  改口令/端口/网段: " + hint("--edit") + "（每一项以当前值为默认，一路回车什么都不改）")
    print("  其余高级项手改上面的 JSON 文件，改完再跑一次 --show 复核")


def main(argv: list) -> int:
    parser = argparse.ArgumentParser(description="QwenPaw 局域网守门代理")
    parser.add_argument("--config", default=str(DEFAULT_CONFIG),
                        help="指定配置文件；演练首启时指到临时文件，别覆盖真实的 gate.json")
    parser.add_argument("--init", action="store_true", help="创建配置并设置账号口令")
    parser.add_argument("--force", action="store_true", help="允许 --init 覆盖已有配置")
    parser.add_argument("--edit", action="store_true",
                        help="日常改配置：以当前值为默认，问口令（可跳过）、两个端口、放行网段")
    parser.add_argument("--show", action="store_true",
                        help="打印当前生效配置连每一项的含义，然后退出")
    parser.add_argument("--set-password", action="store_true", help="更换口令/用户名")
    parser.add_argument("--discover", action="store_true", help="打印探测到的上游后退出")
    parser.add_argument("--firewall", action="store_true",
                        help="添加 Windows 入站放行规则（会弹 UAC）")
    parser.add_argument("--no-firewall", action="store_true",
                        help="启动时不提示放行防火墙（已有规则或走反代时用）")
    parser.add_argument("--remove-firewall", action="store_true",
                        help="删除本工具添加的防火墙规则")
    parser.add_argument("--port", type=int, help="覆盖对外监听端口")
    args = parser.parse_args(argv)

    path = Path(args.config)
    if args.init:
        config = init_config(path, args.force)
        gate_firewall(path, config.listen_port)
        return 0
    if args.show:
        show_config(Config.read(path))
        return 0
    if args.edit:
        edit_config(path)
        return 0

    config = Config.load(path)
    if args.port:
        config.listen_port = args.port
    if args.firewall:
        return 0 if ensure_firewall_rule(config.listen_port) else 1
    if args.remove_firewall:
        return 0 if remove_firewall_rule() else 1
    if args.set_password:
        set_password(config, interactive=True)
        config.save()
        log("口令已更新")
        return 0
    if args.discover:
        port = Upstream(config).resolve()
        print(json.dumps({"upstream": port,
                          "reachable": port is not None}, ensure_ascii=False))
        return 0 if port else 1
    try:
        asyncio.run(run(config, firewall=not args.no_firewall))
    except KeyboardInterrupt:
        log("已停止")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
