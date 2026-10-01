/**
 * The one bubble type the chat UI renders.
 *
 * It is @Observed on purpose: a streaming token mutates `text` in place, so the
 * bubble redraws without the store replacing the whole array. Array membership
 * changes are the store's job and arrive as a new array reference.
 */
import { BubbleKind } from '../stream/StreamReducer';
import { MediaValue } from '../media/MediaLoader';
import { Role } from '../core/Wire';

export class UiKind {
  static readonly TEXT: string = BubbleKind.TEXT;
  static readonly REASONING: string = BubbleKind.REASONING;
  static readonly TOOL: string = BubbleKind.TOOL;
  /** Centered line for a server verdict, a retry notice or a rate limit. */
  static readonly NOTICE: string = 'notice';
  /** A user message waiting behind a live run; tapping it recalls the send. */
  static readonly QUEUED: string = 'queued';
}

export class NoticeTone {
  static readonly ERROR: string = 'error';
  static readonly MUTED: string = 'muted';
}

@Observed
export class UiMessage {
  key: string = '';
  kind: string = UiKind.TEXT;
  role: string = Role.ASSISTANT;
  /** Tool name for a tool card; empty otherwise. */
  name: string = '';
  text: string = '';
  streaming: boolean = false;
  /** Notice colouring: a server verdict reads louder than a status line. */
  tone: string = NoticeTone.ERROR;
  /** Raw reference as it arrived: stored path, data: URI or URL. */
  imageRef: string = '';
  /** Resolved through MediaLoader; undefined until it lands. */
  image?: MediaValue;
  imageRequested: boolean = false;
}
