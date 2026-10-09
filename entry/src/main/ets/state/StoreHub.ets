/**
 * Composition root.
 *
 * v1 had a module-level `client` that every page imported and mutated, so state
 * was global, order-dependent and impossible to substitute in a test. Here one hub
 * owns the transport and every store, and the constructor takes the transport so a
 * test can build a hub over a fake without a device.
 */
import { common } from '@kit.AbilityKit';
import { AgentApi } from '../api/AgentApi';
import { ApprovalApi } from '../api/ApprovalApi';
import { AuthApi } from '../api/AuthApi';
import { ChatApi } from '../api/ChatApi';
import { ComposerApi } from '../api/ComposerApi';
import { UploadApi } from '../api/UploadApi';
import { ApiClient } from '../net/ApiClient';
import { ChatPreferences } from '../core/Prefs';
import { CleanupFile, CleanupPicks, CleanupTally } from '../model/Cleanup';
import { HttpTransport } from '../net/HttpTransport';
import { Transport } from '../net/Transport';
import { MediaLoader } from '../media/MediaLoader';
import { LongTextStore } from '../media/LongTextStore';
import { AudioPlayer } from '../media/AudioPlayer';
import { Parts } from '../model/Parts';
import { ChatRef } from '../model/Dtos';
import { GlobalPoller } from '../polling/GlobalPoller';
import { AppStore } from './AppStore';
import { ChatStore } from './ChatStore';

export class StoreHub {
  readonly transport: Transport;
  readonly client: ApiClient;
  readonly auth: AuthApi;
  readonly agentApi: AgentApi;
  readonly chatApi: ChatApi;
  readonly composerApi: ComposerApi;
  readonly approvalApi: ApprovalApi;
  readonly uploadApi: UploadApi;
  readonly media: MediaLoader;
  /** The phone's copies of messages that outgrew the model's window. */
  readonly longText: LongTextStore;
  /** One speaker for the whole app, so two windows cannot play over each other. */
  readonly audio: AudioPlayer;
  readonly poller: GlobalPoller;
  readonly app: AppStore;
  private readonly chatStores: Map<string, ChatStore> = new Map();
  private static instance?: StoreHub;
  private ready?: Promise<void>;
  context?: common.Context;

  constructor(transport?: Transport) {
    const http = transport === undefined ? new HttpTransport() : transport;
    this.transport = http;
    this.client = new ApiClient(http);
    this.auth = new AuthApi(this.client);
    this.agentApi = new AgentApi(this.client);
    this.chatApi = new ChatApi(this.client);
    this.composerApi = new ComposerApi(this.client);
    this.approvalApi = new ApprovalApi(this.client);
    this.uploadApi = new UploadApi(this.client);
    this.media = new MediaLoader(this.client);
    this.longText = new LongTextStore();
    this.audio = new AudioPlayer();
    this.app = new AppStore(this.client, this.auth, this.agentApi, http);
    this.poller = new GlobalPoller(this.chatApi, this.approvalApi);
    this.poller.register(this.app);
  }

  /** The app-wide hub; tests build their own and never call this. */
  static shared(): StoreHub {
    if (StoreHub.instance === undefined) {
      StoreHub.instance = new StoreHub();
    }
    return StoreHub.instance;
  }

  /**
   * One store per chat, reused when the user returns to a window that is still
   * streaming, so a page pop does not drop an in-flight run.
   */
  chatStoreFor(ref: ChatRef): ChatStore {
    const existing = this.chatStores.get(ref.chatId);
    if (existing !== undefined) {
      existing.rebind(ref.chatId, ref.sessionId, ref.userId);
      return existing;
    }
    const created = new ChatStore(ref, this.chatApi, this.uploadApi, this.approvalApi,
      this.media, this.audio);
    this.chatStores.set(ref.chatId, created);
    return created;
  }

  peekChatStore(chatId: string): ChatStore | undefined {
    return this.chatStores.get(chatId);
  }

  /**
   * Open a fresh window and make it the foreground one at once. The session key is
   * named here — like the web console does — but the chat id comes back from the
   * server, so a phone window stays addressable by approvals exactly as a PC one.
   */
  async newChat(ctx: common.Context, name: string): Promise<ChatRef> {
    const sessionId: string = `${Date.now()}-${Math.floor(Math.random() * 1000000)}`;
    const spec = await this.chatApi.create(name, sessionId);
    const ref = new ChatRef();
    ref.chatId = spec.id;
    ref.sessionId = spec.session_id;
    ref.userId = spec.user_id;
    ref.title = spec.name;
    await this.app.openChat(ctx, ref);
    this.poller.poke();
    return ref;
  }

  /** A window deleted on the PC: throw its store away, streams included. */
  forgetChat(chatId: string): void {
    const store = this.chatStores.get(chatId);
    if (store !== undefined) {
      store.dispose();
      this.chatStores.delete(chatId);
    }
  }

  /**
   * Read the device for the cleanup page: every local copy with its size and last
   * write, sorted into the buckets the page rows are, plus the one preference store
   * that is safe to reset. The counts come out of the same list the per-file rows
   * show, so a category can never promise more than its children hold.
   *
   * A cached copy is stored under a hash of the reference it came from, so the
   * original name is nowhere on the device. The one copy of that mapping is in
   * memory: every reference an open store still holds is hashed back and matched
   * against what the device listed. A copy nothing references any more — including
   * one whose chat has not been opened since the app started — keeps an empty
   * label, and the page then names it by the file it actually is on the device.
   *
   * The long text keeps are merged in beside the cache. They carry their real
   * names already, so they need no label recovery — and they are not a cache, so
   * only this page ever removes them.
   */
  async tally(ctx: common.Context): Promise<CleanupTally> {
    const out = new CleanupTally();
    const files = this.media.files();
    for (const f of this.longText.files()) {
      files.push(f);
    }
    files.sort((a: CleanupFile, b: CleanupFile): number => b.modified - a.modified);
    const labels = this.cachedLabels();
    for (const f of files) {
      const label = labels.get(f.name);
      f.label = label === undefined ? '' : label;
      out.add(f.kind, f.bytes);
    }
    out.files = files;
    out.choices = await ChatPreferences.choiceCount(ctx);
    return out;
  }

  /** On-disk name of every reference an open store holds → the name the user saw. */
  private cachedLabels(): Map<string, string> {
    const out: Map<string, string> = new Map();
    for (const store of this.chatStores.values()) {
      for (const item of store.items) {
        this.rememberLabel(out, item.videoRef, Parts.leafOf(item.videoRef));
        this.rememberLabel(out, item.audioRef, Parts.leafOf(item.audioRef));
        // The naming the asset panel already shows for the same object: a file by
        // the last two segments of its path.
        this.rememberLabel(out, item.fileRef, Parts.shortPath(item.fileName));
      }
    }
    return out;
  }

  private rememberLabel(out: Map<string, string>, ref: string, label: string): void {
    if (ref.length > 0 && label.length > 0) {
      out.set(this.media.nameOf(ref), label);
    }
  }

  /**
   * Local cleanup, chosen on the cleanup page — one file at a time or a whole
   * category, which is the same delete with more of its rows ticked. Nothing here
   * touches the server's transcript: deleting a window is the PC's decision, and a
   * phone tap must not erase it for every device that shares the account.
   *
   * Returns what actually went, which can be less than what was asked for: the
   * system reclaims the cache on its own, and a clip a player still holds open
   * refuses. Saying '已清理 3 项' after two went would be a lie about the third.
   */
  async runCleanup(ctx: common.Context, picks: CleanupPicks): Promise<number> {
    if (picks.files.length === 0 && !picks.choices) {
      return 0;
    }
    if (picks.files.length > 0) {
      // A clip still held open by the player refuses to go, so stop it first.
      this.audio.stop();
    }
    const names: string[] = [];
    for (const f of picks.files) {
      names.push(f.name);
    }
    let gone: number = this.media.dropFiles(names) + this.longText.dropFiles(names);
    if (picks.choices) {
      await ChatPreferences.clearChoices(ctx);
      gone += 1;
    }
    return gone;
  }

  /** Sign-out: release every run and forget decoded media so no token stays live. */
  reset(): void {
    this.audio.stop();
    this.chatStores.forEach((store: ChatStore): void => {
      store.dispose();
    });
    this.chatStores.clear();
    this.media.clear();
    this.poller.stop();
  }

  /**
   * Called once from the ability. Pages await the same promise instead of racing
   * the preference read, which is how v1's login screen could submit against a
   * client that had not been configured yet.
   */
  start(ctx: common.Context): Promise<void> {
    if (this.ready === undefined) {
      this.ready = this.boot(ctx);
    }
    return this.ready;
  }

  private async boot(ctx: common.Context): Promise<void> {
    this.context = ctx;
    // Video and audio play from the sandbox, so the cache needs a directory before
    // the first window can ask a clip to load.
    this.media.bind(ctx);
    // Same for the long text keeps: a send that outgrew the model's window writes
    // its copy the moment it is sent, and there has to be somewhere for it to go.
    this.longText.bind(ctx);
    await this.app.restore(ctx);
    if (this.app.hasSavedSession()) {
      await this.app.refreshAgents();
      this.poller.start();
      this.poller.poke();
    }
  }
}
