/**
 * REST entry point for one QwenPaw server. Owns the base URL, the bearer token
 * and the X-Agent-Id header, and is the single place where an HTTP response or a
 * transport error becomes a Failure.
 */
import { Failure, FailureKind } from '../core/Failure';
import { Log } from '../core/Log';
import { ApiPath, Http } from '../core/Wire';
import { Copy } from '../l10n/Copy';
import { RequestSpec, ResponseShape, Transport } from './Transport';
import { SseHandler, SseSession } from './SseSession';

export class HttpMethod {
  static readonly GET: string = 'GET';
  static readonly POST: string = 'POST';
  static readonly PUT: string = 'PUT';
  static readonly DELETE: string = 'DELETE';
}

/** @kit.NetworkKit code for "operation timed out". */
const READ_TIMED_OUT: number = 2300028;

export class ApiClient {
  serverUrl: string = '';
  token: string = '';
  /** Selected agent, sent as X-Agent-Id on every call like the web console. */
  agentId: string = 'default';
  private readonly transport: Transport;

  constructor(transport: Transport) {
    this.transport = transport;
  }

  static normalize(raw: string): string {
    let s = raw.trim();
    if (s.length === 0) {
      return '';
    }
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      s = `http://${s}`;
    }
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  /**
   * Absolute stored path -> preview sub-path; slashes and percent encoding.
   *
   * `.` and `..` are dropped rather than encoded: encodeURIComponent leaves them
   * as literal dots, so a path quoted out of a transcript would travel as
   * `/api/files/preview/../..` with the bearer header on it and could read outside
   * the preview root. A real stored path never contains a dot segment.
   */
  static encodePreviewPath(storedPath: string): string {
    let p = storedPath.split('\\').join('/');
    while (p.startsWith('/')) {
      p = p.substring(1);
    }
    const segments: string[] = [];
    for (const s of p.split('/')) {
      if (s.length > 0 && s !== '.' && s !== '..') {
        segments.push(encodeURIComponent(s));
      }
    }
    return segments.join('/');
  }

  configure(serverUrl: string, token: string): void {
    this.serverUrl = ApiClient.normalize(serverUrl);
    this.token = token;
  }

  isConfigured(): boolean {
    return this.serverUrl.length > 0;
  }

  url(path: string): string {
    const p = path.startsWith('/') ? path : `/${path}`;
    return `${this.serverUrl}/api${p}`;
  }

  headers(): Record<string, string> {
    const h: Record<string, string> = {};
    if (this.token.length > 0) {
      h['Authorization'] = `Bearer ${this.token}`;
    }
    if (this.agentId.length > 0) {
      h['X-Agent-Id'] = this.agentId;
    }
    return h;
  }

  /**
   * A GET is safe to repeat, and a large catalog body can be cut off in flight:
   * the peer closes the read mid-body, which surfaces as a transport error rather
   * than an HTTP status. Retrying once keeps the composer pickers on screen for a
   * single dropped read, while a server verdict still fails straight through.
   */
  get(path: string): Promise<string> {
    return this.request(HttpMethod.GET, path, undefined).catch((err: Error): Promise<string> => {
      const failure = Failure.from(err);
      if (failure.kind !== FailureKind.Offline && failure.kind !== FailureKind.Timeout) {
        throw failure;
      }
      // A picker that lands a moment late looks exactly like one that never
      // failed, so the dropped read has to leave a trace.
      Log.warn(`GET ${path} dropped mid-read (transport=${failure.transportCode}), retrying once`);
      return this.request(HttpMethod.GET, path, undefined);
    });
  }

  /** Omit bodyJson for a bodyless POST: /console/chat/stop rejects an empty one. */
  post(path: string, bodyJson?: string): Promise<string> {
    return this.request(HttpMethod.POST, path, bodyJson);
  }

  put(path: string, bodyJson: string): Promise<string> {
    return this.request(HttpMethod.PUT, path, bodyJson);
  }

  async uploadMultipart(path: string, boundary: string, body: ArrayBuffer): Promise<string> {
    const spec = this.spec(HttpMethod.POST, path);
    spec.headers['Content-Type'] = `multipart/form-data; boundary=${boundary}`;
    spec.bodyBytes = body;
    spec.readTimeout = 60000;
    const res = await this.raw(spec, path);
    return res.body;
  }

  /** Media bytes, fetched with the bearer header so no token leaks into a URL. */
  async fetchBytes(storedPath: string): Promise<ArrayBuffer> {
    const path = `${ApiPath.FILES_PREVIEW}/${ApiClient.encodePreviewPath(storedPath)}`;
    const spec = this.spec(HttpMethod.GET, path);
    spec.expectBinary = true;
    const res = await this.raw(spec, path);
    if (res.bytes === undefined) {
      throw Failure.parse('预览响应没有返回字节');
    }
    return res.bytes;
  }

  startStream(path: string, bodyJson: string, handler: SseHandler): SseSession {
    const spec = this.spec(HttpMethod.POST, path);
    spec.headers['Content-Type'] = 'application/json';
    spec.headers['Accept'] = 'text/event-stream';
    spec.bodyText = bodyJson;
    // A generation can outlast any short read timeout; the stream ends by close.
    spec.readTimeout = 600000;
    const session = new SseSession();
    session.start(this.transport, spec, handler);
    return session;
  }

  private spec(method: string, path: string): RequestSpec {
    if (!this.isConfigured()) {
      throw Failure.local(Copy.notice_no_base_url);
    }
    const spec = new RequestSpec();
    spec.method = method;
    spec.url = this.url(path);
    spec.headers = this.headers();
    return spec;
  }

  private request(method: string, path: string, bodyJson?: string): Promise<string> {
    const spec = this.spec(method, path);
    if (bodyJson !== undefined && bodyJson.length > 0) {
      spec.headers['Content-Type'] = 'application/json';
      spec.bodyText = bodyJson;
    }
    return this.raw(spec, path).then((res: ResponseShape): string => res.body);
  }

  private async raw(spec: RequestSpec, path: string): Promise<ResponseShape> {
    let res: ResponseShape;
    try {
      res = await this.transport.send(spec);
    } catch (e) {
      const failure = Failure.from(e as Object);
      throw failure.transportCode === READ_TIMED_OUT ? Failure.timeout(failure.message) : failure;
    }
    if (res.status < Http.OK_LOW || res.status >= Http.OK_HIGH) {
      throw Failure.http(res.status, ApiClient.snippet(res.body), path);
    }
    return res;
  }

  private static snippet(body: string): string {
    return body.length > 200 ? body.substring(0, 200) : body;
  }
}
