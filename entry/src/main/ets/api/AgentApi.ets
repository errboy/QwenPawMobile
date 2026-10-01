/**
 * Agent picker source. The chat selector keeps agents the server actually
 * offers in chat; PawApp-managed ones report available_in_chat=false.
 */
import { ApiClient } from '../net/ApiClient';
import { AgentListResponse, AgentSummary } from '../model/Dtos';
import { ApiPath } from '../core/Wire';

export class AgentApi {
  private readonly client: ApiClient;

  constructor(client: ApiClient) {
    this.client = client;
  }

  async listForChat(): Promise<AgentSummary[]> {
    const raw = await this.client.get(ApiPath.AGENTS);
    const resp = JSON.parse(raw) as AgentListResponse;
    const usable: AgentSummary[] = [];
    if (resp.agents === undefined) {
      return usable;
    }
    for (const a of resp.agents) {
      if (a.available_in_chat && a.enabled) {
        usable.push(a);
      }
    }
    return usable;
  }
}
