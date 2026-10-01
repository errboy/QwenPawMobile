/**
 * Transport boundary. Everything above this line is plain logic that a test can
 * drive; only HttpTransport touches @kit.NetworkKit.
 */

export class RequestSpec {
  method: string = 'GET';
  url: string = '';
  headers: Record<string, string> = {};
  bodyText?: string;
  bodyBytes?: ArrayBuffer;
  /** Set when the response body must stay binary (media preview). */
  expectBinary: boolean = false;
  connectTimeout: number = 10000;
  readTimeout: number = 30000;
}

export class ResponseShape {
  status: number = 0;
  body: string = '';
  bytes?: ArrayBuffer;
}

/**
 * Callbacks are function-typed properties rather than interface methods: ArkTS
 * only lets an object literal satisfy a type whose members are data properties.
 */
export interface StreamSink {
  onData: (chunk: ArrayBuffer) => void;
  /** HTTP status of a stream that ran to a natural end. */
  onEnd: (status: number) => void;
  onFail: (code: number, message: string) => void;
}

export interface StreamHandle {
  cancel: () => void;
}

export interface Transport {
  send(spec: RequestSpec): Promise<ResponseShape>;

  stream(spec: RequestSpec, sink: StreamSink): StreamHandle;
}
