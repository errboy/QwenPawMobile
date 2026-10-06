/**
 * Read-only composer capabilities: the slash-command list, loop catalog, model
 * list, skill list, MCP inventory and upload cap that sit above the PC console's
 * input box.
 *
 * Nothing in this class writes. A model or approval choice reaches the server as
 * a pass-through field on the chat body, never as a PUT: /workspace/running-config
 * replaces the whole document, so one stray tap would rewrite the desktop's own
 * configuration for every agent.
 */
import { ApiClient } from '../net/ApiClient';
import {
  ActiveModelsResponse,
  CommandListResponse,
  LoopModeInfo,
  LoopModeStatus,
  MCPClientInfo,
  MCPToolInfo,
  ModelSlot,
  ProviderInfo,
  RunningConfigLevel,
  SkillSpec,
  SlashCommand,
  UploadLimit
} from '../model/Dtos';
import { ApiPath, ApprovalLevel, Channel } from '../core/Wire';
import { Parts } from '../model/Parts';
import { Providers } from '../model/Providers';
import { expectList } from './Shape';

export class ComposerApi {
  private readonly client: ApiClient;

  constructor(client: ApiClient) {
    this.client = client;
  }

  /** Names without a leading slash; the sender adds it. */
  async commands(): Promise<SlashCommand[]> {
    const raw = await this.client.get(ApiPath.COMMANDS_AVAILABLE);
    const parsed = JSON.parse(raw) as CommandListResponse;
    const rows = parsed === undefined ? undefined : parsed.commands;
    if (rows === undefined) {
      return [];
    }
    const out: SlashCommand[] = [];
    for (const c of rows) {
      const item = new SlashCommand();
      item.name = Parts.str(c.name);
      item.description = Parts.str(c.description);
      item.category = Parts.str(c.category);
      if (item.name.length > 0) {
        out.push(item);
      }
    }
    return out;
  }

  /** A bare JSON array, not an envelope. */
  async loops(): Promise<LoopModeInfo[]> {
    const raw = await this.client.get(ApiPath.LOOPS);
    const rows = expectList<LoopModeInfo>(JSON.parse(raw), ApiPath.LOOPS);
    const out: LoopModeInfo[] = [];
    for (const m of rows) {
      const item = new LoopModeInfo();
      item.id = Parts.str(m.id);
      item.name = Parts.str(m.name);
      item.slash_command = Parts.str(m.slash_command);
      item.description = Parts.str(m.description);
      item.source = Parts.str(m.source);
      item.name_i18n = m.name_i18n;
      item.description_i18n = m.description_i18n;
      if (item.id.length > 0) {
        out.push(item);
      }
    }
    return out;
  }

  async loopStatus(chatId: string): Promise<LoopModeStatus> {
    const raw = await this.client.get(
      `${ApiPath.LOOPS_STATUS}?chat_id=${encodeURIComponent(chatId)}`);
    const parsed = JSON.parse(raw) as LoopModeStatus;
    return parsed === undefined ? new LoopModeStatus() : parsed;
  }

  /** Every provider, configured or not; the picker applies the eligibility test. */
  async providers(): Promise<ProviderInfo[]> {
    const raw = await this.client.get(ApiPath.MODELS);
    const parsed = expectList<ProviderInfo>(JSON.parse(raw), ApiPath.MODELS);
    return Providers.normalize(parsed);
  }

  /**
   * The slot the server would use if the phone sent no override. scope=effective
   * resolves the agent from the X-Agent-Id header the client already sends.
   */
  async activeModel(): Promise<ModelSlot | undefined> {
    const raw = await this.client.get(`${ApiPath.MODELS_ACTIVE}?scope=effective`);
    const parsed = JSON.parse(raw) as ActiveModelsResponse;
    const slot = parsed === undefined ? undefined : parsed.active_llm;
    if (slot === undefined || Parts.str(slot.provider_id).length === 0) {
      return undefined;
    }
    return slot;
  }

  /**
   * The level this agent runs with when a message carries no override, which is
   * what the chip shows behind 'follow the desktop'. Read only: the matching PUT
   * replaces the entire running config, so writing it would rewrite the desk's
   * own settings for every agent.
   */
  async runningConfigApproval(): Promise<string> {
    const raw = await this.client.get(ApiPath.RUNNING_CONFIG);
    const parsed = JSON.parse(raw) as RunningConfigLevel;
    const level = parsed === undefined ? undefined : parsed.approval_level;
    const value = Parts.str(level).toUpperCase();
    return ApprovalLevel.isKnown(value) ? value : '';
  }

  /** Zero means the server set no cap; the field is explicitly null in that case. */
  async uploadLimitMb(): Promise<number> {
    const raw = await this.client.get(ApiPath.SETTINGS_UPLOAD_LIMIT);
    const parsed = JSON.parse(raw) as UploadLimit;
    const mb = parsed === undefined ? undefined : parsed.upload_max_size_mb;
    return typeof mb === 'number' ? mb : 0;
  }

  /**
   * Skills the phone can actually run: enabled, and declaring a channel the phone
   * sends on. Enabling a skill is a desktop-side write, so one that is switched off
   * is listed nowhere in this app rather than offered greyed out.
   */
  async skills(): Promise<SkillSpec[]> {
    const raw = await this.client.get(ApiPath.SKILLS);
    const rows = expectList<SkillSpec>(JSON.parse(raw), ApiPath.SKILLS);
    const out: SkillSpec[] = [];
    for (const s of rows) {
      const item = new SkillSpec();
      item.name = Parts.str(s.name);
      item.description = Parts.str(s.description);
      item.emoji = Parts.str(s.emoji);
      item.enabled = s.enabled === true;
      item.channels = s.channels === undefined ? [] : s.channels;
      if (item.name.length > 0 && item.enabled && Channel.reachable(item.channels)) {
        out.push(item);
      }
    }
    return out;
  }

  /** MCP clients as configured on the desktop. Read-only; see MCPClientInfo on what is not read out. */
  async mcpClients(): Promise<MCPClientInfo[]> {
    const raw = await this.client.get(ApiPath.MCP);
    const rows = expectList<MCPClientInfo>(JSON.parse(raw), ApiPath.MCP);
    const out: MCPClientInfo[] = [];
    for (const c of rows) {
      const item = new MCPClientInfo();
      item.key = Parts.str(c.key);
      item.name = Parts.str(c.name);
      item.description = Parts.str(c.description);
      item.enabled = c.enabled === true;
      item.transport = Parts.str(c.transport);
      if (item.key.length > 0) {
        out.push(item);
      }
    }
    return out;
  }

  /**
   * A client's tools. A disabled client answers with an empty list, which reads as
   * 'no tools' unless the caller keeps the enabled flag next to it.
   */
  async mcpTools(key: string): Promise<MCPToolInfo[]> {
    const raw = await this.client.get(`${ApiPath.MCP_TOOLS}/${encodeURIComponent(key)}`);
    const rows = expectList<MCPToolInfo>(JSON.parse(raw), ApiPath.MCP_TOOLS);
    const out: MCPToolInfo[] = [];
    for (const t of rows) {
      const item = new MCPToolInfo();
      item.name = Parts.str(t.name);
      item.description = Parts.str(t.description);
      item.enabled = t.enabled !== false;
      if (item.name.length > 0) {
        out.push(item);
      }
    }
    return out;
  }
}
