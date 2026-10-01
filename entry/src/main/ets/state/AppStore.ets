/**
 * Session, agent and window-list state: the home page's whole world, plus the
 * pieces the chat page needs (server, token, selected agent).
 *
 * This is the replacement for v1's module-level `client` singleton. Everything is
 * reachable through StoreHub, so a test can build an AppStore over a fake
 * transport and assert on state without a device.
 */
import { common } from '@kit.AbilityKit';
import { AgentApi } from '../api/AgentApi';
import { AuthApi } from '../api/AuthApi';
import { ApiClient } from '../net/ApiClient';
import { LanScan, LanTarget } from '../net/LanScan';
import { Transport } from '../net/Transport';
import { Settings } from '../core/Prefs';
import { Failure } from '../core/Failure';
import { AgentSummary, ApprovalInfo, ChatRef, ChatSpec } from '../model/Dtos';
import { PollSnapshot, PollTarget } from '../polling/GlobalPoller';
import { ChatStatus } from '../core/Wire';
import { Copy } from '../l10n/Copy';

/** How long one configured address gets to answer before the list calls it dead. */
const CONFIG_PROBE_MS: number = 2500;

export class AppStore implements PollTarget {
  server: string = '';
  username: string = '';
  agentId: string = 'default';
  agents: AgentSummary[] = [];
  chats: ChatSpec[] = [];
  approvals: ApprovalInfo[] = [];
  /** The chat the phone last had open; pinned to the top of the home list. */
  foreground: ChatRef | undefined = undefined;
  /** False right after sign-out, even though the server address stays saved. */
  signedIn: boolean = false;
  offline: boolean = false;

  // ---------- login configuration ----------

  /** Every address the settings page knows about, in the order it shows them. */
  servers: string[] = [];
  /** The same addresses, probe-shaped, for the login page's selectable list. */
  savedRows: LanTarget[] = [];
  /** Hosts the last LAN sweep answered as QwenPaw servers. */
  discovered: LanTarget[] = [];
  /** The address the login page signs in against. */
  selected: string = '';
  /** Typed on the settings page; `username` above is the server-issued one. */
  configUsername: string = '';
  password: string = '';
  port: number = LanScan.DEFAULT_PORT;
  scanning: boolean = false;
  scanDone: number = 0;
  scanTotal: number = 0;
  scanFound: number = 0;

  private readonly client: ApiClient;
  private readonly auth: AuthApi;
  private readonly agentApi: AgentApi;
  private readonly transport: Transport;
  private views: Array<() => void> = [];

  constructor(client: ApiClient, auth: AuthApi, agentApi: AgentApi, transport: Transport) {
    this.client = client;
    this.auth = auth;
    this.agentApi = agentApi;
    this.transport = transport;
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
  }

  detachView(onChange: () => void): void {
    const index = this.views.indexOf(onChange);
    if (index >= 0) {
      this.views.splice(index, 1);
    }
  }

  private emit(): void {
    for (const view of this.views.slice()) {
      view();
    }
  }

  // ---------- session ----------

  /** Read the saved session into memory and point the client at it. */
  async restore(ctx: common.Context): Promise<void> {
    this.server = await Settings.serverUrl(ctx);
    this.username = await Settings.username(ctx);
    this.agentId = await Settings.agentId(ctx);
    this.signedIn = await Settings.signedIn(ctx);
    this.client.configure(this.server, await Settings.token(ctx));
    this.client.agentId = this.agentId;
    this.foreground = await Settings.loadLastChat(ctx);
    await this.loadConfig(ctx);
    this.emit();
  }

  hasSavedSession(): boolean {
    return this.signedIn && this.server.length > 0;
  }

  // ---------- login configuration ----------

  /**
   * Pull the settings page's values into memory. A device that predates the list
   * has only `server_url`, which becomes the single entry so an old install still
   * shows its server.
   */
  async loadConfig(ctx: common.Context): Promise<void> {
    this.password = await Settings.password(ctx);
    // Read before the address list: a stored portless entry borrows this port.
    this.port = await Settings.scanPort(ctx);
    const list = await Settings.servers(ctx);
    if (list.length === 0 && this.server.length > 0) {
      list.push(this.server);
    }
    const filled: string[] = [];
    for (const url of list) {
      const full = LanScan.withPort(url, this.port);
      if (filled.indexOf(full) < 0) {
        filled.push(full);
      }
    }
    this.servers = filled;
    const typed = await Settings.configUsername(ctx);
    // A device that configured before this field existed falls back to whatever
    // the last login returned, so the settings page never opens on a blank name.
    this.configUsername = typed.length > 0 ? typed : await Settings.username(ctx);
    this.selected = this.pickable(this.selected) ? this.selected
      : (this.pickable(this.server) ? this.server : this.firstAddress());
    this.rebuildRows();
  }

  private pickable(url: string): boolean {
    return this.servers.indexOf(url) >= 0;
  }

  private firstAddress(): string {
    return this.servers.length > 0 ? this.servers[0] : '';
  }

  /**
   * Write the settings page's form back. Addresses are normalized here so a typed
   * '192.168.1.23:8088' and a scanned 'http://192.168.1.23:8088' are one entry,
   * and a portless entry borrows the scan port: the stored URL is what the client
   * will dial, so probe and login cannot end up aimed at different ports.
   */
  async saveConfig(ctx: common.Context, urls: string[], port: number, username: string,
    password: string): Promise<void> {
    this.port = port >= 1 && port <= 65535 ? port : LanScan.DEFAULT_PORT;
    const cleaned: string[] = [];
    for (const raw of urls) {
      const url = LanScan.withPort(ApiClient.normalize(raw), this.port);
      if (url.length > 0 && cleaned.indexOf(url) < 0) {
        cleaned.push(url);
      }
    }
    this.servers = cleaned;
    this.configUsername = username.trim();
    this.password = password;
    await Settings.saveServers(ctx, cleaned);
    await Settings.saveScanPort(ctx, this.port);
    await Settings.savePassword(ctx, password);
    await Settings.saveConfigUsername(ctx, this.configUsername);
    if (!this.pickable(this.selected)) {
      this.selected = this.firstAddress();
    }
    this.rebuildRows();
    this.emit();
  }

  /** Address rows and discovered rows share LanTarget, so they share the model. */
  private rebuildRows(): void {
    const rows: LanTarget[] = [];
    for (const url of this.servers) {
      rows.push(LanScan.targetOf(url, this.port));
    }
    this.savedRows = rows;
  }

  /** Ask each saved address whether it is up, for the login page's status dots. */
  async probeSaved(): Promise<void> {
    if (this.savedRows.length === 0) {
      return;
    }
    await LanScan.probeAll(this.transport, this.savedRows, CONFIG_PROBE_MS);
    this.savedRows = this.savedRows.slice();
    this.emit();
  }

  /** Mark one saved address as the choice for the login button. */
  pick(url: string): void {
    this.selected = url;
    this.emit();
  }

  /**
   * Sweep the phone's own /24. Progress lands on the store so the page only has to
   * mirror fields; hosts already in the configured list are not listed twice.
   * Returns how many hosts answered, so 'nothing out there' and 'only the servers
   * you already saved' are different messages on the login page.
   */
  async scanLan(): Promise<number> {
    const prefix = LanScan.localPrefix();
    this.scanning = true;
    this.scanDone = 0;
    this.scanTotal = 0;
    this.scanFound = 0;
    this.discovered = [];
    this.emit();
    try {
      if (prefix.length === 0) {
        return 0;
      }
      const found = await LanScan.sweep(this.transport, prefix, this.port,
        (done: number, total: number, hits: number): void => {
          this.scanDone = done;
          this.scanTotal = total;
          this.scanFound = hits;
          this.emit();
        });
      const fresh: LanTarget[] = [];
      for (const t of found) {
        if (!this.pickable(t.url)) {
          fresh.push(t);
        }
      }
      this.discovered = fresh;
      if (this.selected.length === 0 && fresh.length > 0) {
        this.selected = fresh[0].url;
      }
      return found.length;
    } finally {
      this.scanning = false;
      this.emit();
    }
  }

  /** Login uses the settings page's credentials against the selected address. */
  async signInWithConfig(ctx: common.Context): Promise<void> {
    if (this.selected.length === 0) {
      throw Failure.local(Copy.need_selection);
    }
    await this.signIn(ctx, this.selected, this.configUsername, this.password);
  }

  /**
   * Probe /auth/status first: a server with auth off must not ask for a password.
   * Throws Failure so the sign-in page can pick the right copy.
   */
  async signIn(ctx: common.Context, server: string, username: string,
    password: string): Promise<void> {
    const normalized = ApiClient.normalize(server);
    if (normalized.length === 0) {
      throw Failure.local(Copy.need_server_address);
    }
    this.client.configure(normalized, '');
    const st = await this.auth.status();
    if (!st.enabled) {
      await this.persist(ctx, normalized, '', '');
      return;
    }
    const r = await this.auth.login(username, password);
    await this.persist(ctx, normalized, r.token, r.username);
  }

  private async persist(ctx: common.Context, server: string, token: string,
    username: string): Promise<void> {
    this.server = server;
    this.username = username;
    this.signedIn = true;
    this.client.configure(server, token);
    await Settings.saveSession(ctx, server, token, username);
    this.emit();
  }

  /** Sign out drops credentials only; the server address stays for next time. */
  async signOut(ctx: common.Context): Promise<void> {
    this.client.token = '';
    this.username = '';
    this.signedIn = false;
    this.chats = [];
    this.approvals = [];
    this.foreground = undefined;
    await Settings.clearSession(ctx);
    this.emit();
  }

  // ---------- agents ----------

  async refreshAgents(): Promise<void> {
    try {
      this.agents = await this.agentApi.listForChat();
      let found = false;
      for (const a of this.agents) {
        if (a.id === this.agentId) {
          found = true;
        }
      }
      // The selected agent was deleted or disabled: fall back like the console.
      if (!found && this.agents.length > 0) {
        this.setAgent(this.agents[0].id);
      }
    } catch (e) {
      this.agents = [];
    }
    this.emit();
  }

  setAgent(agentId: string): void {
    this.agentId = agentId;
    this.client.agentId = agentId;
    this.chats = [];
    this.emit();
  }

  async saveAgent(ctx: common.Context): Promise<void> {
    await Settings.saveAgentId(ctx, this.agentId);
  }

  agentLabel(agent: AgentSummary): string {
    return agent.startup_status === 'running' ? `● ${agent.name}` : `　 ${agent.name}`;
  }

  currentAgentLabel(): string {
    for (const a of this.agents) {
      if (a.id === this.agentId) {
        return this.agentLabel(a);
      }
    }
    return this.agentId;
  }

  // ---------- windows ----------

  /** Foreground identity: the run the phone is currently reading. */
  foregroundId(): string {
    return this.foreground === undefined ? '' : this.foreground.chatId;
  }

  foregroundChat(): ChatSpec | undefined {
    const id = this.foregroundId();
    if (id.length === 0) {
      return undefined;
    }
    for (const c of this.chats) {
      if (c.id === id) {
        return c;
      }
    }
    return undefined;
  }

  async openChat(ctx: common.Context, ref: ChatRef): Promise<void> {
    this.foreground = ref;
    await Settings.saveLastChat(ctx, ref);
    this.emit();
  }

  /** Stale pointer cleanup: the saved chat no longer exists on the server. */
  reconcileForeground(): void {
    const id = this.foregroundId();
    if (id.length === 0) {
      return;
    }
    if (!this.chats.some((c: ChatSpec): boolean => c.id === id)) {
      this.foreground = undefined;
      this.emit();
    }
  }

  /** Background runs the home badge counts, excluding the foreground window. */
  backgroundRunning(): number {
    const fg = this.foregroundId();
    let n = 0;
    for (const c of this.chats) {
      if (c.status === ChatStatus.RUNNING && c.id !== fg) {
        n += 1;
      }
    }
    return n;
  }

  /** Oldest pending approval's window, so the badge can jump straight to it. */
  approvalChatId(): string {
    if (this.approvals.length === 0) {
      return '';
    }
    const root = this.approvals[0].root_session_id;
    for (const c of this.chats) {
      if (c.session_id === root) {
        return c.id;
      }
    }
    return '';
  }

  onPoll(snapshot: PollSnapshot): void {
    this.chats = snapshot.chats;
    this.approvals = snapshot.approvals;
    // Two failed ticks in a row is a real outage, not one dropped packet.
    this.offline = snapshot.failures >= 2;
    this.reconcileForeground();
    this.emit();
  }
}
