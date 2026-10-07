/**
 * One chat window.
 *
 * The page is a mirror of ChatStore: it registers the store with the app-wide
 * poller, re-renders when the store emits, and forwards taps back. All run
 * scheduling, frame merging and reconnect policy live behind the store.
 */
import { common } from '@kit.AbilityKit';
import { Bubble } from '../ui/chat/Bubble';
import { ApprovalCard } from '../ui/chat/ApprovalCard';
import { Composer } from '../ui/chat/Composer';
import { FullScreenEditor } from '../ui/chat/FullScreenEditor';
import { AssetPanel } from '../ui/chat/AssetPanel';
import { McpPanel } from '../ui/chat/McpPanel';
import { SkillPanel } from '../ui/chat/SkillPanel';
import { AppButton } from '../ui/common/AppButton';
import { VoiceNote } from '../media/VoiceNote';
import { AppColor, AppLine, AppMeasure, AppMotion, AppRadius, AppSize, AppSpace, AppType, AppWidth } from '../theme/Theme';
import { Copy } from '../l10n/Copy';
import { Bp } from '../core/Breakpoint';
import { Attachment, AttachSource, QuoteKind } from '../model/Attachment';
import { AssetRow } from '../model/Asset';
import { Export } from '../media/Export';
import { PickOutcome, UploadApi } from '../api/UploadApi';
import { Choice, SelectorKey, SelectorSpec } from '../model/Choices';
import { ApprovalInfo, ChatRef, ChatSpec, LoopModeInfo, MCPClientInfo, MCPToolInfo, ModelSlot, ProviderInfo, SkillSpec, SlashCommand } from '../model/Dtos';
import { LoopModes } from '../model/LoopModes';
import { ModelOption, Providers } from '../model/Providers';
import { Parts } from '../model/Parts';
import { ApprovalLevel, Role } from '../core/Wire';
import { image } from '@kit.ImageKit';
import { Failure } from '../core/Failure';
import { Log } from '../core/Log';
import { UiKind, UiMessage } from '../state/UiMessage';
import { MediaValue } from '../media/MediaLoader';
import { ChatStore } from '../state/ChatStore';
import { RunPhase } from '../stream/RunController';
import { StoreHub } from '../state/StoreHub';

/**
 * Commands the slash menu may carry. The sheet itself is height-capped and
 * scrolls, so this only bounds the node count: a real registry has more
 * commands than six, and a cap that low hid whole categories from anyone who
 * just typed `/` to look around.
 */
const MAX_SLASH_ROWS: number = 20;
/** A typing pause longer than this flushes the composer draft to disk. */
const DRAFT_SAVE_MS: number = 800;
/** Index into the flattened model list, carried as the choice id. */
const NO_MODEL_OVERRIDE: string = '';
/**
 * A quote longer than this is pasted as a preview, in characters because that is
 * what the composer holds: the full message goes out as a text file beside it.
 */
const QUOTE_MAX: number = 600;
/** What a bubble can hold, in the order the asset list shows them. */
const ASSET_KINDS: string[] = [QuoteKind.IMAGE, QuoteKind.VIDEO, QuoteKind.AUDIO, QuoteKind.FILE];

/**
 * One row of the rendered transcript: a lone message, or a run of consecutive
 * tool cards folded behind a single header. Purely a view-layer shape — the
 * store still holds one message per tool call, and a run of one renders as
 * today's plain card.
 */
class ChatRow {
  key: string = '';
  items: UiMessage[] = [];
}

@Entry
@Component
struct ChatPage {
  /** The window's width bucket, published by Breakpoint; 'sm' means a phone. */
  @StorageProp(Bp.KEY) wBp: string = Bp.sm;
  @State items: UiMessage[] = [];
  /**
   * Unfolded tool runs, by the key of the run's first message. The head key
   * never moves while the run grows at its tail, so an open run stays open
   * under the agent's feet. A list, not a Set: @State observes the assignment.
   */
  @State toolRunsOpen: string[] = [];
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
  @State showFullScreenEditor: boolean = false;
  /** This chat's file/media list, read off the transcript when the panel opens. */
  @State assetsOpen: boolean = false;
  @State assetRows: AssetRow[] = [];
  @State assetsStatus: string = '';
  /** One save or forward at a time: a second tap stacks a second system dialog. */
  private assetsBusy: boolean = false;
  /** Shown on the header entry; recounting it is cheap, stat-ing every file is not. */
  @State assetCount: number = 0;
  /**
   * The image the user tapped, held as its own value so the viewer survives a
   * history resync that replaces the bubble it came from.
   */
  @State zoom: MediaValue = new MediaValue();
  @State generating: boolean = false;
  @State nowSec: number = 0;
  @State commands: SlashCommand[] = [];
  /** Skills the desktop enabled for this channel; the ＋ menu opens a picker for them. */
  @State skills: SkillSpec[] = [];
  @State skillsOpen: boolean = false;
  @State mcpOpen: boolean = false;
  @State mcpClients: MCPClientInfo[] = [];
  /** Read when the panel opens, not at chat open: an inventory nobody asked for. */
  @State mcpLoaded: boolean = false;
  @State mcpExpanded: string = '';
  @State mcpTools: MCPToolInfo[] = [];
  /** The open client's tool line: in flight, failed, stopped, or empty. */
  @State mcpToolsNote: string = '';
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
  /** Voice mode: the composer shows the record button instead of the text field. */
  @State voiceMode: boolean = false;
  @State recordSec: number = 0;
  private voice: VoiceNote = new VoiceNote();
  private recordTick: number = -1;
  private recordStartMs: number = 0;
  /** The voice bar was released while the microphone was still opening. */
  private holdReleased: boolean = false;
  /** Pending debounced draft save; -1 means none is scheduled. */
  private draftTimer: number = -1;
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
    this.loadPrefs(store);
    this.loadCommands();
    this.loadSkills();
    this.loadLoops(store);
    this.loadModels();
    this.loadApproval();
  }

  /**
   * Composer choices and the record of media this phone sent are device-local, and
   * both are read before the first history paint: rebuilding bubbles looks up the
   * echo records, so loading them afterwards would show a photo the user just sent
   * as missing until the next reload.
   */
  private loadPrefs(store: ChatStore): void {
    const ctx = this.ctx();
    if (ctx === undefined) {
      store.bootstrap();
      return;
    }
    store.restorePrefs(ctx).catch((): void => {
      // Unreadable preferences leave the composer on the PC's defaults, which is
      // not a reason to withhold the transcript.
    }).then((): void => {
      // A stored draft only fills a composer the user has not already typed into.
      const draft = store.prefs().draft;
      if (this.inputText.length === 0 && draft.length > 0) {
        this.inputText = draft;
      }
      store.bootstrap();
    });
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

  /** Skills the composer can name. The api layer already dropped what a phone cannot run. */
  private loadSkills(): void {
    this.hub().composerApi.skills().then((list: SkillSpec[]): void => {
      this.skills = list;
    }).catch((): void => {
      this.skills = [];
    });
  }

  /**
   * A skill runs by its name reaching the message, the same way a typed `/name`
   * would — the desktop resolves an unmatched `/name` through its slash-command
   * fallback, and its own `/skills` list says to type `/<skill_name> <input>`. There
   * is no other channel for it: which skills are live comes from the workspace
   * manifest and the channel, computed on the server, not from the request body.
   * A previous prefix is replaced rather than stacked: the server reads one token,
   * so '/a /b rest' would silently drop b.
   */
  private pickSkill(name: string): void {
    const body = this.stripSlashToken(this.inputText);
    this.inputText = `/${name} ${body}`;
    // Unlike a system command, a skill takes the user's own sentence as its args,
    // so the field stays editable — and voice mode has no field to show it in.
    this.voiceMode = false;
    this.onInputChanged();
  }

  private stripSlashToken(text: string): string {
    const head = text.trimStart();
    if (!head.startsWith('/')) {
      return text;
    }
    const gap = head.indexOf(' ');
    return gap < 0 ? '' : head.substring(gap + 1).trimStart();
  }

  /**
   * The picker reads the list `loadSkills()` already fetched for this chat, so
   * opening it asks the desktop for nothing.
   */
  private openSkills(): void {
    this.skillsOpen = true;
  }

  /** Open the inventory; the list is read once per chat, not once per keystroke. */
  private openMcp(): void {
    this.mcpOpen = true;
    this.mcpExpanded = '';
    this.mcpTools = [];
    this.mcpToolsNote = '';
    if (this.mcpLoaded) {
      return;
    }
    this.hub().composerApi.mcpClients().then((list: MCPClientInfo[]): void => {
      this.mcpClients = list;
      this.mcpLoaded = true;
    }).catch((err: Object): void => {
      this.mcpClients = [];
      // An empty panel must not read as 'the desktop has nothing mounted'.
      this.mcpToolsNote = Copy.fill(Copy.mcp_failed, Failure.from(err).message);
    });
  }

  private toggleMcp(key: string): void {
    if (this.mcpExpanded === key) {
      this.mcpExpanded = '';
      this.mcpToolsNote = '';
      return;
    }
    this.mcpExpanded = key;
    this.mcpTools = [];
    this.mcpToolsNote = Copy.mcp_tools_loading;
    this.hub().composerApi.mcpTools(key).then((list: MCPToolInfo[]): void => {
      this.mcpToolsNote = '';
      if (list.length === 0) {
        this.mcpToolsNote = this.clientEnabled(key) ? Copy.mcp_tools_empty : Copy.mcp_tools_stopped;
      }
      this.mcpTools = list;
    }).catch((err: Object): void => {
      this.mcpToolsNote = Copy.fill(Copy.mcp_tools_failed, Failure.from(err).message);
    });
  }

  private clientEnabled(key: string): boolean {
    for (const c of this.mcpClients) {
      if (c.key === key) {
        return c.enabled;
      }
    }
    return true;
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
    this.onInputChanged();
  }

  /** Backgrounding is where a kill can land: whatever the pause missed goes to disk now. */
  onPageHide(): void {
    this.flushDraft(this.inputText);
    this.stopAudio();
  }

  private stopAudio(): void {
    const store = this.store;
    if (store !== undefined) {
      store.stopAudio();
    }
  }

  aboutToDisappear(): void {
    this.flushDraft(this.inputText);
    // A page popped mid-take must not leave the microphone open behind it.
    if (this.recording) {
      this.endRecord(true);
    }
    const store = this.store;
    if (store === undefined) {
      return;
    }
    // Nor a voice note that outlived the window it came from.
    store.stopAudio();
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
    // The badge is read off the bubbles, so it is recounted on every flush. The
    // guard below only decides whether to scroll: a history resync can swap the
    // transcript one bubble for another, dropping every media reference while
    // leaving both the count and the tail's length untouched, and a badge that
    // keeps advertising assets the panel can no longer list is worse than none.
    this.assetCount = this.countAssets();
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

  /** Typing is saved on a pause; leaving the page flushes what the pause missed. */
  private onInputChanged(): void {
    this.cancelDraftTimer();
    this.draftTimer = setTimeout((): void => {
      this.draftTimer = -1;
      this.flushDraft(this.inputText);
    }, DRAFT_SAVE_MS);
  }

  private cancelDraftTimer(): void {
    if (this.draftTimer >= 0) {
      clearTimeout(this.draftTimer);
      this.draftTimer = -1;
    }
  }

  /** Fire-and-forget: the write outlives the page, so a pop cannot strand the text. */
  private flushDraft(text: string): void {
    this.cancelDraftTimer();
    const store = this.store;
    const ctx = this.ctx();
    if (store !== undefined && ctx !== undefined) {
      // Only the text persists, never the tray beside it, so a promise about an
      // attachment cannot survive a restart honest. It stays on screen, where the
      // chip really is there, and is stripped on the way to disk.
      store.saveDraft(ctx, ChatPage.withoutClaims(text, ''));
    }
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
    // The draft dies with the send: the watcher's pending save must not revive it.
    this.flushDraft('');
    store.send(this.ctx(), text, files);
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

  /**
   * The voice bar came up. A quick tap outpaces the recorder — the microphone takes
   * a moment to actually open — so a release that lands before `recording` turns true
   * is remembered rather than dropped, and the take is thrown away as soon as it
   * opens. Otherwise a test tap would strand a live recording the bar has closed.
   */
  private endHold(discard: boolean): void {
    if (!this.recording) {
      this.holdReleased = true;
      return;
    }
    this.endRecord(discard, !discard);
  }

  private beginRecord(): void {
    this.holdReleased = false;
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (ctx === undefined) {
      return;
    }
    this.voice.start(ctx).then((): void => {
      if (this.holdReleased) {
        this.voice.discard().catch((err: Object): void => {
          this.reportVoice(err);
        });
        return;
      }
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

  /**
   * Close the engine. The take goes to the tray unless `sendAfter` says it was a
   * hold, in which case it is sent on its own the way it came.
   */
  private endRecord(discard: boolean, sendAfter: boolean = false): void {
    if (!this.recording) {
      return;
    }
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
      if (sendAfter) {
        const store = this.store;
        if (store === undefined) {
          this.pending = this.pending.concat([a]);
          return;
        }
        // Only the take travels. The typed draft and any other tray chip stay put:
        // a hold is a sentence spoken, not the whole composer submitted.
        store.send(this.ctx(), '', [a]);
        return;
      }
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

  /**
   * Drop a tray chip. A long quote's full text lives in that chip and nowhere
   * else, so the sentence promising it goes with it: sending the sentence alone
   * would tell the PC a file came that never did.
   */
  private remove(key: string): void {
    const dropped = this.pending.find((a: Attachment): boolean => a.key === key);
    this.pending = this.pending.filter((a: Attachment): boolean => a.key !== key);
    if (dropped !== undefined && dropped.text.length > 0) {
      this.inputText = ChatPage.withoutClaims(this.inputText, dropped.name);
      this.onInputChanged();
    }
  }

  /**
   * Drop composer lines that promise an attachment travels with the message.
   * A named removal matches only that one promise, so a second long quote still
   * in the tray keeps its sentence; an empty name matches every promise, which is
   * what a draft needs because no tray chip survives into the next session.
   */
  private static withoutClaims(text: string, name: string): string {
    const marker = Copy.chat_quote_as_file.substring(0, Copy.chat_quote_as_file.indexOf('%s'));
    if (marker.length === 0 || text.indexOf(marker) < 0) {
      return text;
    }
    return text.split('\n')
      .filter((line: string): boolean => !(line.startsWith(marker)
        && (name.length === 0 || line.indexOf(name) >= 0)))
      .join('\n');
  }

  /** Last path segment of a stored reference, without whatever query follows it. */
  private static baseOf(ref: string): string {
    const head = ref.split('?')[0];
    const slash = head.lastIndexOf('/');
    return slash >= 0 ? head.substring(slash + 1) : head;
  }

  /**
   * Quote a transcript message into the composer. Text becomes a markdown
   * blockquote, so the PC renders it as a quote and the model sees the same
   * thing the phone showed. Media becomes a reference the server already has.
   */
  private quote(m: UiMessage, kind: string): void {
    if (kind === QuoteKind.TEXT) {
      const clipped = m.text.length > QUOTE_MAX;
      let body = clipped ? m.text.substring(0, QUOTE_MAX) : m.text;
      if (clipped) {
        // Land the preview on a line break: a dangling half line on the last row
        // read as the renderer breaking rather than as a quote that continues.
        const nl = body.lastIndexOf('\n');
        if (nl > 0) {
          body = body.substring(0, nl);
        }
      }
      const lines = body.split('\n');
      const quoted: string[] = [];
      for (const line of lines) {
        quoted.push(line.length > 0 ? `> ${line}` : '>');
      }
      let block = quoted.join('\n');
      if (clipped) {
        // An ellipsis alone read as the quoted text ending where it ended: the PC
        // answered the cut instead of the point. So the paste keeps a preview the
        // transcript can still be recognised from, and the whole message goes out
        // beside it as a text file. ASCII name because it travels in a
        // Content-Disposition header and lands on the PC's filesystem.
        const stamp = Date.now();
        const name = `quote-${stamp}.txt`;
        block = `${block}\n${Copy.fillN2(Copy.chat_quote_as_file, name, m.text.length)}`;
        const a = new Attachment();
        a.key = `quote_${stamp}_${this.pending.length}`;
        a.name = name;
        a.mime = UploadApi.mimeFromName(name);
        a.text = m.text;
        this.pending = this.pending.concat([a]);
      }
      this.inputText = this.inputText.trim().length > 0 ? `${this.inputText}\n\n${block}` : block;
      // Quoting from voice mode would otherwise drop the block into a field the
      // composer isn't showing, leaving a send button that lights up for nothing.
      this.voiceMode = false;
      this.onInputChanged();
      return;
    }
    const ref = kind === QuoteKind.IMAGE ? m.imageRef
      : (kind === QuoteKind.VIDEO ? m.videoRef
        : (kind === QuoteKind.AUDIO ? m.audioRef : m.fileRef));
    if (ref.length === 0) {
      return;
    }
    const a = new Attachment();
    a.key = `quote_${Date.now()}_${this.pending.length}`;
    a.ref = ref;
    a.name = m.fileName.length > 0 ? m.fileName : ChatPage.baseOf(ref);
    // buildParts only reads the prefix to pick the part type, and no bytes move,
    // so the wildcard stands for "whatever the server already stored".
    a.mime = kind === QuoteKind.FILE ? '' : `${kind}/*`;
    this.pending = this.pending.concat([a]);
  }

  /** Which field of a bubble carries the reference for one kind of asset. */
  private static refOf(m: UiMessage, kind: string): string {
    if (kind === QuoteKind.IMAGE) {
      return m.imageRef;
    }
    if (kind === QuoteKind.VIDEO) {
      return m.videoRef;
    }
    if (kind === QuoteKind.AUDIO) {
      return m.audioRef;
    }
    return m.fileRef;
  }

  /**
   * How many distinct assets this chat has carried. No file access here: the header
   * re-reads it whenever the transcript moves, which during a stream is every frame.
   */
  private countAssets(): number {
    const seen: Set<string> = new Set();
    for (const m of this.items) {
      for (const kind of ASSET_KINDS) {
        const ref = ChatPage.refOf(m, kind);
        if (ref.length > 0 && !ref.startsWith('data:')) {
          seen.add(`${kind}_${ref}`);
        }
      }
    }
    return seen.size;
  }

  /**
   * Every file this chat has carried, read off the bubbles already on screen. The
   * transcript is the server's, so the list needs no endpoint of its own and cannot
   * disagree with what the window shows.
   */
  private collectAssets(): AssetRow[] {
    const media = this.hub().media;
    const rows: AssetRow[] = [];
    const seen: Set<string> = new Set();
    // Newest first: this panel is a file browser, and the file the user opened it
    // for is almost always the one that just arrived. Walking backwards also lists
    // a ref that was sent twice at its latest turn rather than its first.
    for (let i = this.items.length - 1; i >= 0; i--) {
      const m = this.items[i];
      for (const kind of ASSET_KINDS) {
        const ref = ChatPage.refOf(m, kind);
        // A `data:` URI is the bytes inlined in the transcript: there is no stored
        // path to hand to the gallery, and the phone has no copy to delete.
        if (ref.length === 0 || ref.startsWith('data:') || seen.has(`${kind}_${ref}`)) {
          continue;
        }
        seen.add(`${kind}_${ref}`);
        const row = new AssetRow();
        // One message can carry a picture and a document, so the message key alone
        // would name two rows the same and the delete confirm would act on the
        // other one's bytes. The kind is what makes a row unique.
        row.key = `${m.key}_${kind}`;
        row.msgKey = m.key;
        row.index = i;
        row.kind = kind;
        row.ref = ref;
        // A document arrives named by the PC's filesystem, so the row shows its
        // parent folder and name: the leading directories name the other machine's
        // disk and only push the part the user recognises off the line. Media refs
        // point into the server's own storage, whose folders say nothing at all.
        row.name = kind === QuoteKind.FILE && m.fileName.length > 0
          ? Parts.shortPath(m.fileName) : Parts.leafOf(ref);
        row.stamp = m.stamp;
        const size = media.sizeOfRef(ref);
        row.cached = size > 0;
        row.size = size;
        rows.push(row);
      }
    }
    return rows;
  }

  private openAssets(): void {
    this.assetRows = this.collectAssets();
    this.assetsStatus = '';
    this.assetsOpen = true;
  }

  private locateAsset(row: AssetRow): void {
    this.assetsOpen = false;
    // The list has to lay out the panel's absence before an index means anything.
    setTimeout((): void => {
      this.scroller.scrollToIndex(row.index, true);
    }, AppMotion.state);
  }

  /** Save and forward both need bytes on disk, so both start by fetching them. */
  private async exportAsset(row: AssetRow, forward: boolean): Promise<void> {
    if (this.assetsBusy) {
      return;
    }
    this.assetsBusy = true;
    this.assetsStatus = Copy.assets_busy;
    try {
      const path = await this.hub().media.localPath(row.ref);
      if (path.length === 0) {
        this.assetsStatus = Copy.fill(Copy.assets_fetch_failed, row.name);
        return;
      }
      // The bytes are here; from now on the system dialog is the feedback, and a line
      // under it would only be stale while the user is choosing where the file goes.
      this.assetsStatus = '';
      // The row says 本机 from the moment the copy lands, whether or not the user
      // follows through with the dialog the system just opened.
      this.assetRows = this.collectAssets();
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (forward) {
        this.assetsStatus = await Export.share(ctx, path, row.name);
      } else if (row.kind === QuoteKind.IMAGE || row.kind === QuoteKind.VIDEO) {
        this.assetsStatus = await Export.toGallery(ctx, path, row.name,
          row.kind === QuoteKind.VIDEO);
      } else {
        // The gallery holds images and video only, so a voice note or a document goes
        // to a folder the user picks instead.
        this.assetsStatus = await Export.toDocuments(ctx, path, row.name);
      }
      // Re-read the rows now that the system surface has closed. The snapshot above
      // was taken before a dialog the user may have spent minutes in, and cacheDir
      // is the system's to reclaim: a row still claiming 本机 would offer
      // 删除副本 for bytes that are no longer on the phone.
      this.assetRows = this.collectAssets();
    } finally {
      this.assetsBusy = false;
    }
  }

  /**
   * Open one asset the way its kind wants to be opened. Pictures land in the chat's
   * own full-screen viewer and voice notes start in the chat's own player, so the
   * panel stays behind them and the user comes back to the list. Video and documents
   * leave for a system player or reader — the app has no surface for either — and
   * the panel is still there when they return.
   */
  private openAsset(row: AssetRow): void {
    if (row.kind === QuoteKind.IMAGE) {
      this.hub().media.load(row.ref).then((value: MediaValue): void => {
        if (value.failed || value.isEmpty()) {
          this.assetsStatus = Copy.fill(Copy.assets_fetch_failed, row.name);
          return;
        }
        this.assetsStatus = '';
        this.zoom = value;
      });
      return;
    }
    const m = this.itemAt(row.msgKey);
    if (m === undefined) {
      return;
    }
    if (row.kind === QuoteKind.AUDIO) {
      const store = this.store;
      if (store !== undefined) {
        store.playAudio(m);
      }
      return;
    }
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (row.kind === QuoteKind.VIDEO) {
      this.openVideoAsset(row, ctx);
      return;
    }
    const store = this.store;
    if (store !== undefined) {
      store.openFile(ctx, m);
    }
  }

  /** Bytes first, then the system's player: the panel waits where it was. */
  private async openVideoAsset(row: AssetRow, ctx: common.UIAbilityContext): Promise<void> {
    if (this.assetsBusy) {
      return;
    }
    this.assetsBusy = true;
    this.assetsStatus = Copy.assets_busy;
    try {
      const path = await this.hub().media.localPath(row.ref);
      if (path.length === 0) {
        this.assetsStatus = Copy.fill(Copy.assets_fetch_failed, row.name);
        return;
      }
      this.assetsStatus = await Export.open(ctx, path, row.name);
      this.assetRows = this.collectAssets();
    } finally {
      this.assetsBusy = false;
    }
  }

  private dropAsset(row: AssetRow): void {
    if (row.kind === QuoteKind.AUDIO) {
      // Same reason the cleanup page stops the speaker first: a copy the player is
      // still holding is not really gone.
      this.hub().audio.stop();
    }
    const media = this.hub().media;
    // 'Nothing to delete' and 'refused' are different stories. The system can reclaim
    // the cache while the panel is open, and blaming a lock then would send the user
    // off to close a player that is not open.
    this.assetsStatus = media.sizeOfRef(row.ref) === 0
      ? Copy.assets_drop_gone
      : (media.dropRef(row.ref) ? Copy.assets_dropped : Copy.assets_drop_failed);
    this.assetRows = this.collectAssets();
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

  private itemAt(key: string): UiMessage | undefined {
    for (const m of this.items) {
      if (m.key === key) {
        return m;
      }
    }
    return undefined;
  }

  /** Only a decoded image is worth a full screen; a broken one stays a caption. */
  private openZoom(key: string): void {
    const m = this.itemAt(key);
    const value = m === undefined ? undefined : m.image;
    if (value === undefined || value.failed || value.isEmpty()) {
      return;
    }
    this.zoom = value;
  }

  private zoomOpen(): boolean {
    return !this.zoom.isEmpty() && !this.zoom.failed;
  }

  private zoomSource(): image.PixelMap | string {
    return this.zoom.map === undefined ? this.zoom.url : this.zoom.map;
  }

  private closeZoom(): void {
    this.zoom = new MediaValue();
  }

  private toggleAudio(key: string): void {
    const store = this.store;
    const m = this.itemAt(key);
    if (store !== undefined && m !== undefined) {
      store.playAudio(m);
    }
  }

  /**
   * A back gesture closes the topmost layer it finds: the editor, then a zoomed
   * image. The page stays, so one stray swipe cannot strand a long text
   * mid-composition or drop the user out of the chat they were reading.
   */
  onBackPress(): boolean {
    if (this.showFullScreenEditor) {
      this.showFullScreenEditor = false;
      return true;
    }
    if (this.zoomOpen()) {
      this.closeZoom();
      return true;
    }
    if (this.assetsOpen) {
      this.assetsOpen = false;
      return true;
    }
    if (this.skillsOpen) {
      this.skillsOpen = false;
      return true;
    }
    if (this.mcpOpen) {
      this.mcpOpen = false;
      return true;
    }
    this.flushDraft(this.inputText);
    return false;
  }

  private goBack(): void {
    this.flushDraft(this.inputText);
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
        if (this.assetCount > 0) {
          Text(Copy.fillN(Copy.assets_entry, this.assetCount))
            .fontSize(AppType.caption)
            .fontColor(AppColor.accent_text)
            .backgroundColor(AppColor.accent_faint)
            .borderRadius(AppRadius.pill)
            .padding({ left: AppSpace.sm, right: AppSpace.sm, top: AppSpace.xxs, bottom: AppSpace.xxs })
            .onClick((): void => {
              this.openAssets();
            })
        }
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
          // Wrapping, not one Row: a long title takes the whole row and the next
          // chip is then measured to a sliver past the window edge — untappable.
          Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
            ForEach(this.bgRunning, (chat: ChatSpec) => {
              Text(`${chat.name} ${Copy.chat_open}`)
                .fontSize(AppType.caption)
                .fontColor(AppColor.accent_text)
                .backgroundColor(AppColor.accent_faint)
                .borderRadius(AppRadius.pill)
                .padding({ left: AppSpace.sm, right: AppSpace.sm, top: AppSpace.xxs, bottom: AppSpace.xxs })
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .constraintSize({ maxWidth: '100%' })
                .margin({ right: AppSpace.xs, bottom: AppSpace.xxs })
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
    .width(AppMeasure.text(this.wBp))
    .padding({ top: AppSpace.sm, bottom: AppSpace.xs })
  }

  /**
   * Whether a bubble holds something the user can open. A tool that handed over a
   * file carries it on the same fields an answer bubble does, so the asset count and
   * the panel read it without a second path — and the fold below has to leave it
   * alone, because a file buried behind "8 tool calls" is the one thing the user
   * asked the agent for.
   */
  private static carriesAsset(m: UiMessage): boolean {
    for (const kind of ASSET_KINDS) {
      if (ChatPage.refOf(m, kind).length > 0) {
        return true;
      }
    }
    return m.fileName.length > 0;
  }

  /**
   * The transcript in rows: a message stands alone, but consecutive tool cards
   * fold into one row headed by their count — an agent that recalls history in
   * bursts otherwise fills the screen with cards it folded for exactly that
   * reason. Two is the smallest run worth a header; a single card keeps the
   * plain row it has always had. A card that carries a file is never folded, and
   * so breaks the run it sits in.
   */
  private rows(): ChatRow[] {
    const rows: ChatRow[] = [];
    let i = 0;
    while (i < this.items.length) {
      const first = this.items[i];
      if (first.kind !== UiKind.TOOL || ChatPage.carriesAsset(first)) {
        const alone = new ChatRow();
        alone.key = first.key;
        alone.items = [first];
        rows.push(alone);
        i += 1;
        continue;
      }
      let end = i + 1;
      while (end < this.items.length && this.items[end].kind === UiKind.TOOL
        && !ChatPage.carriesAsset(this.items[end])) {
        end += 1;
      }
      const run = new ChatRow();
      run.key = first.key;
      run.items = this.items.slice(i, end);
      rows.push(run);
      i = end;
    }
    return rows;
  }

  private toolRunOpen(key: string): boolean {
    return this.toolRunsOpen.includes(key);
  }

  private toggleToolRun(key: string): void {
    const at = this.toolRunsOpen.indexOf(key);
    this.toolRunsOpen = at >= 0
      ? this.toolRunsOpen.slice(0, at).concat(this.toolRunsOpen.slice(at + 1))
      : this.toolRunsOpen.concat([key]);
  }

  @Builder
  toolRow(row: ChatRow) {
    if (row.items.length === 1) {
      this.bubbleRow(row.items[0])
    } else {
      Column({ space: AppSpace.xs }) {
        Row() {
          this.toolRunHead(row)
          Blank()
        }
        .width('100%')
        if (this.toolRunOpen(row.key)) {
          // Unfolded, a run is just today's cards again: each still folds its own
          // content, so "one of them" stays a reachable thing to look at.
          ForEach(row.items, (item: UiMessage) => {
            this.bubbleRow(item)
          }, (item: UiMessage): string => item.key)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
  }

  @Builder
  toolRunHead(row: ChatRow) {
    Row({ space: AppSpace.xxs }) {
      Text(Copy.fillN(Copy.chat_tool_group, row.items.length))
        .fontSize(AppType.caption)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColor.warning_text)
        .layoutWeight(1)
      Text(this.toolRunOpen(row.key) ? Copy.chat_tool_collapse : Copy.chat_tool_expand)
        .fontSize(AppType.caption)
        .fontColor(AppColor.warning_text)
    }
    .width('100%')
    .onClick((): void => {
      this.toggleToolRun(row.key);
    })
    .backgroundColor(AppColor.warning_bg)
    .border({ width: AppLine.thin, color: AppColor.warning_border })
    .padding(AppSpace.sm)
    .borderRadius(AppRadius.card)
    .constraintSize({ maxWidth: AppWidth.tool_max })
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
        },
        onZoomImage: (key: string): void => {
          this.openZoom(key);
        },
        onToggleAudio: (key: string): void => {
          this.toggleAudio(key);
        },
        onQuote: (item: UiMessage, kind: string): void => {
          this.quote(item, kind);
        },
        onOpenFile: (item: UiMessage): void => {
          const ctx = this.ctx();
          const store = this.store;
          if (ctx !== undefined && store !== undefined) {
            store.openFile(ctx, item);
          }
        },
        sizeOf: (ref: string): number => this.hub().media.sizeOfRef(ref)
      })
      if (item.role !== Role.USER) {
        Blank()
      }
    }
    .width('100%')
  }

  /**
   * Full-screen image. The bytes are already decoded, so this costs no second
   * fetch, and the whole surface is the close gesture: a phone holding a photo
   * open with one hand has no other control to reach.
   */
  @Builder
  zoomViewer() {
    Column({ space: AppSpace.sm }) {
      Text(Copy.chat_zoom_close)
        .fontSize(AppType.caption)
        .fontColor(AppColor.text_inverse)
      Image(this.zoomSource())
        .objectFit(ImageFit.Contain)
        .width('100%')
        .layoutWeight(1)
    }
    .alignItems(HorizontalAlign.Center)
    .width('100%')
    .height('100%')
    .padding({ left: AppSpace.md, right: AppSpace.md, top: AppSpace.lg, bottom: AppSpace.lg })
    .backgroundColor(AppColor.scrim)
    .onClick(() => {
      this.closeZoom();
    })
  }

  build() {
    if (this.showFullScreenEditor) {
      FullScreenEditor({
        text: $inputText,
        placeholder: Copy.chat_input_placeholder,
        onSend: (): void => {
          this.showFullScreenEditor = false;
          this.send();
        },
        onCancel: (): void => {
          this.showFullScreenEditor = false;
        },
        onTextChanged: (): void => {
          this.onInputChanged();
        }
      })
    } else if (this.zoomOpen()) {
      this.zoomViewer()
    } else if (this.assetsOpen) {
      AssetPanel({
        rows: this.assetRows,
        bp: this.wBp,
        status: this.assetsStatus,
        onClose: (): void => {
          this.assetsOpen = false;
        },
        onOpen: (row: AssetRow): void => {
          this.openAsset(row);
        },
        onLocate: (row: AssetRow): void => {
          this.locateAsset(row);
        },
        onSave: (row: AssetRow): void => {
          this.exportAsset(row, false);
        },
        onForward: (row: AssetRow): void => {
          this.exportAsset(row, true);
        },
        onDropCopy: (row: AssetRow): void => {
          this.dropAsset(row);
        }
      })
    } else if (this.skillsOpen) {
      SkillPanel({
        skills: this.skills,
        bp: this.wBp,
        onClose: (): void => {
          this.skillsOpen = false;
        },
        onPick: (name: string): void => {
          this.skillsOpen = false;
          this.pickSkill(name);
        }
      })
    } else if (this.mcpOpen) {
      McpPanel({
        clients: this.mcpClients,
        bp: this.wBp,
        expanded: this.mcpExpanded,
        tools: this.mcpTools,
        toolsNote: this.mcpToolsNote,
        onClose: (): void => {
          this.mcpOpen = false;
        },
        onToggle: (key: string): void => {
          this.toggleMcp(key);
        }
      })
    } else {
      Column({ space: AppSpace.xxs }) {
        this.header()

      if (this.loadingHistory) {
        Text(Copy.chat_loading_history)
          .fontSize(AppType.body)
          .fontColor(AppColor.text_secondary)
          .width(AppMeasure.text(this.wBp))
      } else {
        // List.space takes number|string only, so the gap comes from item margins.
        List({ scroller: this.scroller }) {
          // The key carries the member count: a tool run grows in place while
          // its first row keeps its key, and ArkUI reuses the old subtree
          // without re-running the item generator for a repeated key.
          ForEach(this.rows(), (row: ChatRow) => {
            ListItem() {
              this.toolRow(row)
            }
            .margin({ bottom: AppSpace.xs })
          }, (row: ChatRow): string => row.key + '#' + row.items.length)
        }
        .width(AppMeasure.text(this.wBp))
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
        .width(AppMeasure.text(this.wBp))
      }, (approval: ApprovalInfo): string => `${approval.request_id}_${this.nowSec}`)

      if (this.recording) {
        Row({ space: AppSpace.sm }) {
          Text('●')
            .fontSize(AppType.body)
            .fontColor(AppColor.warning_text)
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
        .width(AppMeasure.text(this.wBp))
      }

      Composer({
        text: $inputText,
        attachments: $pending,
        busy: this.busy,
        uploading: this.uploading,
        suggestions: this.slashSuggestions(),
        selectors: this.selectors(),
        skills: this.skills,
        recording: this.recording,
        voiceMode: this.voiceMode,
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
        onHoldStart: (): void => {
          this.beginRecord();
        },
        onHoldEnd: (discard: boolean): void => {
          this.endHold(discard);
        },
        onToggleMode: (): void => {
          // Mid-take the mode switch is inert on purpose: hiding the record pill
          // would leave the take with no on-screen stop, and the choice between
          // keeping and discarding it belongs to the recording bar above.
          if (!this.recording) {
            this.voiceMode = !this.voiceMode;
          }
        },
        onRemove: (key: string): void => {
          this.remove(key);
        },
        onPickCommand: (name: string): void => {
          this.pickCommand(name);
        },
        onOpenSkills: (): void => {
          this.openSkills();
        },
        onOpenMcp: (): void => {
          this.openMcp();
        },
        onPickChoice: (key: string, id: string): void => {
          this.pickChoice(key, id);
        },
        onLongText: (): void => {
          // The editor writes into the text field, so it takes the composer back
          // to text mode on its way out — otherwise the long text lands unseen.
          this.voiceMode = false;
          this.showFullScreenEditor = true;
        },
        onTextChanged: (): void => {
          this.onInputChanged();
        }
      })
      .width(AppMeasure.text(this.wBp))

      if (this.uploading) {
        Row({ space: AppSpace.xs }) {
          LoadingProgress()
            .width(AppSize.icon_md)
            .height(AppSize.icon_md)
            .color(AppColor.accent_action)
          Text(Copy.notice_uploading)
            .fontSize(AppType.caption)
            .fontColor(AppColor.text_tertiary)
        }
        .width(AppMeasure.text(this.wBp))
      }
    }
    .alignItems(HorizontalAlign.Center)
    .padding({ left: AppSpace.md, right: AppSpace.md })
    .width('100%')
    .height('100%')
    .backgroundColor(AppColor.bg)
    }
  }
}
