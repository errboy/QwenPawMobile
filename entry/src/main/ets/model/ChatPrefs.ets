/**
 * Per-chat composer preferences.
 *
 * The backend keeps none of this: approval level and model slot ride along in
 * every chat request body, and a loop mode is nothing but a slash prefix on the
 * message text. So the phone owns the state, keyed by chat, exactly like the web
 * console's per-chat localStorage.
 */
import { ApprovalLevel } from '../core/Wire';
import { ModelSlot, RequestContext } from './Dtos';

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
