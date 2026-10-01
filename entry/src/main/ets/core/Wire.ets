/**
 * Backend wire vocabulary for QwenPaw v2.2.2-beta.4.
 * These literals are the single source of truth: no other module may spell out
 * a status, object kind or content type by hand.
 */

/** Top-level discriminator on every console SSE frame. */
export class SseObject {
  static readonly RESPONSE: string = 'response';
  static readonly MESSAGE: string = 'message';
  static readonly CONTENT: string = 'content';
}

/** Message.type values. Call-side kinds are grouped in ToolTypes. */
export class MsgType {
  static readonly MESSAGE: string = 'message';
  static readonly REASONING: string = 'reasoning';
  static readonly PLUGIN_CALL: string = 'plugin_call';
  static readonly PLUGIN_CALL_OUTPUT: string = 'plugin_call_output';
  static readonly FUNCTION_CALL: string = 'function_call';
  static readonly FUNCTION_CALL_OUTPUT: string = 'function_call_output';
  static readonly MCP_TOOL_CALL: string = 'mcp_tool_call';
  static readonly MCP_TOOL_CALL_OUTPUT: string = 'mcp_tool_call_output';
  static readonly PROGRESS: string = 'progress';
  static readonly RESULT: string = 'result';
  /** Keep-alive frame; carries no content and must stay invisible. */
  static readonly HEARTBEAT: string = 'heartbeat';
}

/** Tool frames render as one card; the output variants carry the result. */
export class ToolTypes {
  static readonly CALLS: string[] = [MsgType.PLUGIN_CALL, MsgType.FUNCTION_CALL, MsgType.MCP_TOOL_CALL];
  static readonly OUTPUTS: string[] =
    [MsgType.PLUGIN_CALL_OUTPUT, MsgType.FUNCTION_CALL_OUTPUT, MsgType.MCP_TOOL_CALL_OUTPUT];

  static isCall(type: string): boolean {
    return ToolTypes.CALLS.includes(type);
  }

  static isOutput(type: string): boolean {
    return ToolTypes.OUTPUTS.includes(type);
  }

  static isTool(type: string): boolean {
    return ToolTypes.isCall(type) || ToolTypes.isOutput(type);
  }
}

/** RunStatus shared by response/message frames. Only the last three are terminal. */
export class RunStatus {
  static readonly CREATED: string = 'created';
  static readonly IN_PROGRESS: string = 'in_progress';
  static readonly COMPLETED: string = 'completed';
  static readonly FAILED: string = 'failed';
  static readonly CANCELLED: string = 'cancelled';

  static isTerminal(status: string): boolean {
    return status === RunStatus.COMPLETED || status === RunStatus.FAILED
      || status === RunStatus.CANCELLED;
  }
}

export class ContentType {
  static readonly TEXT: string = 'text';
  static readonly IMAGE: string = 'image';
  static readonly AUDIO: string = 'audio';
  static readonly VIDEO: string = 'video';
  static readonly DATA: string = 'data';
  static readonly FILE: string = 'file';
  static readonly REFUSAL: string = 'refusal';
}

/** Frame `type` values that carry no `object` field. */
export class FrameType {
  static readonly REPLAY_END: string = 'replay_end';
  static readonly RATE_LIMITED: string = 'rate_limited';
  static readonly TURN_USAGE: string = 'turn_usage';
}

/** ChatSpec.status / ChatHistory.status: the server overwrites these live. */
export class ChatStatus {
  static readonly IDLE: string = 'idle';
  static readonly RUNNING: string = 'running';
}

export class Role {
  static readonly USER: string = 'user';
  static readonly ASSISTANT: string = 'assistant';
  static readonly SYSTEM: string = 'system';
  static readonly TOOL: string = 'tool';
}

/** REST paths, always relative to {server}/api. */
export class ApiPath {
  static readonly AUTH_STATUS: string = '/auth/status';
  static readonly AUTH_LOGIN: string = '/auth/login';
  static readonly AGENTS: string = '/agents';
  static readonly CHATS: string = '/chats';
  static readonly CONSOLE_CHAT: string = '/console/chat';
  static readonly CONSOLE_CHAT_STOP: string = '/console/chat/stop';
  static readonly CONSOLE_UPLOAD: string = '/console/upload';
  static readonly APPROVAL_LIST: string = '/approval/list';
  static readonly APPROVAL_APPROVE: string = '/approval/approve';
  static readonly APPROVAL_DENY: string = '/approval/deny';
  static readonly FILES_PREVIEW: string = '/files/preview';
}

export class Http {
  static readonly OK_LOW: number = 200;
  static readonly OK_HIGH: number = 300;
  static readonly UNAUTHORIZED: number = 401;
  static readonly FORBIDDEN: number = 403;
  static readonly NOT_FOUND: number = 404;
  static readonly CONFLICT: number = 409;
  static readonly LOCKED: number = 423;
  static readonly TOO_MANY: number = 429;
}

/** Governance approval severity; drives the card's colour family. */
export class Severity {
  static readonly CRITICAL: string = 'critical';
  static readonly HIGH: string = 'high';
  static readonly MEDIUM: string = 'medium';

  static isError(value: string): boolean {
    const v = value.toLowerCase();
    return v === Severity.CRITICAL || v === Severity.HIGH;
  }

  static isWarning(value: string): boolean {
    return value.toLowerCase() === Severity.MEDIUM;
  }
}

/** Least privilege: approving records the literal target only. */
export class ApprovalScope {
  static readonly EXACT: string = 'exact';
  static readonly SIMILAR: string = 'similar';
}
