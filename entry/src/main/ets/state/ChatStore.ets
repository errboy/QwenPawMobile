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
import { common } from '@kit.AbilityKit';
import { ApprovalApi } from '../api/ApprovalApi';
import { ChatApi } from '../api/ChatApi';
import { UploadApi } from '../api/UploadApi';
import { Failure } from '../core/Failure';
import { nowStamp, stampText } from '../core/Format';
import { ChatPreferences } from '../core/Prefs';
import { ChatStatus, ContentType, MsgType, Role, RunStatus, ToolTypes } from '../core/Wire';
import { MediaLoader, MediaValue } from '../media/MediaLoader';
import { AudioPlayer } from '../media/AudioPlayer';
import { Export } from '../media/Export';
import { Attachment } from '../model/Attachment';
import { ChatPreference, SentMedia } from '../model/ChatPrefs';
import {
  ApprovalInfo,
  ChatHistory,
  ChatMessageModel,
  ChatRef,
  ChatSpec,
  LoopModeInfo,
  UploadResult
} from '../model/Dtos';
import { LoopModes } from '../model/LoopModes';
import { PartTemplates, Parts } from '../model/Parts';
import { POLL_INTERVAL_MS, PollSnapshot, PollTarget } from '../polling/GlobalPoller';
import { StreamReducer, Upsert } from '../stream/StreamReducer';
import { RunController, RunPhase, RunSink } from '../stream/RunController';
import { Copy } from '../l10n/Copy';
import { NoticeTone, UiKind, UiMessage } from './UiMessage';

/** Wire copy for part labels, sourced from Copy.ets instead of hardcoded. */
function partTemplates(): PartTemplates {
  const t = new PartTemplates();
  t.image = Copy.chat_part_image;
  t.video = Copy.chat_part_video;
  t.audio = Copy.chat_part_audio;
  t.fileTemplate = Copy.chat_part_file;
  t.unknownTool = Copy.chat_default_tool_name;
  t.inlineFile = Copy.chat_file_inline;
  t.outputSuffix = Copy.chat_tool_output_suffix;
  return t;
}

/**
 * Sends one chat keeps a media echo for, newest last. It is a display aid for the
 * turns this phone sent, and the ones a user still scrolls to are the recent ones;
 * an older turn simply comes back the way it does on the desktop.
 */
const MAX_SENT_MEDIA: number = 20;

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

  /** The finish stamp this window last saw for its own chat, from the poller. */
  private seenFinishedAt: string = '';
  /** When history was last reloaded, so the poller does not fetch it twice. */
  private lastPullSec: number = 0;

  private readonly api: ChatApi;
  private readonly uploadApi: UploadApi;
  private readonly approvalApi: ApprovalApi;
  private readonly media: MediaLoader;
  private readonly audio: AudioPlayer;
  private readonly templates: PartTemplates;
  private readonly controller: RunController;
  private views: Array<() => void> = [];
  private noticeSeq: number = 0;
  private clock: number = -1;

  constructor(ref: ChatRef, api: ChatApi, uploadApi: UploadApi, approvalApi: ApprovalApi,
    media: MediaLoader, audio: AudioPlayer) {
    this.ref = ref;
    this.api = api;
    this.uploadApi = uploadApi;
    this.approvalApi = approvalApi;
    this.media = media;
    this.audio = audio;
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
    this.stopAudio();
  }

  // ---------- public actions ----------

  busy(): boolean {
    return this.controller.busy();
  }

  /** Route params are known only after the page opens, so bind late too. */
  rebind(chatId: string, sessionId: string, userId: string): void {
    this.controller.bind(chatId, sessionId, userId);
  }

  // ---------- composer preferences ----------
  /** Loop catalog, kept here so a send can resolve a mode without refetching. */
  private loopModes: LoopModeInfo[] = [];

  setLoopModes(modes: LoopModeInfo[]): void {
    this.loopModes = modes;
  }

  /** Live composer choices. Empty fields mean 'follow the PC agent's default'. */
  prefs(): ChatPreference {
    return this.controller.pref;
  }

  /**
   * Load this chat's stored choices. The server keeps no per-session copy of the
   * approval level or the model slot, so the phone is the only place they exist.
   */
  async restorePrefs(ctx: common.Context): Promise<void> {
    const stored = await ChatPreferences.get(ctx, this.ref.chatId);
    stored.chatId = this.ref.chatId;
    this.controller.pref = stored;
    this.emit();
  }

  async savePrefs(ctx: common.Context, pref: ChatPreference): Promise<void> {
    pref.chatId = this.ref.chatId;
    this.controller.pref = pref;
    await ChatPreferences.set(ctx, pref);
    this.emit();
  }

  /**
   * Persist the composer draft. Deliberately does not emit: the text on screen is
   * already the source of truth while the page is open, and an emit per keystroke
   * would re-render the whole conversation.
   */
  async saveDraft(ctx: common.Context, draft: string): Promise<void> {
    const pref = this.controller.pref;
    if (pref.draft === draft) {
      return;
    }
    pref.draft = draft;
    pref.chatId = this.ref.chatId;
    await ChatPreferences.set(ctx, pref);
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
  async send(ctx: common.Context | undefined, text: string,
    attachments: Attachment[]): Promise<void> {
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
    // The loop mode is a prefix on the text, not a field on the body, and a live
    // run must not have a second command queued in front of it.
    const wire = LoopModes.apply(trimmed, this.loopModes, this.controller.pref.loopSlash,
      !this.controller.busy());
    const parts = ChatApi.buildParts(wire, uploads, mimes);
    const bubble = this.addUserBubble(wire, uploads, mimes);
    // Recorded before the run opens: the point of the echo is that the media is
    // still here after a reload, and a reload can happen the moment the turn ends.
    // No context means no record, which costs a thumbnail and never the send.
    let cid: string = '';
    if (uploads.length > 0 && ctx !== undefined) {
      cid = await this.rememberSentMedia(ctx, bubble);
    }
    this.controller.submit(bubble.key, parts, cid);
    this.emit();
  }

  recallQueued(key: string): void {
    this.controller.recall(key);
  }

  stopRun(): void {
    this.controller.requestStop();
  }

  /**
   * One tap plays a clip, the next stops it. The player is app-wide, so starting
   * here also silences whichever bubble was holding the speaker before.
   */
  async playAudio(m: UiMessage): Promise<void> {
    if (m.audioRef.length === 0) {
      return;
    }
    if (this.audio.current() === m.key) {
      this.audio.stop();
      return;
    }
    const source = await this.media.audioSource(m.audioRef);
    if (source.length === 0) {
      this.pushNotice(Copy.chat_audio_unavailable, NoticeTone.ERROR);
      return;
    }
    m.audioPlaying = true;
    this.emit();
    this.audio.play(m.key, source, (key: string): void => {
      this.clearPlaying(key);
    }, (message: string): void => {
      this.clearPlaying(m.key);
      this.pushNotice(Copy.fill(Copy.notice_audio_failed, message), NoticeTone.ERROR);
    });
  }

  /** Leaving a window must not leave its voice note playing behind the page. */
  stopAudio(): void {
    if (this.audio.current().length > 0 && this.indexOf(this.audio.current()) >= 0) {
      this.audio.stop();
    }
  }

  private clearPlaying(key: string): void {
    const index = this.indexOf(key);
    if (index >= 0) {
      this.items[index].audioPlaying = false;
      this.emit();
    }
  }

  /**
   * Open a document in an app on the phone. Its bytes live on the PC, so they are
   * fetched into the media cache first — the same copy the asset panel would save —
   * and only then handed to whichever reader the system matches. A second tap while
   * the first is still fetching does nothing: two copies of one file, opened twice,
   * reads as the app being slow rather than as a busy flag nobody honoured.
   */
  async openFile(ctx: common.Context, m: UiMessage): Promise<void> {
    if (m.fileRef.length === 0 || m.fileBusy) {
      return;
    }
    m.fileBusy = true;
    this.emit();
    try {
      const name = m.fileName.length > 0 ? m.fileName : m.fileRef;
      const path = await this.media.localPath(m.fileRef);
      if (path.length === 0) {
        this.pushNotice(Copy.fill(Copy.assets_fetch_failed, Parts.leafOf(name)), NoticeTone.ERROR);
        return;
      }
      const detail = await Export.open(ctx as common.UIAbilityContext, path, name);
      if (detail.length > 0) {
        this.pushNotice(detail, NoticeTone.ERROR);
      }
    } finally {
      m.fileBusy = false;
      this.emit();
    }
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

  /** Files the picker handed over but the phone will not upload. */
  reportPickSkipped(detail: string): void {
    if (detail.length > 0) {
      this.pushNotice(Copy.fill(Copy.notice_pick_skipped, detail), NoticeTone.MUTED);
    }
  }

  /** A recording that never became a file, including a refused microphone. */
  reportVoiceFailure(detail: string): void {
    this.pushNotice(detail, NoticeTone.ERROR);
  }

  onPoll(snapshot: PollSnapshot): void {
    const mine: ApprovalInfo[] = [];
    const bg: ChatSpec[] = [];
    let running = false;
    let finishedAt = '';
    for (const a of snapshot.approvals) {
      if (ApprovalApi.belongsTo(a, this.ref.sessionId)) {
        mine.push(a);
      }
    }
    for (const c of snapshot.chats) {
      if (c.id === this.ref.chatId) {
        running = c.status === ChatStatus.RUNNING;
        // The desktop sends null until this chat's first run ever finishes.
        finishedAt = c.last_finished_at === null ? '' : c.last_finished_at;
      } else if (c.status === ChatStatus.RUNNING) {
        bg.push(c);
      }
    }
    this.approvals = mine;
    this.bgRunning = bg;
    this.nowSec = Math.floor(Date.now() / 1000);
    this.controller.probe(running);
    this.catchUpTurn(finishedAt);
    this.emit();
  }

  /**
   * Catch a turn this window never watched. A run that starts and finishes inside
   * one 10s gap is never attached to, and even when it is attached the stream
   * never carries the other side's own message, so the chat's finish stamp is the
   * only remaining evidence that the transcript moved without us.
   */
  private catchUpTurn(finishedAt: string): void {
    if (finishedAt.length === 0 || finishedAt === this.seenFinishedAt) {
      return;
    }
    const firstSighting = this.seenFinishedAt.length === 0;
    this.seenFinishedAt = finishedAt;
    if (firstSighting || this.controller.busy() || this.pulledRecently()) {
      return;
    }
    this.resyncFromHistory().catch((e: Object): void => {
      this.pushNotice(Copy.fill(Copy.notice_history_failed, Failure.from(e).message),
        NoticeTone.ERROR);
    });
  }

  /** True while a reload from the run's own terminal frame still covers this turn. */
  private pulledRecently(): boolean {
    return this.lastPullSec > 0
      && Math.floor(Date.now() / 1000) - this.lastPullSec < POLL_INTERVAL_MS / 1000;
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
      created.videoRef = u.videoUrl;
      created.audioRef = u.audioUrl;
      created.fileRef = u.fileUrl;
      created.fileName = u.fileName;
      // A live turn has no server instant yet — the stream carries none — so the
      // phone stamps its own. The reload that follows replaces it with the server's.
      created.stamp = nowStamp();
      this.push(created);
      this.requestImage(created);
      this.requestVideo(created);
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
    if (u.videoUrl.length > 0) {
      const moved = held.videoRef !== u.videoUrl;
      held.videoRef = u.videoUrl;
      if (moved) {
        held.video = undefined;
        held.videoRequested = false;
        this.requestVideo(held);
      }
    }
    if (u.audioUrl.length > 0) {
      held.audioRef = u.audioUrl;
    }
    if (u.fileUrl.length > 0 || u.fileName.length > 0) {
      held.fileRef = u.fileUrl;
      held.fileName = u.fileName;
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

  /**
   * Marks the bubble as one the server refused to take, which also makes it
   * survive the history rebuild that follows: an ordinary optimistic bubble is
   * dropped there because a rebuild assumes every message it removed went out.
   * Without this the user's text disappears with no trace of the rejected send.
   */
  onSendUndelivered(key: string): void {
    const index = this.indexOf(key);
    if (index < 0) {
      return;
    }
    const m = this.items[index];
    m.undelivered = true;
    m.streaming = false;
    this.pushNotice(Copy.notice_undelivered, NoticeTone.ERROR);
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
    this.pushNotice(text, NoticeTone.RETRYING);
  }

  /**
   * Drop the pending-reconnect lines. The controller calls this whenever the wait
   * they describe stops being the current one — the link is demonstrated to work
   * again, the wait ends for good, or the ladder moves to its next rung — because
   * nothing else makes them stop being true, and history reloads keep every notice
   * on purpose. Left alone, a screen the connection has long since recovered shows
   * "reconnecting in 2 seconds" forever, and each retry attempt adds another.
   */
  retireRetrying(): void {
    const kept: UiMessage[] = [];
    for (const m of this.items) {
      if (m.kind === UiKind.NOTICE && m.tone === NoticeTone.RETRYING) {
        continue;
      }
      kept.push(m);
    }
    if (kept.length === this.items.length) {
      return;
    }
    this.items = kept;
    this.emit();
  }

  onGaveUp(): void {
    this.pushNotice(Copy.notice_reconnect_failed, NoticeTone.ERROR);
  }

  onPhase(phase: string): void {
    this.phase = phase;
    this.emit();
  }

  async resyncFromHistory(): Promise<boolean> {
    this.lastPullSec = Math.floor(Date.now() / 1000);
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
      // Notices are the phone's own commentary and never come back from history,
      // so a rebuild that dropped them would silently erase "stopped" / "failed"
      // lines the user had just been told about. An undelivered send is kept for
      // the same reason: the server has no copy of it, so history cannot bring it
      // back either.
      if (m.kind === UiKind.QUEUED || m.kind === UiKind.NOTICE || m.undelivered) {
        rebuilt.push(m);
      }
    }
    this.items = rebuilt;
    for (const m of rebuilt) {
      this.requestImage(m);
      this.requestVideo(m);
    }
    this.emit();
  }

  private toUi(src: ChatMessageModel): UiMessage | undefined {
    const m = new UiMessage();
    m.key = src.id;
    m.role = src.role === Role.USER ? Role.USER : Role.ASSISTANT;
    // The reply's landing time beats the turn's creation time: a turn with long
    // tool calls is created long before it answers, and the asset list reads as
    // "this arrived now". Legacy rows carry no finished_at.
    const meta = src.metadata;
    m.stamp = stampText(Parts.str(meta?.finished_at ?? meta?.timestamp));
    const type = src.type;
    if (ToolTypes.isTool(type)) {
      const data = Parts.firstData(src.content);
      m.kind = UiKind.TOOL;
      m.name = Parts.toolName(data, this.templates)
        + (ToolTypes.isOutput(type) ? this.templates.outputSuffix : '');
      m.text = Parts.clip(Parts.asText(ToolTypes.isOutput(type) ? data?.output : data?.arguments),
        this.templates.toolClipChars);
      // History keeps a sent file the same way the stream does — inside the tool's
      // output — so reopening a chat has to list those files too, or the transcript
      // the user watched fill up would lose its attachments on the way back.
      const media = ToolTypes.isOutput(type)
        ? Parts.toolMedia(src.content, this.templates) : undefined;
      const files = media === undefined ? [] : media.files;
      if (files.length > 0) {
        for (const f of files) {
          if (f.kind === ContentType.IMAGE) {
            m.imageRef = f.ref;
          } else if (f.kind === ContentType.VIDEO) {
            m.videoRef = f.ref;
          } else if (f.kind === ContentType.AUDIO) {
            m.audioRef = f.ref;
          } else {
            m.fileRef = f.ref;
            m.fileName = f.name;
          }
        }
        m.text = Parts.clip(Parts.str(media?.text), this.templates.toolClipChars);
      }
      return m;
    }
    if (type === MsgType.REASONING) {
      m.kind = UiKind.REASONING;
      m.text = Parts.displayText(src.content, this.templates);
    } else {
      m.kind = UiKind.TEXT;
      m.text = Parts.displayText(src.content, this.templates);
      m.imageRef = Parts.firstImage(src.content);
      m.videoRef = Parts.firstVideo(src.content);
      m.audioRef = Parts.firstAudio(src.content);
      const file = Parts.firstFile(src.content);
      if (file !== undefined) {
        m.fileRef = file.url;
        m.fileName = file.name;
      }
    }
    if (m.role === Role.USER) {
      this.applySentMedia(src, m);
    }
    if (m.text.length === 0 && m.imageRef.length === 0
      && m.videoRef.length === 0 && m.audioRef.length === 0
      && m.fileRef.length === 0 && m.fileName.length === 0) {
      return undefined;
    }
    return m;
  }

  /**
   * The echo shown the instant the message leaves, before the server answers.
   *
   * It is built from the same labelling, the same mime list and the same refs as
   * toUi(), which is what replaces it once history comes back: an echo that named a
   * take 'voice-1791121878906.m4a' would watch its own attachment turn into '[语音]'
   * a few seconds later, and a name that only ever existed on this phone is not
   * something the transcript can agree with. The mimes are read the way
   * ChatApi.buildParts reads them, because the type that server part got is the
   * type this bubble has to show — the stored name is the server's to choose.
   */
  private addUserBubble(text: string, uploads: UploadResult[], mimes: string[]): UiMessage {
    const m = new UiMessage();
    m.key = `local_${Date.now()}_${this.noticeSeq}`;
    this.noticeSeq += 1;
    m.role = Role.USER;
    m.kind = UiKind.TEXT;
    m.stamp = nowStamp();
    let labels = '';
    for (let i = 0; i < uploads.length; i++) {
      const up = uploads[i];
      const type = ContentType.forMime(i < mimes.length ? mimes[i] : '');
      labels += Parts.label(type, up.file_name, this.templates);
      if (type === ContentType.IMAGE && m.imageRef.length === 0) {
        m.imageRef = up.url;
      } else if (type === ContentType.VIDEO && m.videoRef.length === 0) {
        m.videoRef = up.url;
      } else if (type === ContentType.AUDIO && m.audioRef.length === 0) {
        m.audioRef = up.url;
      } else if (type === ContentType.FILE && m.fileRef.length === 0) {
        // The sent clip is addressable by its stored path, so the phone previews
        // and replays it exactly the way it plays one received from the PC.
        m.fileRef = up.url;
        m.fileName = up.file_name;
      }
    }
    m.text = `${text}${labels}`;
    this.push(m);
    this.requestImage(m);
    this.requestVideo(m);
    return m;
  }

  /**
   * Keep what this phone just showed for an outgoing turn, so its own media can be
   * put back after a history reload.
   *
   * The server stores a turn's attachments for history only when that turn carried
   * a `file` part, so an uploaded image comes back as the model-facing sentence the
   * desktop built — on the desktop's own client too (docs/07 §8.1). The id written
   * into the message metadata is what ties a history row back to this record: the
   * history `id` is re-minted per request, so nothing else on the wire identifies
   * a turn this phone sent. Once the desktop starts echoing attachments the record
   * simply stops matching, and the phone shows the server's answer.
   *
   * Resolves to the id to stamp on the request.
   */
  private async rememberSentMedia(ctx: common.Context, bubble: UiMessage): Promise<string> {
    const rec = new SentMedia();
    rec.cid = `cm_${Date.now()}_${this.noticeSeq}`;
    rec.imageRef = bubble.imageRef;
    rec.videoRef = bubble.videoRef;
    rec.audioRef = bubble.audioRef;
    rec.fileRef = bubble.fileRef;
    rec.fileName = bubble.fileName;
    const pref = this.controller.pref;
    const kept = pref.sentMedia.concat([rec]);
    pref.sentMedia = kept.length > MAX_SENT_MEDIA
      ? kept.slice(kept.length - MAX_SENT_MEDIA) : kept;
    await ChatPreferences.set(ctx, pref);
    return rec.cid;
  }

  /**
   * Paste the phone's own attachments back into a history row that arrived without
   * any. Only a row that carries this phone's id and has nothing of its own to show
   * qualifies, so a turn the server did render is never overwritten and a message
   * sent from the PC is never claimed.
   */
  private applySentMedia(src: ChatMessageModel, m: UiMessage): void {
    const cid = src.metadata?.metadata?.qwenpaw_client_message_id ?? '';
    if (cid.length === 0) {
      return;
    }
    if (m.imageRef.length > 0 || m.videoRef.length > 0 || m.audioRef.length > 0
      || m.fileRef.length > 0 || m.fileName.length > 0) {
      return;
    }
    for (const rec of this.controller.pref.sentMedia) {
      if (rec.cid !== cid) {
        continue;
      }
      m.imageRef = rec.imageRef;
      m.videoRef = rec.videoRef;
      m.audioRef = rec.audioRef;
      m.fileRef = rec.fileRef;
      m.fileName = rec.fileName;
      return;
    }
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

  /**
   * Same byte path as an image, but the result is a file the player opens rather
   * than a bitmap: a Video component cannot carry the bearer header.
   */
  private requestVideo(m: UiMessage): void {
    if (m.videoRef.length === 0 || m.videoRequested) {
      return;
    }
    m.videoRequested = true;
    this.media.videoSource(m.videoRef).then((value: MediaValue): void => {
      m.video = value;
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
