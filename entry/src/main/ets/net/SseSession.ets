/**
 * One live SSE connection: bytes -> UTF-8 text -> events.
 * Cancel is idempotent and guarantees no handler fires afterwards, which is what
 * lets pages drop a stream in aboutToDisappear without racing callbacks.
 */
import { util } from '@kit.ArkTS';
import { Failure } from '../core/Failure';
import { RequestSpec, StreamHandle, StreamSink, Transport } from './Transport';
import { SseDecoder, SseEvent } from './SseDecoder';

export interface SseHandler {
  /** Raw JSON payload of one `data:` frame. */
  onFrame(data: string, meta: SseEvent): void;

  /** Stream reached a natural end; status is the HTTP code (0 when unknown). */
  onClosed(status: number): void;

  onFailed(failure: Failure): void;
}

export class SseSession {
  private readonly decoder: SseDecoder = new SseDecoder();
  private readonly utf8: util.TextDecoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
  private handle?: StreamHandle;
  private handler?: SseHandler;
  private closed: boolean = false;

  isAlive(): boolean {
    return !this.closed;
  }

  start(transport: Transport, spec: RequestSpec, handler: SseHandler): void {
    this.handler = handler;
    this.closed = false;
    const sink: StreamSink = {
      onData: (chunk: ArrayBuffer): void => {
        this.consume(chunk);
      },
      onEnd: (status: number): void => {
        this.drain();
        this.finish(() => {
          handler.onClosed(status);
        });
      },
      onFail: (code: number, message: string): void => {
        this.finish(() => {
          handler.onFailed(Failure.offline(code, message));
        });
      }
    };
    this.handle = transport.stream(spec, sink);
  }

  cancel(): void {
    const handle = this.handle;
    this.handle = undefined;
    if (handle !== undefined) {
      handle.cancel();
    }
    this.closed = true;
    this.decoder.reset();
  }

  private consume(chunk: ArrayBuffer): void {
    const text = this.utf8.decodeWithStream(new Uint8Array(chunk), { stream: true });
    for (const event of this.decoder.push(text)) {
      if (this.handler !== undefined) {
        this.handler.onFrame(event.data, event);
      }
    }
  }

  private drain(): void {
    const trailing = this.decoder.flush();
    if (this.handle !== undefined) {
      this.handle.cancel();
      this.handle = undefined;
    }
    for (const event of trailing) {
      if (this.handler !== undefined && !this.closed) {
        this.handler.onFrame(event.data, event);
      }
    }
  }

  private finish(emit: () => void): void {
    if (this.closed) {
      return;
    }
    this.closed = true;
    this.handle = undefined;
    emit();
  }
}
