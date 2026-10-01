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
