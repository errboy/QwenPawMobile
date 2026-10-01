/**
 * The only module in the app that touches @kit.NetworkKit.
 */
import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { RequestSpec, ResponseShape, StreamHandle, StreamSink, Transport } from './Transport';

/** @kit.NetworkKit code for "operation timed out". */
const READ_TIMED_OUT: number = 2300028;

export class HttpTransport implements Transport {
  isTimeout(code: number): boolean {
    return code === READ_TIMED_OUT;
  }

  async send(spec: RequestSpec): Promise<ResponseShape> {
    const req = http.createHttp();
    try {
      const res = await req.request(spec.url, HttpTransport.options(spec));
      const out = new ResponseShape();
      out.status = res.responseCode;
      if (spec.expectBinary) {
        out.bytes = res.result as ArrayBuffer;
      } else {
        out.body = typeof res.result === 'string' ? res.result : '';
      }
      return out;
    } finally {
      req.destroy();
    }
  }

  stream(spec: RequestSpec, sink: StreamSink): StreamHandle {
    const req = http.createHttp();
    let dead = false;
    const detach = (): void => {
      try {
        req.off('dataReceive');
        req.off('dataEnd');
        req.destroy();
      } catch (e) {
        // Already torn down.
      }
    };
    req.on('dataReceive', (chunk: ArrayBuffer): void => {
      if (!dead) {
        sink.onData(chunk);
      }
    });
    req.requestInStream(spec.url, HttpTransport.options(spec))
      .then((status: number): void => {
        if (!dead) {
          dead = true;
          detach();
          sink.onEnd(status);
        }
      })
      .catch((e: BusinessError): void => {
        if (!dead) {
          dead = true;
          detach();
          sink.onFail(e.code === undefined ? 0 : e.code, e.message === undefined ? '' : e.message);
        }
      });
    return {
      cancel: (): void => {
        if (!dead) {
          dead = true;
          detach();
        }
      }
    };
  }

  private static options(spec: RequestSpec): http.HttpRequestOptions {
    const options: http.HttpRequestOptions = {
      method: HttpTransport.methodOf(spec.method),
      header: spec.headers,
      expectDataType: spec.expectBinary ? http.HttpDataType.ARRAY_BUFFER : http.HttpDataType.STRING,
      connectTimeout: spec.connectTimeout,
      readTimeout: spec.readTimeout
    };
    // An empty extraData is rejected by the http module's parameter check, so a
    // bodyless POST must omit the field entirely rather than send ''.
    if (spec.bodyText !== undefined && spec.bodyText.length > 0) {
      options.extraData = spec.bodyText;
    } else if (spec.bodyBytes !== undefined) {
      options.extraData = spec.bodyBytes;
    }
    return options;
  }

  private static methodOf(method: string): http.RequestMethod {
    if (method === 'POST') {
      return http.RequestMethod.POST;
    }
    if (method === 'PUT') {
      return http.RequestMethod.PUT;
    }
    if (method === 'DELETE') {
      return http.RequestMethod.DELETE;
    }
    return http.RequestMethod.GET;
  }
}
