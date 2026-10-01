/**
 * Single source of truth for one chat window.
 *
 * Rules that keep the v1 defects out:
 *   - Membership changes publish a **new** array (so the page's @State re-renders);
 *     content changes mutate an @Observed UiMessage in place (so a token does not
 *     rebuild the list).
 *   - Reconnect reloads history but re-appends the queued bubbles instead of
 *     wiping them, which is how v1 lost an interjected message on every retry.
 *   - Nothing here polls: the page registers with GlobalPoller and forwards
 *     snapshots, so /api/chats is fetched once per tick for the whole app.
 */
import { ApprovalApi } from '../api/ApprovalApi';
import { ChatApi } from '../api/ChatApi';
import { UploadApi } from '../api/UploadApi';
import { Failure } from '../core/Failure';
import { ChatStatus, MsgType, Role, RunStatus, ToolTypes } from '../core/Wire';
import { MediaLoader, MediaValue } from '../media/MediaLoader';
import { Attachment } from '../model/Attachment';
import {
  ApprovalInfo,
  ChatHistory,
  ChatMessageModel,
  ChatRef,
  ChatSpec,
  RequestPart,
  UploadResult
} from '../model/Dtos';
import { PartTemplates, Parts } from '../model/Parts';
import { PollSnapshot, PollTarget } from '../polling/GlobalPoller';
import { StreamReducer, Upsert } from '../stream/StreamReducer';
import { RunController, RunPhase, RunSink } from '../stream/RunController';
import { Copy } from '../l10n/Copy';
import { NoticeTone, UiKind, UiMessage } from './UiMessage';

/** Wire copy for part labels, sourced from Copy.ets instead of hardcoded. */
function partTemplates(): PartTemplates {
  const t = new PartTemplates();
  t.image = Copy.chat_part_image;
  t.video = Copy.chat_part_video;
  t.fileTemplate = Copy.chat_part_file;
  t.unknownTool = Copy.chat_default_tool_name;
  t.outputSuffix = Copy.chat_tool_output_suffix;
  return t;
}

export class ChatStore implements RunSink, PollTarget {
  readonly ref: ChatRef;
  items: UiMessage[] = [];
  approvals: ApprovalInfo[] = [];
  bgRunning: ChatSpec[] = [];
  phase: string = RunPhase.IDLE;
  loading: boolean = true;
  uploading: boolean = false;
  /** Seconds stamp for the approval countdown; a plain field the page mirrors. */
  nowSec: number = Math.floor(Date.now() / 1000);
  /**
   * Bumped when an image lands. Decoding changes a bubble's height long after the
   * history scroll settled, so the page cannot tell from the item list alone that
   * it has to stick to the tail again.
   */
  mediaRev: number = 0;

  private readonly api: ChatApi;
  private readonly uploadApi: UploadApi;
  private readonly approvalApi: ApprovalApi;
  private readonly media: MediaLoader;
  private readonly templates: PartTemplates;
  private readonly controller: RunController;
  private views: Array<() => void> = [];
  private noticeSeq: number = 0;
  private clock: number = -1;

  constructor(ref: ChatRef, api: ChatApi, uploadApi: UploadApi, approvalApi: ApprovalApi,
    media: MediaLoader) {
    this.ref = ref;
    this.api = api;
    this.uploadApi = uploadApi;
    this.approvalApi = approvalApi;
    this.media = media;
    this.templates = partTemplates();
    this.controller = new RunController(api, this, new StreamReducer(this.templates));
    this.controller.bind(ref.chatId, ref.sessionId, ref.userId);
  }

  // ---------- view plumbing ----------

  /**
   * A page subscribes with the closure it created once, so detach can identify it.
   * Closures rather than a view interface because an ArkUI struct cannot implement
   * one.
   */
  attachView(onChange: () => void): void {
    if (this.views.indexOf(onChange) < 0) {
      this.views.push(onChange);
    }
    this.startClock();
  }

  detachView(onChange: () => void): void {
    const index = this.views.indexOf(onChange);
    if (index >= 0) {
      this.views.splice(index, 1);
    }
    if (this.views.length === 0) {
      this.stopClock();
    }
  }

  /**
   * A second clock, 1s, purely for the approval countdown: it touches no network.
   * It only runs while a view is attached, so a backgrounded page stops ticking.
   */
  private startClock(): void {
    if (this.clock >= 0) {
      return;
    }
    this.clock = setInterval((): void => {
      if (this.approvals.length === 0) {
        return;
      }
      this.nowSec = Math.floor(Date.now() / 1000);
      this.emit();
    }, 1000);
  }

  private stopClock(): void {
    if (this.clock >= 0) {
      clearInterval(this.clock);
      this.clock = -1;
    }
  }

  private emit(): void {
    for (const view of this.views.slice()) {
      view();
    }
  }

  dispose(): void {
    this.controller.dispose();
    this.stopClock();
    this.views = [];
  }

  // ---------- public actions ----------

  busy(): boolean {
    return this.controller.busy();
  }

  /** Route params are known only after the page opens, so bind late too. */
  rebind(chatId: string, sessionId: string, userId: string): void {
    this.controller.bind(chatId, sessionId, userId);
  }

  async bootstrap(): Promise<void> {
    this.loading = true;
    this.emit();
    try {
      const h: ChatHistory = await this.api.history(this.ref.chatId);
      this.replaceFromHistory(h);
      if (h.status === ChatStatus.RUNNING) {
        this.controller.adoptRunningHistory();
      }
    } catch (e) {
      this.pushNotice(Copy.fill(Copy.notice_history_failed, Failure.from(e as Object).message),
        NoticeTone.ERROR);
    } finally {
      this.loading = false;
      this.emit();
    }
  }

  /** Send now, or interrupt the live run and queue this message behind it. */
  async send(text: string, attachments: Attachment[]): Promise<void> {
    const trimmed = text.trim();
    if (trimmed.length === 0 && attachments.length === 0) {
      return;
    }
    let uploads: UploadResult[] = [];
    if (attachments.length > 0) {
      this.uploading = true;
      this.emit();
      try {
        uploads = await this.uploadApi.uploadAll(attachments);
      } catch (e) {
        this.uploading = false;
        this.emit();
        this.pushNotice(Copy.fill(Copy.notice_upload_failed, Failure.from(e as Object).message),
          NoticeTone.ERROR);
        return;
      }
      this.uploading = false;
    }
    const mimes: string[] = attachments.map((a: Attachment): string => a.mime);
    const parts = ChatApi.buildParts(trimmed, uploads, mimes);
    const bubble = this.addUserBubble(trimmed, uploads);
    this.controller.submit(bubble.key, parts);
    this.emit();
  }

  recallQueued(key: string): void {
    this.controller.recall(key);
  }

  stopRun(): void {
    this.controller.requestStop();
  }

  /** The user's decision is never made for them: this only fires on a tap. */
  async decide(approval: ApprovalInfo, approved: boolean): Promise<void> {
    const display = approval.tool_display_name.length > 0
      ? approval.tool_display_name : approval.tool_name;
    try {
      if (approved) {
        const resp = await this.approvalApi.approve(approval, this.ref.userId);
        const serverMessage = Parts.str(resp.message);
        this.pushNotice(Copy.fill(Copy.approval_approved,
          serverMessage.length > 0 ? serverMessage : display), NoticeTone.MUTED);
      } else {
        await this.approvalApi.deny(approval, Copy.approval_denied_reason, this.ref.userId);
        this.pushNotice(Copy.fill(Copy.approval_denied, display), NoticeTone.MUTED);
      }
      this.dropApproval(approval.request_id);
      // The blocked run resumes server-side. If no stream is live the next poll
      // tick is up to 10s away, so re-attach now instead of leaving the bubble dry.
      if (!this.controller.busy()) {
        this.controller.attach();
      }
    } catch (e) {
      this.pushNotice(Copy.fill(Copy.notice_approval_failed, Failure.from(e as Object).message),
        NoticeTone.ERROR);
    }
  }

  /** The page owns the picker, so its failures still have to reach the notice feed. */
  reportPickFailure(detail: string): void {
    this.pushNotice(Copy.fill(Copy.notice_pick_failed, detail), NoticeTone.ERROR);
  }

  onPoll(snapshot: PollSnapshot): void {
    const mine: ApprovalInfo[] = [];
    const bg: ChatSpec[] = [];
    let running = false;
    for (const a of snapshot.approvals) {
      if (ApprovalApi.belongsTo(a, this.ref.sessionId)) {
        mine.push(a);
      }
    }
    for (const c of snapshot.chats) {
      if (c.id === this.ref.chatId) {
        running = c.status === ChatStatus.RUNNING;
      } else if (c.status === ChatStatus.RUNNING) {
        bg.push(c);
      }
    }
    this.approvals = mine;
    this.bgRunning = bg;
    this.nowSec = Math.floor(Date.now() / 1000);
    this.controller.probe(running);
    this.emit();
  }

  // ---------- RunSink ----------

  applyUpsert(u: Upsert): void {
    const index = this.indexOf(u.key);
    if (index < 0) {
      const created = new UiMessage();
      created.key = u.key;
      created.kind = u.kind;
      created.role = u.role;
      created.name = u.name;
      created.text = u.text;
      created.streaming = u.streaming;
      created.imageRef = u.imageUrl;
      this.push(created);
      this.requestImage(created);
      this.emit();
      return;
    }
    const held = this.items[index];
    held.kind = u.kind;
    held.name = u.name;
    held.text = u.text;
    held.streaming = u.streaming;
    if (u.imageUrl.length > 0 && held.imageRef !== u.imageUrl) {
      held.imageRef = u.imageUrl;
      held.image = undefined;
      held.imageRequested = false;
      this.requestImage(held);
    }
    this.emit();
  }

  markQueued(key: string): void {
    const index = this.indexOf(key);
    if (index < 0) {
      return;
    }
    this.items[index].kind = UiKind.QUEUED;
    this.emit();
  }

  markUnqueued(key: string): void {
    const index = this.indexOf(key);
    if (index < 0) {
      return;
    }
    const m = this.items[index];
    m.kind = m.text.length > 0 ? UiKind.TEXT : UiKind.QUEUED;
    m.streaming = false;
    this.emit();
  }

  forgetBubble(key: string): void {
    const index = this.indexOf(key);
    if (index >= 0) {
      this.spliceAt(index);
    }
  }

  onRunFinished(status: string, errorText: string): void {
    this.finishStreaming();
    if (status === RunStatus.FAILED) {
      this.pushNotice(Copy.fill(Copy.notice_generation_failed,
        errorText.length > 0 ? errorText : Copy.notice_unknown_error), NoticeTone.ERROR);
    } else if (status === RunStatus.CANCELLED) {
      this.pushNotice(Copy.notice_stopped, NoticeTone.MUTED);
    }
    this.emit();
  }

  onRateLimited(detail: string): void {
    this.pushNotice(Copy.fill(Copy.notice_rate_limited, detail), NoticeTone.ERROR);
  }

  onTransportError(detail: string): void {
    this.pushNotice(detail, NoticeTone.ERROR);
  }

  onStopFailed(detail: string): void {
    this.pushNotice(Copy.fill(Copy.notice_stop_failed, detail), NoticeTone.ERROR);
  }

  onRetrying(delaySeconds: number, detail: string): void {
    const text = detail.length > 0
      ? Copy.fillN2(Copy.notice_interrupted_with, detail, delaySeconds)
      : Copy.fillN(Copy.notice_interrupted, delaySeconds);
    this.pushNotice(text, NoticeTone.MUTED);
  }

  onGaveUp(): void {
    this.pushNotice(Copy.notice_reconnect_failed, NoticeTone.ERROR);
  }

  onPhase(phase: string): void {
    this.phase = phase;
    this.emit();
  }

  async resyncFromHistory(): Promise<boolean> {
    const h: ChatHistory = await this.api.history(this.ref.chatId);
    this.replaceFromHistory(h);
    return h.status === ChatStatus.RUNNING;
  }

  // ---------- internals ----------

  /** Rebuild from the server, keeping queued sends so a retry cannot eat them. */
  private replaceFromHistory(h: ChatHistory): void {
    const rebuilt: UiMessage[] = [];
    for (const m of h.messages) {
      const ui = this.toUi(m);
      if (ui !== undefined) {
        rebuilt.push(ui);
      }
    }
    for (const m of this.items) {
      if (m.kind === UiKind.QUEUED) {
        rebuilt.push(m);
      }
    }
    this.items = rebuilt;
    for (const m of rebuilt) {
      this.requestImage(m);
    }
    this.emit();
  }

  private toUi(src: ChatMessageModel): UiMessage | undefined {
    const m = new UiMessage();
    m.key = src.id;
    m.role = src.role === Role.USER ? Role.USER : Role.ASSISTANT;
    const type = src.type;
    if (ToolTypes.isTool(type)) {
      const data = Parts.firstData(src.content);
      m.kind = UiKind.TOOL;
      m.name = Parts.toolName(data, this.templates)
        + (ToolTypes.isOutput(type) ? this.templates.outputSuffix : '');
      m.text = Parts.clip(Parts.asText(ToolTypes.isOutput(type) ? data?.output : data?.arguments),
        this.templates.toolClipChars);
      return m;
    }
    if (type === MsgType.REASONING) {
      m.kind = UiKind.REASONING;
      m.text = Parts.displayText(src.content, this.templates);
    } else {
      m.kind = UiKind.TEXT;
      m.text = Parts.displayText(src.content, this.templates);
      m.imageRef = Parts.firstImage(src.content);
    }
    if (m.text.length === 0 && m.imageRef.length === 0) {
      return undefined;
    }
    return m;
  }

  private addUserBubble(text: string, uploads: UploadResult[]): UiMessage {
    const m = new UiMessage();
    m.key = `local_${Date.now()}_${this.noticeSeq}`;
    this.noticeSeq += 1;
    m.role = Role.USER;
    m.kind = UiKind.TEXT;
    if (text.length > 0) {
      m.text = text;
    } else {
      const names: string[] = uploads.map((u: UploadResult): string =>
        Copy.fill(Copy.chat_attachment_line, u.file_name));
      m.text = names.join('\n');
    }
    for (const up of uploads) {
      if (m.imageRef.length === 0 && UploadApi.mimeFromName(up.file_name).startsWith('image/')) {
        m.imageRef = up.url;
      }
    }
    this.push(m);
    this.requestImage(m);
    return m;
  }

  /** Header-authenticated byte fetch -> PixelMap; never a token in a URL. */
  private requestImage(m: UiMessage): void {
    if (m.imageRef.length === 0 || m.imageRequested) {
      return;
    }
    m.imageRequested = true;
    this.media.load(m.imageRef).then((value: MediaValue): void => {
      m.image = value;
      this.mediaRev += 1;
      this.emit();
    });
  }

  private finishStreaming(): void {
    for (const m of this.items) {
      if (m.streaming) {
        m.streaming = false;
      }
    }
  }

  private indexOf(key: string): number {
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].key === key) {
        return i;
      }
    }
    return -1;
  }

  /** New array reference, or the page's @State would not see the change. */
  private push(msg: UiMessage): void {
    const copy = this.items.slice();
    copy.push(msg);
    this.items = copy;
  }

  private spliceAt(index: number): void {
    const copy = this.items.slice();
    copy.splice(index, 1);
    this.items = copy;
    this.emit();
  }

  private dropApproval(requestId: string): void {
    const kept: ApprovalInfo[] = [];
    for (const a of this.approvals) {
      if (a.request_id !== requestId) {
        kept.push(a);
      }
    }
    this.approvals = kept;
    this.emit();
  }

  private pushNotice(text: string, tone: string): void {
    const m = new UiMessage();
    m.key = `notice_${Date.now()}_${this.noticeSeq}`;
    this.noticeSeq += 1;
    m.kind = UiKind.NOTICE;
    m.role = Role.SYSTEM;
    m.text = text;
    m.tone = tone;
    this.push(m);
    this.emit();
  }
}
