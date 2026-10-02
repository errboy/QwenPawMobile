/**
 * One chat window.
 *
 * The page is a mirror of ChatStore: it registers the store with the app-wide
 * poller, re-renders when the store emits, and forwards taps back. All run
 * scheduling, frame merging and reconnect policy live behind the store.
 */
import { common } from '@kit.AbilityKit';
import { KeyboardAvoidMode } from '@kit.ArkUI';
import { Bubble } from '../ui/chat/Bubble';
import { ApprovalCard } from '../ui/chat/ApprovalCard';
import { Composer } from '../ui/chat/Composer';
import { AppButton } from '../ui/common/AppButton';
import { VoiceNote } from '../media/VoiceNote';
import { AppColor, AppMotion, AppRadius, AppSize, AppSpace, AppType } from '../theme/Theme';
import { Copy } from '../l10n/Copy';
import { Attachment, AttachSource } from '../model/Attachment';
import { PickOutcome } from '../api/UploadApi';
import { Choice, SelectorKey, SelectorSpec } from '../model/Choices';
import { ApprovalInfo, ChatRef, ChatSpec, LoopModeInfo, ModelSlot, ProviderInfo, SlashCommand } from '../model/Dtos';
import { LoopModes } from '../model/LoopModes';
import { ModelOption, Providers } from '../model/Providers';
import { Parts } from '../model/Parts';
import { ApprovalLevel, Role } from '../core/Wire';
import { Failure } from '../core/Failure';
import { Log } from '../core/Log';
import { UiMessage } from '../state/UiMessage';
import { ChatStore } from '../state/ChatStore';
import { RunPhase } from '../stream/RunController';
import { StoreHub } from '../state/StoreHub';

/** Rows the slash menu can take before it crowds out the conversation. */
const MAX_SLASH_ROWS: number = 6;
/** Index into the flattened model list, carried as the choice id. */
const NO_MODEL_OVERRIDE: string = '';

@Entry
@Component
struct ChatPage {
  @State items: UiMessage[] = [];
  @State approvals: ApprovalInfo[] = [];
  @State bgRunning: ChatSpec[] = [];
  /** Other sessions stay one tap away but out of the way: collapsed by default. */
  @State bgPanelOpen: boolean = false;
  @State inputText: string = '';
  @State pending: Attachment[] = [];
  @State busy: boolean = false;
  @State loadingHistory: boolean = true;
  @State uploading: boolean = false;
  @State title: string = '';
  @State generating: boolean = false;
  @State nowSec: number = 0;
  @State commands: SlashCommand[] = [];
  @State loopModes: LoopModeInfo[] = [];
  @State loopId: string = '';
  @State models: ModelOption[] = [];
  @State modelProvider: string = '';
  @State modelId: string = '';
  /** What the server says it would use with no override; shown until one is picked. */
  @State serverModelName: string = '';
  @State approvalLevel: string = '';
  /** This agent's own level, so 'follow the desktop' can name what it follows. */
  @State serverApproval: string = '';
  /** A take in progress: the composer's menu turns into its stop button. */
  @State recording: boolean = false;
  @State recordSec: number = 0;
  private voice: VoiceNote = new VoiceNote();
  private recordTick: number = -1;
  private recordStartMs: number = 0;
  private ref: ChatRef = new ChatRef();
  private store: ChatStore | undefined = undefined;
  private pull: () => void = (): void => {};
  private scroller: Scroller = new Scroller();
  private lastCount: number = 0;
  private lastTailLength: number = 0;
  private lastMediaRev: number = 0;
  /** The server's registry, before the loop catalog is folded into it. */
  private registry: SlashCommand[] = [];
  /** An empty catalog is a fetched answer only once the call came back; before that
      no stored choice may be judged against it. */
  private loopsReady: boolean = false;
  private modelsReady: boolean = false;

  private hub(): StoreHub {
    return StoreHub.shared();
  }

  private ctx(): common.Context | undefined {
    return this.getUIContext().getHostContext() as common.Context | undefined;
  }

  aboutToAppear(): void {
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    const raw: Object | undefined = this.getUIContext().getRouter().getParams();
    if (raw !== undefined) {
      const params = raw as ChatRef;
      if (params.chatId.length > 0) {
        this.ref = params;
      }
    }
    if (this.ref.chatId.length === 0) {
      const saved = this.hub().app.foreground;
      if (saved !== undefined) {
        this.ref = saved;
      }
    }
    this.title = this.ref.title.length > 0 ? this.ref.title : Copy.chat_default_title;
    const store = this.hub().chatStoreFor(this.ref);
    this.store = store;
    this.pull = (): void => {
      this.sync();
    };
    store.attachView(this.pull);
    this.hub().poller.register(store);
    this.sync();
    store.bootstrap();
    this.loadPrefs(store);
    this.loadCommands();
    this.loadLoops(store);
    this.loadModels();
    this.loadApproval();
  }

  /** Composer choices are device-local; read them before the first send of a run. */
  private loadPrefs(store: ChatStore): void {
    const ctx = this.ctx();
    if (ctx !== undefined) {
      store.restorePrefs(ctx);
    }
  }

  /** The registry is server-side, so a plugin command shows up without an app update. */
  private loadCommands(): void {
    this.hub().composerApi.commands().then((list: SlashCommand[]): void => {
      this.registry = list;
      this.rebuildSlashMenu();
    }).catch((): void => {
      this.registry = [];
      this.rebuildSlashMenu();
    });
  }

  /**
   * Loop modes come from the server too, and a plugin mode can appear or vanish
   * between sessions, so the stored id has to be re-checked against the catalog.
   */
  private loadLoops(store: ChatStore): void {
    this.hub().composerApi.loops().then((list: LoopModeInfo[]): void => {
      this.loopModes = LoopModes.selectable(list);
      store.setLoopModes(list);
      this.rebuildSlashMenu();
      // Only a handler that ran to the end has proved the catalog arrived: a
      // half-applied load must not be allowed to discard a stored mode.
      this.loopsReady = true;
      this.alignLoopPreference();
    }).catch((err: Object): void => {
      // The picker just vanishes, so hilog is the only trace that this was a
      // failed fetch rather than a server with no loop modes to offer.
      const f = Failure.from(err);
      Log.warn(`composer loops failed http=${f.httpStatus} transport=${f.transportCode} ${f.message}`);
      this.loopModes = [];
      store.setLoopModes([]);
      this.rebuildSlashMenu();
    });
  }

  /**
   * The provider catalog is the desktop's own list, read-only here. Picking one
   * never writes it back: the choice travels as a per-message override, so the
   * agent's saved slot on the PC stays exactly where the user left it.
   */
  private loadModels(): void {
    const api = this.hub().composerApi;
    api.providers().then((list: ProviderInfo[]): void => {
      this.models = Providers.options(list);
      // Only a handler that ran to the end has proved the catalog arrived.
      this.modelsReady = true;
      this.alignModelPreference();
      api.activeModel().then((slot: ModelSlot | undefined): void => {
        this.serverModelName = Providers.displayName(this.models, slot);
      }).catch((): void => {
        this.serverModelName = '';
      });
    }).catch((err: Object): void => {
      const f = Failure.from(err);
      Log.warn(`composer models failed http=${f.httpStatus} transport=${f.transportCode} ${f.message}`);
      this.models = [];
      this.serverModelName = '';
    });
  }

  /**
   * The level this agent runs with on the desktop, read so the chip can name what
   * 'follow the PC' follows. Read only: the same document is written by a whole
   * document PUT, so the phone never sends one.
   */
  private loadApproval(): void {
    this.hub().composerApi.runningConfigApproval().then((level: string): void => {
      this.serverApproval = level;
    }).catch((err: Object): void => {
      const f = Failure.from(err);
      Log.warn(`composer running-config failed http=${f.httpStatus} transport=${f.transportCode} ${f.message}`);
      this.serverApproval = '';
    });
  }

  /** A mode the server no longer offers must not keep prefixing messages. */
  private alignLoopPreference(): void {
    const store = this.store;
    if (store === undefined || !this.loopsReady) {
      return;
    }
    const pref = store.prefs();
    if (pref.loopModeId.length === 0) {
      return;
    }
    const slash = this.loopSlash(pref.loopModeId);
    if (slash.length === 0) {
      this.chooseLoop('');
      return;
    }
    pref.loopSlash = slash;
    this.loopId = pref.loopModeId;
  }

  /** A slot the server would refuse to call is worse than no slot: drop it. */
  private alignModelPreference(): void {
    const store = this.store;
    if (store === undefined || !this.modelsReady) {
      return;
    }
    const pref = store.prefs();
    if (pref.providerId.length === 0) {
      return;
    }
    if (this.modelIndex(pref.providerId, pref.model) < 0) {
      this.chooseModel(NO_MODEL_OVERRIDE);
      return;
    }
    this.modelProvider = pref.providerId;
    this.modelId = pref.model;
  }

  private loopSlash(id: string): string {
    for (const m of this.loopModes) {
      if (Parts.str(m.id) === id) {
        return LoopModes.command(Parts.str(m.slash_command));
      }
    }
    return '';
  }

  /** '' selects the server's default loop, which carries no command of its own. */
  private chooseLoop(id: string): void {
    const store = this.store;
    if (store === undefined) {
      return;
    }
    const pref = store.prefs();
    pref.loopModeId = id;
    pref.loopSlash = this.loopSlash(id);
    this.loopId = id;
    const ctx = this.ctx();
    if (ctx !== undefined) {
      store.savePrefs(ctx, pref);
    }
  }

  private loopTitle(): string {
    for (const m of this.loopModes) {
      if (Parts.str(m.id) === this.loopId) {
        return LoopModes.displayName(m);
      }
    }
    return Copy.chat_loop_none;
  }

  private modelIndex(providerId: string, model: string): number {
    for (let i = 0; i < this.models.length; i++) {
      const option = this.models[i];
      if (option.providerId === providerId && option.modelId === model) {
        return i;
      }
    }
    return -1;
  }

  /** An empty id means 'send no override', leaving the PC agent's own slot in force. */
  private chooseModel(id: string): void {
    const store = this.store;
    if (store === undefined) {
      return;
    }
    const index = id.length === 0 ? -1 : Number(id);
    const option = index >= 0 && index < this.models.length ? this.models[index] : undefined;
    const pref = store.prefs();
    pref.providerId = option === undefined ? '' : option.providerId;
    pref.model = option === undefined ? '' : option.modelId;
    this.modelProvider = pref.providerId;
    this.modelId = pref.model;
    const ctx = this.ctx();
    if (ctx !== undefined) {
      store.savePrefs(ctx, pref);
    }
  }

  private modelTitle(): string {
    if (this.modelProvider.length > 0) {
      const index = this.modelIndex(this.modelProvider, this.modelId);
      if (index >= 0) {
        return this.models[index].modelName;
      }
      // A slot from a catalog this run did not get back is still being sent, so it
      // has to be visible and tappable rather than hidden behind a default label.
      return this.modelId;
    }
    return this.serverModelName.length > 0 ? this.serverModelName : Copy.chat_model_follow;
  }

  /**
   * One chip per composer picker. A picker with nothing to choose stays hidden
   * rather than showing a menu that only says 'default'.
   */
  private selectors(): SelectorSpec[] {
    const out: SelectorSpec[] = [];
    if (this.loopModes.length > 0) {
      out.push(this.loopSelector());
    }
    if (this.models.length > 0 || this.modelProvider.length > 0) {
      out.push(this.modelSelector());
    }
    // Four fixed values, so unlike the two catalogs above this one always has an answer.
    out.push(this.approvalSelector());
    return out;
  }

  private loopSelector(): SelectorSpec {
    const choices: Choice[] = [];
    const none = new Choice();
    none.id = '';
    none.label = Copy.chat_loop_none;
    none.selected = this.loopId.length === 0;
    choices.push(none);
    for (const m of this.loopModes) {
      const choice = new Choice();
      choice.id = Parts.str(m.id);
      choice.label = LoopModes.displayName(m);
      choice.hint = LoopModes.command(Parts.str(m.slash_command));
      choice.selected = choice.id === this.loopId;
      choices.push(choice);
    }
    const spec = new SelectorSpec();
    spec.key = SelectorKey.LOOP;
    spec.title = this.loopTitle();
    spec.selected = this.loopId;
    spec.choices = choices;
    return spec;
  }

  /** The choice id is the index into the flattened list, so no provider id can collide. */
  private modelSelector(): SelectorSpec {
    const choices: Choice[] = [];
    const follow = new Choice();
    follow.id = NO_MODEL_OVERRIDE;
    follow.label = Copy.chat_model_follow;
    follow.selected = this.modelProvider.length === 0;
    choices.push(follow);
    for (let i = 0; i < this.models.length; i++) {
      const option = this.models[i];
      const choice = new Choice();
      choice.id = String(i);
      choice.label = option.modelName;
      choice.hint = option.providerName;
      choice.selected = option.providerId === this.modelProvider && option.modelId === this.modelId;
      choices.push(choice);
    }
    const spec = new SelectorSpec();
    spec.key = SelectorKey.MODEL;
    spec.title = this.modelTitle();
    // The slot itself, not its index: an override this run's catalog never
    // matched still changes the chip's identity, so its menu rebuilds.
    spec.selected = this.modelProvider.length === 0 ? '' : `${this.modelProvider}:${this.modelId}`;
    spec.choices = choices;
    return spec;
  }

  /** The four levels are a fixed enum, so a stored one needs no catalog to check. */
  private static levelName(level: string): string {
    if (level === ApprovalLevel.STRICT) {
      return Copy.chat_approval_strict;
    }
    if (level === ApprovalLevel.SMART) {
      return Copy.chat_approval_smart;
    }
    if (level === ApprovalLevel.AUTO) {
      return Copy.chat_approval_auto;
    }
    if (level === ApprovalLevel.OFF) {
      return Copy.chat_approval_off;
    }
    return '';
  }

  private approvalTitle(): string {
    if (this.approvalLevel.length > 0) {
      return ChatPage.levelName(this.approvalLevel);
    }
    const follow = ChatPage.levelName(this.serverApproval);
    return follow.length > 0 ? follow : Copy.chat_approval_follow;
  }

  /** An empty id sends no request_context, leaving the desktop's own level in force. */
  private chooseApproval(id: string): void {
    const store = this.store;
    if (store === undefined) {
      return;
    }
    const pref = store.prefs();
    pref.approvalLevel = ApprovalLevel.isKnown(id) ? id.toUpperCase() : '';
    this.approvalLevel = pref.approvalLevel;
    const ctx = this.ctx();
    if (ctx !== undefined) {
      store.savePrefs(ctx, pref);
    }
  }

  private approvalSelector(): SelectorSpec {
    const choices: Choice[] = [];
    const follow = new Choice();
    follow.id = '';
    follow.label = Copy.chat_approval_follow;
    follow.hint = ChatPage.levelName(this.serverApproval);
    follow.selected = this.approvalLevel.length === 0;
    choices.push(follow);
    for (const level of ApprovalLevel.ALL) {
      const choice = new Choice();
      choice.id = level;
      choice.label = ChatPage.levelName(level);
      // The hint is the wire value, so a tap shows exactly what the message carries.
      choice.hint = level;
      choice.selected = level === this.approvalLevel;
      choices.push(choice);
    }
    const spec = new SelectorSpec();
    spec.key = SelectorKey.APPROVAL;
    spec.title = this.approvalTitle();
    spec.selected = this.approvalLevel;
    spec.choices = choices;
    return spec;
  }

  private pickChoice(key: string, id: string): void {
    if (key === SelectorKey.LOOP) {
      this.chooseLoop(id);
      return;
    }
    if (key === SelectorKey.MODEL) {
      this.chooseModel(id);
      return;
    }
    if (key === SelectorKey.APPROVAL) {
      this.chooseApproval(id);
    }
  }

  /** The desktop console folds loop commands into the same `/` menu the registry fills. */
  private rebuildSlashMenu(): void {
    const out: SlashCommand[] = [];
    const taken: string[] = [];
    for (const c of this.registry) {
      out.push(c);
      taken.push(c.name.toLowerCase());
    }
    for (const m of this.loopModes) {
      const name = LoopModes.command(Parts.str(m.slash_command)).substring(1);
      if (name.length > 0 && !taken.includes(name.toLowerCase())) {
        const row = new SlashCommand();
        row.name = name;
        row.description = LoopModes.displayDescription(m);
        row.category = 'loop';
        out.push(row);
        taken.push(name.toLowerCase());
      }
    }
    this.commands = out;
  }

  /** Same gate the desktop sender uses: a lone `/word`, nothing past the first space. */
  private slashSuggestions(): SlashCommand[] {
    // The server lstrips before matching a command, so a stray leading space from a
    // phone keyboard must not hide the menu.
    const text = this.inputText.trimStart();
    if (!text.startsWith('/')) {
      return [];
    }
    const needle = text.substring(1);
    if (/\s/.test(needle)) {
      return [];
    }
    const head = needle.toLowerCase();
    const out: SlashCommand[] = [];
    for (const c of this.commands) {
      if (c.name.toLowerCase().startsWith(head)) {
        out.push(c);
        if (out.length >= MAX_SLASH_ROWS) {
          break;
        }
      }
    }
    return out;
  }

  /** Completing a command leaves it as ordinary message text; the server dispatches it. */
  private pickCommand(name: string): void {
    this.inputText = `/${name} `;
  }

  aboutToDisappear(): void {
    // A page popped mid-take must not leave the microphone open behind it.
    if (this.recording) {
      this.endRecord(true);
    }
    const store = this.store;
    if (store === undefined) {
      return;
    }
    // The store itself stays in the hub: a run started here must survive the pop.
    this.hub().poller.unregister(store);
    store.detachView(this.pull);
  }

  private sync(): void {
    const store = this.store;
    if (store === undefined) {
      return;
    }
    this.items = store.items;
    this.approvals = store.approvals;
    this.bgRunning = store.bgRunning;
    this.loadingHistory = store.loading;
    this.uploading = store.uploading;
    this.busy = store.busy();
    this.nowSec = store.nowSec;
    this.generating = store.phase !== RunPhase.IDLE;
    const pref = store.prefs();
    this.loopId = pref.loopModeId;
    this.modelProvider = pref.providerId;
    this.modelId = pref.model;
    this.approvalLevel = pref.approvalLevel;
    // Preferences can land after a catalog has been fetched; a choice that died in
    // between must stop affecting messages on the flush that reveals it.
    this.alignLoopPreference();
    this.alignModelPreference();
    this.followTail(store.mediaRev);
  }

  /** Stick to the bottom when a bubble is added or the last one keeps growing. */
  private followTail(mediaRev: number): void {
    const count = this.items.length;
    const tail = count > 0 ? this.items[count - 1].text.length : 0;
    const settled = mediaRev !== this.lastMediaRev;
    if (count === this.lastCount && tail === this.lastTailLength && !settled) {
      return;
    }
    this.lastCount = count;
    this.lastTailLength = tail;
    this.lastMediaRev = mediaRev;
    // Scrolling in this frame measures the list as it was before the state
    // flush, so a freshly loaded history would jump back to the top.
    // A decoded image grows its bubble one layout pass later, so that jump has
    // to wait for the new height instead of measuring the pre-image list.
    this.stickTail(settled ? AppMotion.state : 0);
  }

  private stickTail(delay: number): void {
    setTimeout((): void => {
      this.scroller.scrollEdge(Edge.End);
    }, delay);
  }

  private send(): void {
    const store = this.store;
    if (store === undefined) {
      return;
    }
    const text = this.inputText;
    const files = this.pending;
    this.inputText = '';
    this.pending = [];
    store.send(text, files);
  }

  private pick(source: string): void {
    if (this.uploading) {
      return;
    }
    const api = this.hub().uploadApi;
    const append = (outcome: PickOutcome): void => {
      if (outcome.picked.length > 0) {
        this.pending = this.pending.concat(outcome.picked);
      }
      const store = this.store;
      if (store !== undefined) {
        store.reportPickSkipped(outcome.skipped.join('；'));
      }
    };
    const failed = (e: Object): void => {
      // Backing out of the picker rejects with a "cancel" message; that is the
      // user's choice, not a failure to report.
      const detail = Failure.from(e).message;
      const store = this.store;
      if (store !== undefined && detail.length > 0 && !detail.includes('cancel')) {
        store.reportPickFailure(detail);
      }
    };
    let picked: Promise<PickOutcome>;
    if (source === AttachSource.AUDIO) {
      picked = api.pickAudio();
    } else if (source === AttachSource.FILES) {
      picked = api.pickFiles();
    } else {
      picked = api.pickGallery();
    }
    picked.then(append).catch(failed);
  }

  /**
   * The ＋ menu's record row: one tap opens the microphone, the next tap closes it
   * and drops the file into the tray, where it sends with whatever text is typed.
   */
  private toggleRecord(): void {
    if (this.recording) {
      this.endRecord(false);
      return;
    }
    this.beginRecord();
  }

  private beginRecord(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (ctx === undefined) {
      return;
    }
    this.voice.start(ctx).then((): void => {
      this.recordStartMs = Date.now();
      this.recordSec = 0;
      this.recording = true;
      this.recordTick = setInterval((): void => {
        this.recordSec = Math.floor((Date.now() - this.recordStartMs) / 1000);
      }, 1000);
    }).catch((err: Object): void => {
      this.reportVoice(err);
    });
  }

  /** Close the engine; the take only reaches the tray when it is not thrown away. */
  private endRecord(discard: boolean): void {
    if (this.recordTick >= 0) {
      clearInterval(this.recordTick);
      this.recordTick = -1;
    }
    this.recording = false;
    this.recordSec = 0;
    if (discard) {
      this.voice.discard().catch((err: Object): void => {
        this.reportVoice(err);
      });
      return;
    }
    this.voice.stop().then((a: Attachment): void => {
      this.pending = this.pending.concat([a]);
    }).catch((err: Object): void => {
      this.reportVoice(err);
    });
  }

  private reportVoice(err: Object): void {
    const detail = Failure.from(err).message;
    const store = this.store;
    if (store !== undefined && detail.length > 0) {
      store.reportVoiceFailure(detail);
    }
  }

  /** mm:ss for the recording bar. */
  private recordClock(): string {
    const total = this.recordSec;
    const secs = total % 60;
    const pad = secs < 10 ? '0' : '';
    return `${Math.floor(total / 60)}:${pad}${secs}`;
  }

  private remove(key: string): void {
    this.pending = this.pending.filter((a: Attachment): boolean => a.key !== key);
  }

  private recall(key: string): void {
    const store = this.store;
    if (store !== undefined) {
      store.recallQueued(key);
    }
  }

  private decide(approval: ApprovalInfo, approved: boolean): void {
    const store = this.store;
    if (store !== undefined) {
      store.decide(approval, approved);
    }
  }

  private goBack(): void {
    this.getUIContext().getRouter().back();
  }

  /** Switching windows pushes a second page; the first keeps its live run. */
  private openAnother(chat: ChatSpec): void {
    const ref = new ChatRef();
    ref.chatId = chat.id;
    ref.sessionId = chat.session_id;
    ref.userId = chat.user_id;
    ref.title = chat.name;
    const ctx = this.ctx();
    if (ctx !== undefined) {
      this.hub().app.openChat(ctx, ref);
    }
    this.getUIContext().getRouter().pushUrl({ url: 'pages/ChatPage', params: ref });
  }

  @Builder
  header() {
    Column({ space: AppSpace.xxs }) {
      Row({ space: AppSpace.sm }) {
        Text(Copy.chat_back)
          .fontSize(AppType.body)
          .fontColor(AppColor.accent_text)
          .padding({ top: AppSpace.sm, bottom: AppSpace.sm })
          .onClick(() => {
            this.goBack();
          })
        Text(this.title)
          .fontSize(AppType.subtitle)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColor.text)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (this.generating) {
          Text(Copy.chat_generating)
            .fontSize(AppType.caption)
            .fontColor(AppColor.success)
        }
      }
      .width('100%')

      if (this.bgRunning.length > 0) {
        Row({ space: AppSpace.xs }) {
          Text(Copy.fillN(Copy.chat_bg_sessions, this.bgRunning.length))
            .fontSize(AppType.caption)
            .fontColor(AppColor.text_tertiary)
          Blank()
          Text(this.bgPanelOpen ? Copy.home_group_collapse : Copy.home_group_expand)
            .fontSize(AppType.caption)
            .fontColor(AppColor.accent_text)
        }
        .width('100%')
        .padding({ top: AppSpace.xxs, bottom: AppSpace.xxs })
        .onClick(() => {
          this.bgPanelOpen = !this.bgPanelOpen;
        })

        if (this.bgPanelOpen) {
          Row({ space: AppSpace.xs }) {
            ForEach(this.bgRunning, (chat: ChatSpec) => {
              Text(`${chat.name} ${Copy.chat_open}`)
                .fontSize(AppType.caption)
                .fontColor(AppColor.accent_text)
                .backgroundColor(AppColor.accent_faint)
                .borderRadius(AppRadius.pill)
                .padding({ left: AppSpace.sm, right: AppSpace.sm, top: AppSpace.xxs, bottom: AppSpace.xxs })
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .onClick(() => {
                  this.openAnother(chat);
                })
            }, (chat: ChatSpec): string => `${chat.id}_${chat.status}`)
          }
          .width('100%')
        }
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ top: AppSpace.sm, bottom: AppSpace.xs })
  }

  @Builder
  bubbleRow(item: UiMessage) {
    Row() {
      if (item.role === Role.USER) {
        Blank()
      }
      Bubble({
        item: item,
        onRecall: (key: string): void => {
          this.recall(key);
        }
      })
      if (item.role !== Role.USER) {
        Blank()
      }
    }
    .width('100%')
  }

  build() {
    Column({ space: AppSpace.xxs }) {
      this.header()

      if (this.loadingHistory) {
        Text(Copy.chat_loading_history)
          .fontSize(AppType.body)
          .fontColor(AppColor.text_secondary)
          .width('100%')
      } else {
        // List.space takes number|string only, so the gap comes from item margins.
        List({ scroller: this.scroller }) {
          ForEach(this.items, (item: UiMessage) => {
            ListItem() {
              this.bubbleRow(item)
            }
            .margin({ bottom: AppSpace.xs })
          }, (item: UiMessage): string => item.key)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .onAppear((): void => {
          // A page pushed onto an already-loaded history has nothing to measure
          // during its state flush; the tail jump belongs here.
          this.stickTail(0);
        })
      }

      ForEach(this.approvals, (approval: ApprovalInfo) => {
        ApprovalCard({
          approval: approval,
          nowSec: this.nowSec,
          onDecide: (target: ApprovalInfo, approved: boolean): void => {
            this.decide(target, approved);
          }
        })
      }, (approval: ApprovalInfo): string => `${approval.request_id}_${this.nowSec}`)

      if (this.recording) {
        Row({ space: AppSpace.sm }) {
          Text('●')
            .fontSize(AppType.body)
            .fontColor(AppColor.warning)
          Text(Copy.fill(Copy.chat_recording, this.recordClock()))
            .fontSize(AppType.caption)
            .fontColor(AppColor.text_secondary)
            .layoutWeight(1)
          AppButton({
            label: Copy.chat_rec_stop,
            quiet: false,
            onTap: (): void => {
              this.endRecord(false);
            }
          })
          AppButton({
            label: Copy.chat_rec_cancel,
            quiet: true,
            onTap: (): void => {
              this.endRecord(true);
            }
          })
        }
        .width('100%')
      }

      Composer({
        text: $inputText,
        attachments: $pending,
        busy: this.busy,
        uploading: this.uploading,
        suggestions: this.slashSuggestions(),
        selectors: this.selectors(),
        recording: this.recording,
        onSend: (): void => {
          this.send();
        },
        onStop: (): void => {
          const store = this.store;
          if (store !== undefined) {
            store.stopRun();
          }
        },
        onPick: (source: string): void => {
          this.pick(source);
        },
        onRecord: (): void => {
          this.toggleRecord();
        },
        onRemove: (key: string): void => {
          this.remove(key);
        },
        onPickCommand: (name: string): void => {
          this.pickCommand(name);
        },
        onPickChoice: (key: string, id: string): void => {
          this.pickChoice(key, id);
        }
      })

      if (this.uploading) {
        Row({ space: AppSpace.xs }) {
          LoadingProgress()
            .width(AppSize.icon_md)
            .height(AppSize.icon_md)
            .color(AppColor.accent)
          Text(Copy.notice_uploading)
            .fontSize(AppType.caption)
            .fontColor(AppColor.text_tertiary)
        }
        .width('100%')
      }
    }
    .alignItems(HorizontalAlign.Start)
    .padding({ left: AppSpace.md, right: AppSpace.md })
    .width('100%')
    .height('100%')
    .backgroundColor(AppColor.bg)
  }
}
