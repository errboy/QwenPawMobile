/**
 * Pure SSE parser: text in, events out. No sockets, no decoding, no QwenPaw
 * assumptions beyond the SSE wire grammar, so it is unit-testable on its own.
 */

export class SseEvent {
  data: string = '';
  event: string = '';
  id: string = '';
  retry: number = 0;
  /** True when the block carried a `data:` field at all. */
  hasData: boolean = false;
}

export class SseDecoder {
  private buffer: string = '';

  /** Feed a decoded text chunk; returns every event completed by this chunk. */
  push(chunk: string): SseEvent[] {
    if (chunk.length === 0) {
      return [];
    }
    this.buffer = SseDecoder.normalize(this.buffer + chunk);
    const out: SseEvent[] = [];
    let index = this.buffer.indexOf('\n\n');
    while (index >= 0) {
      const block = this.buffer.substring(0, index);
      this.buffer = this.buffer.substring(index + 2);
      SseDecoder.appendIfReal(out, SseDecoder.parseBlock(block));
      index = this.buffer.indexOf('\n\n');
    }
    return out;
  }

  /** Emit a trailing event that arrived without its blank-line terminator. */
  flush(): SseEvent[] {
    const out: SseEvent[] = [];
    if (this.buffer.length > 0) {
      SseDecoder.appendIfReal(out, SseDecoder.parseBlock(this.buffer));
      this.buffer = '';
    }
    return out;
  }

  reset(): void {
    this.buffer = '';
  }

  private static appendIfReal(out: SseEvent[], event: SseEvent): void {
    if (event.hasData) {
      out.push(event);
    }
  }

  private static normalize(text: string): string {
    return text.split('\r\n').join('\n').split('\r').join('\n');
  }

  private static parseBlock(block: string): SseEvent {
    const event = new SseEvent();
    const dataLines: string[] = [];
    for (const line of block.split('\n')) {
      if (line.length === 0 || line.startsWith(':')) {
        continue;
      }
      const colon = line.indexOf(':');
      const field = colon < 0 ? line : line.substring(0, colon);
      let value = colon < 0 ? '' : line.substring(colon + 1);
      if (value.startsWith(' ')) {
        value = value.substring(1);
      }
      if (field === 'data') {
        dataLines.push(value);
        event.hasData = true;
      } else if (field === 'event') {
        event.event = value;
      } else if (field === 'id') {
        event.id = value;
      } else if (field === 'retry') {
        const parsed = Number.parseInt(value, 10);
        if (!Number.isNaN(parsed)) {
          event.retry = parsed;
        }
      }
    }
    event.data = dataLines.join('\n');
    return event;
  }
}
