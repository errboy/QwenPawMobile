/**
 * LAN discovery for the PC running QwenPaw.
 *
 * Typing 192.168.1.23:8088 on a phone is the single worst first-run experience
 * this app has, and a wrong digit is indistinguishable from a dead server. So the
 * login page sweeps the phone's own /24 instead: one GET /api/auth/status per
 * address, in small batches, with a short timeout. A host answers only when it is
 * both reachable and speaking the QwenPaw wire vocabulary, which is exactly the
 * set worth listing.
 */
import { connection } from '@kit.NetworkKit';
import { AuthStatus } from '../model/Dtos';
import { ApiPath } from '../core/Wire';
import { RequestSpec, Transport } from './Transport';

/** One probed address and what the probe learned. */
export class LanTarget {
  url: string = '';
  host: string = '';
  port: number = 0;
  online: boolean = false;
  authEnabled: boolean = false;
  hasUsers: boolean = false;
  latencyMs: number = 0;
}

export type ScanProgress = (done: number, total: number, found: number) => void;

/** Private ranges a home/office LAN actually uses. */
const PRIVATE_PREFIXES: string[] = ['192.168.', '10.', '172.'];

export class LanScan {
  static readonly DEFAULT_PORT: number = 8088;
  /** One request per address, so a dead host costs a timeout, not a retry. */
  private static readonly BATCH: number = 16;
  private static readonly PROBE_MS: number = 1200;

  /** '192.168.0' for the phone's own Wi-Fi address; '' when it cannot be read. */
  static localPrefix(): string {
    const ip = LanScan.localAddress();
    const dot = ip.lastIndexOf('.');
    return dot > 0 ? ip.substring(0, dot) : '';
  }

  static localAddress(): string {
    try {
      const props = connection.getConnectionPropertiesSync(connection.getDefaultNetSync());
      for (const link of props.linkAddresses) {
        const addr = link.address.address;
        for (const range of PRIVATE_PREFIXES) {
          if (addr.startsWith(range)) {
            return addr;
          }
        }
      }
    } catch (e) {
      // No active network or the permission is refused: the caller lists nothing.
    }
    return '';
  }

  /** Every candidate address in the /24, minus the phone itself. */
  static candidates(prefix: string, port: number): LanTarget[] {
    const out: LanTarget[] = [];
    if (prefix.length === 0) {
      return out;
    }
    const own = LanScan.localAddress();
    for (let host = 1; host < 255; host++) {
      const ip = `${prefix}.${host}`;
      if (ip === own) {
        continue;
      }
      const t = new LanTarget();
      t.host = ip;
      t.port = port;
      t.url = `http://${ip}:${port}`;
      out.push(t);
    }
    return out;
  }

  /** Sweep a /24; progress fires per batch so the UI can show a bar. */
  static async sweep(transport: Transport, prefix: string, port: number,
    onProgress?: ScanProgress): Promise<LanTarget[]> {
    const all = LanScan.candidates(prefix, port);
    const live: LanTarget[] = [];
    let done = 0;
    for (let i = 0; i < all.length; i += LanScan.BATCH) {
      const batch = all.slice(i, i + LanScan.BATCH);
      const results = await Promise.all(batch.map(async (t: LanTarget): Promise<LanTarget> =>
        LanScan.probe(transport, t, LanScan.PROBE_MS)));
      for (const r of results) {
        if (r.online) {
          live.push(r);
        }
      }
      done += batch.length;
      if (onProgress !== undefined) {
        onProgress(done, all.length, live.length);
      }
    }
    return live;
  }

  /** Probe a handful of addresses at once; the list order is preserved. */
  static async probeAll(transport: Transport, targets: LanTarget[],
    timeoutMs: number): Promise<LanTarget[]> {
    return Promise.all(targets.map(async (t: LanTarget): Promise<LanTarget> =>
      LanScan.probe(transport, t, timeoutMs)));
  }

  /** Probe one address. Only a QwenPaw-shaped /auth/status counts as a hit. */
  static async probe(transport: Transport, target: LanTarget, timeoutMs: number): Promise<LanTarget> {
    const spec = new RequestSpec();
    spec.method = 'GET';
    spec.url = `${target.url}/api${ApiPath.AUTH_STATUS}`;
    spec.connectTimeout = timeoutMs;
    spec.readTimeout = timeoutMs;
    const started = Date.now();
    try {
      const res = await transport.send(spec);
      const shape = JSON.parse(res.body) as AuthStatus;
      const hit = res.status >= 200 && res.status < 300 && typeof shape.enabled === 'boolean'
        && typeof shape.has_users === 'boolean';
      target.online = hit;
      if (hit) {
        target.authEnabled = shape.enabled;
        target.hasUsers = shape.has_users;
        target.latencyMs = Date.now() - started;
      }
    } catch (e) {
      target.online = false;
    }
    return target;
  }

  /** 'http://a:1' -> 'a:1'; anything else stays as typed so the UI can show it. */
  static hostOf(url: string): string {
    let s = url.trim();
    if (s.startsWith('http://')) {
      s = s.substring(7);
    } else if (s.startsWith('https://')) {
      s = s.substring(8);
    }
    const slash = s.indexOf('/');
    return slash >= 0 ? s.substring(0, slash) : s;
  }

  static portOf(url: string, fallback: number): number {
    const host = LanScan.hostOf(url);
    const colon = host.lastIndexOf(':');
    if (colon < 0) {
      return fallback;
    }
    const port = parseInt(host.substring(colon + 1), 10);
    return port >= 1 && port <= 65535 ? port : fallback;
  }

  /**
   * 'http://10.0.2.2' + 8088 -> 'http://10.0.2.2:8088'. An explicit port stays
   * put, and so does https, where the default is 443 rather than the scan port.
   */
  static withPort(url: string, defaultPort: number): string {
    if (!url.startsWith('http://') || LanScan.portOf(url, 0) > 0) {
      return url;
    }
    return `${url}:${defaultPort}`;
  }

  /**
   * Wrap an address the user configured as a probe target. A typed host without a
   * port borrows the scan port, so '192.168.1.23' and 'http://192.168.1.23:8088'
   * describe the same machine to the login list.
   */
  static targetOf(url: string, defaultPort: number): LanTarget {
    const full = LanScan.withPort(url, defaultPort);
    const t = new LanTarget();
    t.url = full;
    t.host = LanScan.hostOf(full);
    t.port = LanScan.portOf(full, defaultPort);
    return t;
  }
}
