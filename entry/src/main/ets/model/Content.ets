/**
 * Content-part vocabulary shared by chat history and the SSE stream.
 * Kept separate from Dtos.ets so the dependency stays one-way.
 */

/** Payload of a `data` part: tool arguments and tool outputs ride here. */
export class DataPayload {
  call_id: string = '';
  name: string = '';
  arguments?: Object;
  output?: Object;
  state?: string;
}

/**
 * Where a tool's block keeps its bytes: a path on the PC's disk, or the bytes
 * themselves inlined as base64. Which one it is arrives in `type`.
 */
export class ToolBlockSource {
  type: string = '';
  url?: string;
  data?: string;
  media_type?: string;
}

/**
 * One block of the list a tool serialises into its `output`. A file the PC handed
 * over is a `data` block with a `source`; what the tool has to say is a `text` one.
 */
export class ToolOutputBlock {
  type: string = '';
  text?: string;
  name?: string;
  source?: ToolBlockSource;
}

/** A single content part, heterogeneous by `type` (text|image|audio|video|data|file|refusal). */
export class ContentPart {
  type: string = 'text';
  text: string = '';
  delta?: boolean;
  index?: number;
  msg_id?: string;
  status?: string;
  data?: DataPayload;
  image_url?: string;
  video_url?: string;
  /** Audio parts carry their stored path or base64 payload in `data`. */
  filename?: string;
  file_name?: string;
  file_url?: string;
}

/** response.error is an object; transport-level error frames carry a plain string. */
export class FrameError {
  code?: string;
  message?: string;
}
