/**
 * One error shape for the whole app. Transport, HTTP and parse failures are
 * normalised into a Failure at the boundary that produced them, so the UI never
 * has to inspect a raw BusinessError or sniff an HTTP status out of a message.
 */
import { Http } from './Wire';

export enum FailureKind {
  NoServer,
  Offline,
  Timeout,
  Unauthorized,
  Forbidden,
  NotFound,
  Conflict,
  Locked,
  TooMany,
  Server,
  Parse,
  Rejected,
  Unknown
}

interface TransportShape {
  code?: number;
  message?: string;
}

export class Failure extends Error {
  kind: FailureKind = FailureKind.Unknown;
  /** HTTP status, or 0 when the request never got a response. */
  httpStatus: number = 0;
  /** Raw transport code from @kit.NetworkKit, kept for diagnostics. */
  transportCode: number = 0;
  /** Server-supplied detail (FastAPI `detail` or a body snippet). */
  detail: string = '';

  constructor(kind: FailureKind, message: string) {
    super(message);
    this.name = 'Failure';
    this.kind = kind;
  }

  private static byStatus(status: number): FailureKind {
    if (status === Http.UNAUTHORIZED) {
      return FailureKind.Unauthorized;
    }
    if (status === Http.FORBIDDEN) {
      return FailureKind.Forbidden;
    }
    if (status === Http.NOT_FOUND) {
      return FailureKind.NotFound;
    }
    if (status === Http.CONFLICT) {
      return FailureKind.Conflict;
    }
    if (status === Http.LOCKED) {
      return FailureKind.Locked;
    }
    if (status === Http.TOO_MANY) {
      return FailureKind.TooMany;
    }
    return status >= 500 ? FailureKind.Server : FailureKind.Rejected;
  }

  static http(status: number, detail: string, path: string): Failure {
    const f = new Failure(Failure.byStatus(status), `HTTP ${status} ${path}`);
    f.httpStatus = status;
    f.detail = detail;
    return f;
  }

  /** Cannot reach the server at all: worth retrying with backoff. */
  static offline(transportCode: number, message: string): Failure {
    const f = new Failure(FailureKind.Offline, message);
    f.transportCode = transportCode;
    return f;
  }

  /** @kit.NetworkKit surfaces a read timeout as a transport error too. */
  static timeout(message: string): Failure {
    const f = new Failure(FailureKind.Timeout, message);
    f.transportCode = -2;
    return f;
  }

  static parse(message: string): Failure {
    return new Failure(FailureKind.Parse, message);
  }

  static local(message: string): Failure {
    return new Failure(FailureKind.Unknown, message);
  }

  /** Wrap anything thrown across a kit boundary. */
  static from(cause: Object): Failure {
    if (cause instanceof Failure) {
      return cause;
    }
    const shape = cause as TransportShape;
    const code = shape.code === undefined ? 0 : shape.code;
    const message = shape.message === undefined ? `${shape}` : shape.message;
    return Failure.offline(code, message);
  }

  isConflict(): boolean {
    return this.kind === FailureKind.Conflict;
  }

  isUnauthorized(): boolean {
    return this.kind === FailureKind.Unauthorized;
  }

  /** A dropped connection may be re-attached; a server verdict may not. */
  isTransient(): boolean {
    return this.kind === FailureKind.Offline || this.kind === FailureKind.Timeout
      || this.kind === FailureKind.Server || this.kind === FailureKind.TooMany;
  }
}
