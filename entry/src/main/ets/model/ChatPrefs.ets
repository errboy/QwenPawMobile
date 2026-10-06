/**
 * Per-chat composer preferences.
 *
 * The backend keeps none of this: approval level and model slot ride along in
 * every chat request body, and a loop mode is nothing but a slash prefix on the
 * message text. So the phone owns the state, keyed by chat, exactly like the web
 * console's per-chat localStorage.
 *
 * The one non-composer entry is the record of media this phone sent, which sits
 * here because it is the same shape of fact: per chat, device-local, and small
 * enough that a chat window can carry it without another store.
 */
import { ApprovalLevel } from '../core/Wire';
import { ModelSlot, RequestContext } from './Dtos';

/**
 * One attachment set this phone sent, kept so its own media survives a history
 * reload. The desktop stores a turn's attachments for history only when that turn
 * carried a `file` part, so an image the phone uploaded comes back as the
 * model-facing sentence the server built (see docs/07 §8.1) on every client, this
 * one included. The refs are the phone's copy of what it already showed once.
 *
 * Mirrors UiMessage's ref fields one-to-one: the record is copied off the outgoing
 * bubble, which is why it holds at most one reference per kind.
 */
export class SentMedia {
  /** The id stamped on that turn's metadata; the join key against history. */
  cid: string = '';
  imageRef: string = '';
  videoRef: string = '';
  audioRef: string = '';
  fileRef: string = '';
  fileName: string = '';
}

export class ChatPreference {
  chatId: string = '';
  /** Empty means 'send no override', which leaves the PC agent's own level in force. */
  approvalLevel: string = '';
  providerId: string = '';
  model: string = '';
  loopModeId: string = '';
  /** Kept beside the id so a prefix can be applied without refetching /loops. */
  loopSlash: string = '';
  /** Unsent composer text: the only copy that survives the page being popped. */
  draft: string = '';
  /** Media this phone sent, oldest first, capped by the store that reads it. */
  sentMedia: SentMedia[] = [];

  /** A half-picked slot is worse than none: the server would reject the pair. */
  modelOverride(): ModelSlot | undefined {
    if (this.providerId.length === 0 || this.model.length === 0) {
      return undefined;
    }
    const slot = new ModelSlot();
    slot.provider_id = this.providerId;
    slot.model = this.model;
    return slot;
  }

  approvalOverride(): RequestContext | undefined {
    if (!ApprovalLevel.isKnown(this.approvalLevel)) {
      return undefined;
    }
    const ctx = new RequestContext();
    ctx.approval_level = this.approvalLevel.toUpperCase();
    return ctx;
  }
}
