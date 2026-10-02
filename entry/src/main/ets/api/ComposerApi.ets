/**
 * Read-only composer capabilities: the slash-command list, loop catalog, model
 * list and upload cap that sit above the PC console's input box.
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
  ModelSlot,
  ProviderInfo,
  RunningConfigLevel,
  SlashCommand,
  UploadLimit
} from '../model/Dtos';
import { ApiPath, ApprovalLevel } from '../core/Wire';
import { Parts } from '../model/Parts';
import { Providers } from '../model/Providers';

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
    const rows = JSON.parse(raw) as LoopModeInfo[];
    if (rows === undefined) {
      return [];
    }
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
    const parsed = JSON.parse(raw) as ProviderInfo[];
    return parsed === undefined ? [] : Providers.normalize(parsed);
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
}
