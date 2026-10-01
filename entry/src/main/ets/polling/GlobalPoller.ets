/**
 * The app's only network timer.
 *
 * v1 ran a 10s interval in HomePage and another in ChatPage, so every idle second
 * fired two /api/chats and two /api/approval/list requests and the two pages could
 * render different snapshots of the same moment. One poller fetches once and hands
 * the same snapshot to whoever is listening.
 */
import { ApprovalApi } from '../api/ApprovalApi';
import { ChatApi } from '../api/ChatApi';
import { ApprovalInfo, ChatSpec } from '../model/Dtos';

export const POLL_INTERVAL_MS: number = 10000;

/** One coherent view of the server, shared by every listener. */
export class PollSnapshot {
  chats: ChatSpec[] = [];
  approvals: ApprovalInfo[] = [];
  /** Consecutive failed ticks; the UI starts showing an offline hint at 2. */
  failures: number = 0;
}

export interface PollTarget {
  onPoll(snapshot: PollSnapshot): void;
}

export class GlobalPoller {
  private readonly chatApi: ChatApi;
  private readonly approvalApi: ApprovalApi;
  private readonly targets: PollTarget[] = [];
  private timer: number = -1;
  private running: boolean = false;
  private snapshotValue: PollSnapshot = new PollSnapshot();

  constructor(chatApi: ChatApi, approvalApi: ApprovalApi) {
    this.chatApi = chatApi;
    this.approvalApi = approvalApi;
  }

  snapshot(): PollSnapshot {
    return this.snapshotValue;
  }

  register(target: PollTarget): void {
    if (!this.targets.includes(target)) {
      this.targets.push(target);
    }
  }

  unregister(target: PollTarget): void {
    for (let i = 0; i < this.targets.length; i++) {
      if (this.targets[i] === target) {
        this.targets.splice(i, 1);
        return;
      }
    }
  }

  /** Start the tick loop; a second call is a no-op, so pages cannot stack timers. */
  start(): void {
    if (this.timer >= 0) {
      return;
    }
    this.timer = setInterval((): void => {
      this.tick();
    }, POLL_INTERVAL_MS);
  }

  stop(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  /** Manual refresh and page-entry: fetch once without waiting for the tick. */
  poke(): void {
    this.tick();
  }

  private async tick(): Promise<void> {
    if (this.running) {
      return;
    }
    this.running = true;
    const next = new PollSnapshot();
    next.failures = this.snapshotValue.failures;
    try {
      next.chats = await this.chatApi.list();
      next.approvals = await this.approvalApi.list();
      next.failures = 0;
    } catch (e) {
      // Keep the last good snapshot: a transient blip must not blank the list.
      next.chats = this.snapshotValue.chats;
      next.approvals = this.snapshotValue.approvals;
      next.failures += 1;
    } finally {
      this.running = false;
    }
    this.snapshotValue = next;
    for (const target of this.targets.slice()) {
      target.onPoll(next);
    }
  }
}
