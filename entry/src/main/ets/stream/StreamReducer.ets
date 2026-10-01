/**
 * Frame -> bubble reducer for QwenPaw v2.2.2-beta.4's console SSE stream.
 *
 * Two properties of the wire drive the whole design:
 *   - `object=content` frames carry `delta=true` for increments and `delta=false`
 *     for the *complete* block text. v1 appended on both, so a finished block
 *     printed twice. Here every block is stored per (msg_id, index) and the
 *     non-delta frame overwrites it.
 *   - There is no `data: [DONE]`. A run ends when the `response` frame reports a
 *     terminal status; anything else that closes the stream is a dropped
 *     connection, which RunController has to tell apart from a verdict.
 *
 * The reducer emits facts (Upsert / status / flags), never copy: all user-facing
 * strings are composed by the UI layer from Copy.ets.
 */
import { ContentPart, FrameError } from '../model/Content';
import { SseFrame } from '../model/Dtos';
import { DEFAULT_TEMPLATES, Parts, PartTemplates } from '../model/Parts';
import { ContentType, FrameType, MsgType, RunStatus, SseObject, ToolTypes } from '../core/Wire';

/** Bubble families the chat UI renders. */
export class BubbleKind {
  static readonly TEXT: string = 'text';
  static readonly REASONING: string = 'reasoning';
  static readonly TOOL: string = 'tool';
}

/** One bubble the store must create or overwrite, keyed by backend msg_id. */
export class Upsert {
  key: string = '';
  kind: string = BubbleKind.TEXT;
  role: string = 'assistant';
  name: string = '';
  text: string = '';
  imageUrl: string = '';
  streaming: boolean = false;
}

/** What a single frame changed. */
export class StreamFacts {
  upserts: Upsert[] = [];
  /** Terminal RunStatus when a response frame closed the run; '' otherwise. */
  runStatus: string = '';
  runError: string = '';
  /** Bare {"error": "..."} frame: a server verdict, so no reconnect is wanted. */
  transportError: string = '';
  rateLimited: string = '';
  heartbeat: boolean = false;
  /** True after the replay of a run started elsewhere has finished. */
  replayEnd: boolean = false;
  /** Any frame that arrived, which proves the connection is live. */
  alive: boolean = false;
}

class MsgBuf {
  kind: string = BubbleKind.TEXT;
  /** Block index -> accumulated text, so delta=false can replace it. */
  blocks: Map<number, string> = new Map();
  imageUrl: string = '';
}

export class StreamReducer {
  private readonly templates: PartTemplates;
  private readonly bufs: Map<string, MsgBuf> = new Map();

  constructor(templates?: PartTemplates) {
    this.templates = templates === undefined ? DEFAULT_TEMPLATES : templates;
  }

  /** Feed the raw payload of one `data:` line. Malformed JSON is dropped, not fatal. */
  feed(raw: string): StreamFacts {
    let frame: SseFrame;
    try {
      frame = JSON.parse(raw) as SseFrame;
    } catch (e) {
      return new StreamFacts();
    }
    if (frame === undefined || frame === null) {
      return new StreamFacts();
    }
    return this.apply(frame);
  }

  apply(frame: SseFrame): StreamFacts {
    const out = new StreamFacts();
    out.alive = true;
    const obj = Parts.str(frame.object);
    if (obj === SseObject.CONTENT) {
      this.onContent(frame, out);
    } else if (obj === SseObject.MESSAGE) {
      this.onMessage(frame, out);
    } else if (obj === SseObject.RESPONSE) {
      this.onResponse(frame, out);
    } else {
      this.onSignal(frame, out);
    }
    return out;
  }

  /** Text already committed to the store; forget the buffers for a new run. */
  clear(): void {
    this.bufs.clear();
  }

  private onContent(f: SseFrame, out: StreamFacts): void {
    const msgId = Parts.str(f.msg_id);
    if (msgId.length === 0) {
      return;
    }
    const type = Parts.str(f.type);
    if (type === ContentType.TEXT) {
      const piece = Parts.str(f.text);
      if (piece.length === 0) {
        return;
      }
      const index = f.index === undefined || f.index === null ? 0 : f.index;
      const buf = this.bufferFor(msgId);
      buf.blocks.set(index, f.delta === true ? this.textAt(buf, index) + piece : piece);
      out.upserts.push(this.snapshot(msgId, buf, true));
      return;
    }
    if (type === ContentType.IMAGE) {
      const url = Parts.str(f.image_url);
      if (url.length === 0) {
        return;
      }
      const buf = this.bufferFor(msgId);
      buf.imageUrl = url;
      out.upserts.push(this.snapshot(msgId, buf, true));
      return;
    }
    // `data` parts stream tool arguments one chunk at a time; the completed
    // message frame renders them, so partial JSON never shows up in the UI.
  }

  private onMessage(f: SseFrame, out: StreamFacts): void {
    const id = Parts.str(f.id);
    const type = Parts.str(f.type);
    if (id.length === 0 || type === MsgType.HEARTBEAT) {
      return;
    }
    const status = Parts.str(f.status);
    if (ToolTypes.isTool(type)) {
      if (status === RunStatus.COMPLETED) {
        out.upserts.push(this.toolUpsert(id, type, f.content));
      }
      return;
    }
    const kind = type === MsgType.REASONING ? BubbleKind.REASONING : BubbleKind.TEXT;
    const buf = this.bufferFor(id);
    buf.kind = kind;
    if (status !== RunStatus.COMPLETED) {
      // Start frame: it names the block kind so the deltas that follow land in
      // the right bubble. The card itself appears with its first delta.
      return;
    }
    const text = Parts.displayText(f.content, this.templates);
    const image = Parts.firstImage(f.content);
    buf.blocks.clear();
    if (text.length > 0) {
      buf.blocks.set(0, text);
    }
    if (image.length > 0) {
      buf.imageUrl = image;
    }
    out.upserts.push(this.snapshot(id, buf, false));
  }

  private onResponse(f: SseFrame, out: StreamFacts): void {
    const status = Parts.str(f.status);
    if (!RunStatus.isTerminal(status)) {
      return;
    }
    out.runStatus = status;
    out.runError = StreamReducer.errorText(f.error);
    this.clear();
  }

  /** Frames without `object`: keep-alives, replay markers, transport errors. */
  private onSignal(f: SseFrame, out: StreamFacts): void {
    const type = Parts.str(f.type);
    if (type === MsgType.HEARTBEAT) {
      out.heartbeat = true;
      return;
    }
    if (type === FrameType.REPLAY_END) {
      out.replayEnd = true;
      return;
    }
    if (type === FrameType.RATE_LIMITED) {
      out.rateLimited = StreamReducer.errorText(f.error);
      return;
    }
    const err = StreamReducer.errorText(f.error);
    if (err.length > 0) {
      out.transportError = err;
    }
    // turn_usage and any frame type this build does not know: no bubble.
  }

  private toolUpsert(id: string, type: string, content: ContentPart[] | undefined): Upsert {
    const data = Parts.firstData(content);
    const u = new Upsert();
    u.key = id;
    u.kind = BubbleKind.TOOL;
    u.name = Parts.toolName(data, this.templates)
      + (ToolTypes.isOutput(type) ? this.templates.outputSuffix : '');
    const body = ToolTypes.isOutput(type) ? Parts.asText(data === undefined ? undefined : data.output)
      : Parts.asText(data === undefined ? undefined : data.arguments);
    u.text = Parts.clip(body, this.templates.toolClipChars);
    return u;
  }

  private bufferFor(msgId: string): MsgBuf {
    const existing = this.bufs.get(msgId);
    if (existing !== undefined) {
      return existing;
    }
    const buf = new MsgBuf();
    this.bufs.set(msgId, buf);
    return buf;
  }

  private textAt(buf: MsgBuf, index: number): string {
    const held = buf.blocks.get(index);
    return held === undefined ? '' : held;
  }

  private snapshot(msgId: string, buf: MsgBuf, streaming: boolean): Upsert {
    const u = new Upsert();
    u.key = msgId;
    u.kind = buf.kind;
    u.text = StreamReducer.joinBlocks(buf);
    u.imageUrl = buf.imageUrl;
    u.streaming = streaming;
    return u;
  }

  /** Blocks are numbered by the server; join them in ascending index order. */
  private static joinBlocks(buf: MsgBuf): string {
    if (buf.blocks.size === 0) {
      return '';
    }
    const indexes: number[] = [];
    buf.blocks.forEach((_text: string, index: number): void => {
      indexes.push(index);
    });
    indexes.sort((a: number, b: number): number => a - b);
    let out = '';
    for (const i of indexes) {
      const piece = buf.blocks.get(i);
      if (piece !== undefined) {
        out += piece;
      }
    }
    return out;
  }

  /** A declared string can arrive as a {code,message} object, or the reverse. */
  static errorText(value: Object | undefined): string {
    if (value === undefined || value === null) {
      return '';
    }
    if (typeof value === 'string') {
      return value as string;
    }
    const shape = value as FrameError;
    const message = Parts.str(shape.message);
    if (message.length > 0) {
      return message;
    }
    const code = Parts.str(shape.code);
    return code.length > 0 ? code : Parts.asText(value);
  }
}
