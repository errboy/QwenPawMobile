/**
 * Run state machine for one chat window.
 *
 * v1 spread this logic over ChatPage methods and shared a single
 * `reconnectAttempts` counter between the 10s poller and the reconnect ladder, so
 * a poll tick could silently cancel a retry. Here the controller owns scheduling
 * and the store owns display; the poller only calls probe().
 *
 * Phases:
 *   idle        no run known, queued sends may start
 *   streaming   an SSE connection is open
 *   backoff     the connection dropped, waiting on the 2/4/8s ladder
 *   stale       retries exhausted but the server may still be generating;
 *               the poll tick decides whether to re-attach or release the UI
 */
import { ChatApi } from '../api/ChatApi';
import { Failure } from '../core/Failure';
import { Http, RunStatus } from '../core/Wire';
import { RequestPart } from '../model/Dtos';
import { ChatPreference } from '../model/ChatPrefs';
import { SseEvent } from '../net/SseDecoder';
import { SseHandler, SseSession } from '../net/SseSession';
import { StreamFacts, StreamReducer, Upsert } from './StreamReducer';

/** Retry ladder: 2s, 4s, 8s, then give up and hand over to the poller. */
const MAX_RECONNECT: number = 3;

export class RunPhase {
  static readonly IDLE: string = 'idle';
  static readonly STREAMING: string = 'streaming';
  static readonly BACKOFF: string = 'backoff';
  static readonly STALE: string = 'stale';
}

/**
 * Everything the controller can ask the chat store to do. Deliberately fact-shaped
 * (delaySeconds, errorText, phase) rather than sentence-shaped, so all copy stays
 * in the UI layer.
 */
export interface RunSink {
  applyUpsert(u: Upsert): void;
  /** The bubble is waiting behind a live run; render it as queued. */
  markQueued(key: string): void;
  markUnqueued(key: string): void;
  forgetBubble(key: string): void;
  /** Terminal response frame, or the equivalent verdict from a probe. */
  onRunFinished(status: string, errorText: string): void;
  onRateLimited(detail: string): void;
  onTransportError(detail: string): void;
  onStopFailed(detail: string): void;
  onRetrying(delaySeconds: number, detail: string): void;
  onGaveUp(): void;
  onPhase(phase: string): void;
  /** Reload bubbles; resolves true when the server still reports a live run. */
  resyncFromHistory(): Promise<boolean>;
}

class QueuedSend {
  key: string = '';
  parts: RequestPart[] = [];
}

/** Bridges SseSession callbacks into the controller without a shared counter. */
class FrameHandler implements SseHandler {
  private readonly owner: RunController;
  private readonly reconnecting: boolean;

  constructor(owner: RunController, reconnecting: boolean) {
    this.owner = owner;
    this.reconnecting = reconnecting;
  }

  onFrame(data: string, _meta: SseEvent): void {
    this.owner.handleFrame(data);
  }

  onClosed(status: number): void {
    this.owner.handleClosed(status, this.reconnecting);
  }

  onFailed(failure: Failure): void {
    this.owner.handleFailed(failure, this.reconnecting);
  }
}

export class RunController {
  private readonly api: ChatApi;
  private readonly sink: RunSink;
  private readonly reducer: StreamReducer;
  private readonly queue: QueuedSend[] = [];
  private session?: SseSession;
  private timer: number = -1;
  private attempts: number = 0;
  private terminalSeen: boolean = true;
  private replayEnded: boolean = false;
  /** True while a run this client typed is live, false for one it only watches. */
  private localRun: boolean = false;
  private phaseValue: string = RunPhase.IDLE;
  chatId: string = '';
  sessionId: string = '';
  userId: string = '';
  /** Composer choices carried on every send; the server stores none of them. */
  pref: ChatPreference = new ChatPreference();

  constructor(api: ChatApi, sink: RunSink, reducer: StreamReducer) {
    this.api = api;
    this.sink = sink;
    this.reducer = reducer;
  }

  /** Route params land here before the first history load. */
  bind(chatId: string, sessionId: string, userId: string): void {
    this.chatId = chatId;
    this.sessionId = sessionId;
    this.userId = userId;
  }

  phase(): string {
    return this.phaseValue;
  }

  /** True while the user's send is not free to start a fresh run. */
  busy(): boolean {
    return this.phaseValue !== RunPhase.IDLE;
  }

  queuedCount(): number {
    return this.queue.length;
  }

  /** Send now, or interrupt the live run and let this send queue behind it. */
  submit(key: string, parts: RequestPart[]): void {
    if (this.phaseValue === RunPhase.IDLE) {
      this.startRun(parts);
      return;
    }
    const item = new QueuedSend();
    item.key = key;
    item.parts = parts;
    this.queue.push(item);
    this.sink.markQueued(key);
    this.requestStop();
  }

  /** Pull a queued send back before it runs. */
  recall(key: string): void {
    for (let i = 0; i < this.queue.length; i++) {
      if (this.queue[i].key === key) {
        this.queue.splice(i, 1);
        this.sink.forgetBubble(key);
        return;
      }
    }
  }

  /** Attach to a run the PC console or another phone started on this session. */
  attach(): void {
    this.open(ChatApi.reconnectBody(this.sessionId, this.userId), true);
  }

  /** Stop button, and the interrupt half of a send-while-busy. */
  requestStop(): void {
    if (this.chatId.length === 0) {
      return;
    }
    const live = this.session !== undefined && this.session.isAlive();
    this.api.stop(this.chatId).then((): void => {
      if (!live && this.phaseValue !== RunPhase.IDLE) {
        // No stream to deliver the cancelled frame: probe once instead of waiting
        // for the next poll tick to release the UI.
        this.resync();
      }
    }).catch((e: Object): void => {
      this.sink.onStopFailed(Failure.from(e).message);
    });
  }

  /**
   * The single poll tick. Only acts when no stream is live: a running chat revives
   * a stale view, an idle one releases the UI and lets queued sends through.
   */
  probe(chatRunning: boolean): void {
    if (this.phaseValue !== RunPhase.IDLE && this.phaseValue !== RunPhase.STALE) {
      return;
    }
    if (this.phaseValue === RunPhase.STALE) {
      if (chatRunning) {
        this.attempts = 0;
        this.attach();
        return;
      }
      this.sink.onRunFinished(RunStatus.COMPLETED, '');
      this.finish();
      this.pullForeignTurn();
      return;
    }
    if (chatRunning) {
      this.attach();
      return;
    }
    this.drain();
  }

  /** Called after a successful history load that found the run still going. */
  adoptRunningHistory(): void {
    if (this.phaseValue === RunPhase.IDLE) {
      this.attach();
    }
  }

  dispose(): void {
    this.closeStream();
    this.clearTimer();
    this.queue.splice(0, this.queue.length);
    this.setPhase(RunPhase.IDLE);
  }

  private startRun(parts: RequestPart[]): void {
    this.open(ChatApi.bodyOf(this.sessionId, parts, this.userId, this.pref), false);
  }

  private open(bodyJson: string, isReconnect: boolean): void {
    this.closeStream();
    this.clearTimer();
    this.terminalSeen = false;
    this.replayEnded = false;
    this.localRun = !isReconnect;
    this.setPhase(RunPhase.STREAMING);
    this.session = this.api.stream(bodyJson, new FrameHandler(this, isReconnect));
  }

  /**
   * The user's message never rides the stream. The console SSE buffer only ever
   * holds assistant/tool frames, and the turn lands in persisted history from the
   * POST_RESPONSE hook that runs *before* the terminal frame, so once a run the
   * PC (or the other phone) started ends, the bubbles have to be reloaded or the
   * message the other side typed stays invisible until the page is re-entered.
   */
  private pullForeignTurn(): void {
    if (this.localRun || this.phaseValue !== RunPhase.IDLE) {
      return;
    }
    this.sink.resyncFromHistory().catch((e: Object): void => {
      this.sink.onTransportError(Failure.from(e).message);
    });
  }

  handleFrame(raw: string): void {
    const facts: StreamFacts = this.reducer.feed(raw);
    if (!facts.alive) {
      return;
    }
    // Any frame that lands proves the (re)connected stream works.
    this.attempts = 0;
    for (const u of facts.upserts) {
      this.sink.applyUpsert(u);
    }
    if (facts.replayEnd) {
      this.replayEnded = true;
    }
    if (facts.rateLimited.length > 0) {
      this.sink.onRateLimited(facts.rateLimited);
    }
    if (facts.transportError.length > 0) {
      // The server reported a verdict: reconnecting would only repeat it.
      this.terminalSeen = true;
      this.sink.onTransportError(facts.transportError);
      this.sink.onRunFinished(RunStatus.FAILED, facts.transportError);
      this.finish();
      this.pullForeignTurn();
      return;
    }
    if (facts.runStatus.length > 0) {
      this.terminalSeen = true;
      this.sink.onRunFinished(facts.runStatus, facts.runError);
      this.finish();
      this.pullForeignTurn();
    }
  }

  handleClosed(status: number, isReconnect: boolean): void {
    if (this.terminalSeen) {
      this.finish();
      return;
    }
    if (status === Http.CONFLICT && !isReconnect) {
      // Another client is generating in this session: replay and attach to it.
      this.attach();
      return;
    }
    if (this.replayEnded) {
      // Replayed a finished run whose terminal frame was not in the buffer.
      this.resync();
      return;
    }
    this.scheduleReconnect('');
  }

  handleFailed(failure: Failure, isReconnect: boolean): void {
    if (this.terminalSeen) {
      this.finish();
      return;
    }
    if (failure.isConflict() && !isReconnect) {
      this.attach();
      return;
    }
    if (failure.isTransient()) {
      this.scheduleReconnect(failure.message);
      return;
    }
    // 401/403/404 and parse errors will not fix themselves on retry.
    this.sink.onTransportError(failure.message);
    this.sink.onRunFinished(RunStatus.FAILED, failure.message);
    this.finish();
  }

  private scheduleReconnect(detail: string): void {
    if (this.attempts >= MAX_RECONNECT) {
      this.giveUp();
      return;
    }
    this.attempts += 1;
    const delaySeconds = 2 << (this.attempts - 1);
    this.setPhase(RunPhase.BACKOFF);
    this.sink.onRetrying(delaySeconds, detail);
    this.timer = setTimeout((): void => {
      this.timer = -1;
      this.resync();
    }, delaySeconds * 1000);
  }

  /** Reload bubbles, then re-attach while the run is still alive. */
  private resync(): void {
    this.sink.resyncFromHistory().then((running: boolean): void => {
      if (running) {
        this.attach();
        return;
      }
      this.terminalSeen = true;
      this.finish();
    }).catch((e: Object): void => {
      this.scheduleReconnect(Failure.from(e).message);
    });
  }

  private giveUp(): void {
    // busy stays true: the backend may still be generating, and probe() will
    // revive the stream or release the UI on the next tick.
    this.setPhase(RunPhase.STALE);
    this.sink.onGaveUp();
  }

  private finish(): void {
    this.closeStream();
    this.clearTimer();
    this.setPhase(RunPhase.IDLE);
    this.drain();
  }

  private drain(): void {
    if (this.queue.length === 0 || this.phaseValue !== RunPhase.IDLE) {
      return;
    }
    const next = this.queue[0];
    this.queue.splice(0, 1);
    this.sink.markUnqueued(next.key);
    this.startRun(next.parts);
  }

  private setPhase(phase: string): void {
    if (this.phaseValue === phase) {
      return;
    }
    this.phaseValue = phase;
    this.sink.onPhase(phase);
  }

  private closeStream(): void {
    const session = this.session;
    this.session = undefined;
    if (session !== undefined) {
      session.cancel();
    }
    this.reducer.clear();
  }

  private clearTimer(): void {
    if (this.timer >= 0) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
  }
}
