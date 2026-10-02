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
import { HttpTransport } from '../net/HttpTransport';
import { Transport } from '../net/Transport';
import { MediaLoader } from '../media/MediaLoader';
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
    const created = new ChatStore(ref, this.chatApi, this.uploadApi, this.approvalApi, this.media);
    this.chatStores.set(ref.chatId, created);
    return created;
  }

  peekChatStore(chatId: string): ChatStore | undefined {
    return this.chatStores.get(chatId);
  }

  /** A window deleted on the PC: throw its store away, streams included. */
  forgetChat(chatId: string): void {
    const store = this.chatStores.get(chatId);
    if (store !== undefined) {
      store.dispose();
      this.chatStores.delete(chatId);
    }
  }

  /** Sign-out: release every run and forget decoded media so no token stays live. */
  reset(): void {
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
    await this.app.restore(ctx);
    if (this.app.hasSavedSession()) {
      await this.app.refreshAgents();
      this.poller.start();
      this.poller.poke();
    }
  }
}
