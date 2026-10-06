/**
 * Governance approvals. A high-risk tool call parks its run until someone
 * answers, so this is the one API that can unblock a stalled generation.
 */
import { ApiClient } from '../net/ApiClient';
import { ApprovalActionRequest, ApprovalActionResponse, ApprovalInfo, ApprovalListResponse } from '../model/Dtos';
import { ApiPath, ApprovalScope } from '../core/Wire';
import { expectList } from './Shape';

export class ApprovalApi {
  private readonly client: ApiClient;

  constructor(client: ApiClient) {
    this.client = client;
  }

  /**
   * GET /api/approval/list. Without a session it reports every pending approval
   * for the active agent; with one it aggregates that root session's children.
   */
  async list(sessionId?: string): Promise<ApprovalInfo[]> {
    const query = sessionId !== undefined && sessionId.length > 0
      ? `?session_id=${encodeURIComponent(sessionId)}` : '';
    const raw = await this.client.get(`${ApiPath.APPROVAL_LIST}${query}`);
    const resp = JSON.parse(raw) as ApprovalListResponse;
    return resp.pending_approvals === undefined ? []
      : expectList<ApprovalInfo>(resp.pending_approvals, ApiPath.APPROVAL_LIST);
  }

  /**
   * Approve with least privilege: scope 'exact' records only the literal target,
   * never the generalized pattern.
   */
  async approve(approval: ApprovalInfo, userId: string | undefined): Promise<ApprovalActionResponse> {
    const body = this.bodyFor(approval, userId);
    body.scope = ApprovalScope.EXACT;
    const raw = await this.client.post(ApiPath.APPROVAL_APPROVE, JSON.stringify(body));
    return JSON.parse(raw) as ApprovalActionResponse;
  }

  async deny(approval: ApprovalInfo, reason: string,
    userId: string | undefined): Promise<ApprovalActionResponse> {
    const body = this.bodyFor(approval, userId);
    body.reason = reason;
    const raw = await this.client.post(ApiPath.APPROVAL_DENY, JSON.stringify(body));
    return JSON.parse(raw) as ApprovalActionResponse;
  }

  /** The server 403s unless session_id equals the approval's root session. */
  private bodyFor(approval: ApprovalInfo, userId: string | undefined): ApprovalActionRequest {
    const body = new ApprovalActionRequest();
    body.request_id = approval.request_id;
    body.session_id = approval.root_session_id;
    if (userId !== undefined && userId.length > 0) {
      body.user_id = userId;
    }
    return body;
  }

  /** Which chat a pending approval belongs to, for client-side list filtering. */
  static belongsTo(approval: ApprovalInfo, sessionId: string): boolean {
    if (sessionId.length === 0) {
      return false;
    }
    return approval.session_id === sessionId || approval.root_session_id === sessionId;
  }
}
