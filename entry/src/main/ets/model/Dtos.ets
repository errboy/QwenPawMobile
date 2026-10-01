/**
 * Wire DTOs for QwenPaw v2.2.2-beta.4 (snake_case preserved).
 * Parsed with `JSON.parse(x) as T`, so a field the server omits stays
 * undefined at runtime even though the class declares a default.
 */
import { ContentPart, DataPayload } from './Content';

export class AuthStatus {
  enabled: boolean = false;
  has_users: boolean = false;
}

export class LoginRequest {
  username: string = '';
  password: string = '';
  /** 0 or -1 asks the server for a non-expiring token. */
  expires_in: number = 0;
}

export class LoginResponse {
  token: string = '';
  username: string = '';
}

export class AgentSummary {
  id: string = '';
  name: string = '';
  description: string = '';
  enabled: boolean = false;
  pinned: boolean = false;
  /** AgentStartupStatus; only 'running' is rendered with an active dot. */
  startup_status: string = '';
  backend: string = 'qwenpaw';
  /** False for agents managed by a PawApp; they must not appear in the picker. */
  available_in_chat: boolean = true;
}

export class AgentListResponse {
  agents: AgentSummary[] = [];
}

export class ChatSpec {
  id: string = '';
  name: string = '';
  /** 'channel:user_id'; the key the run and approvals are addressed by. */
  session_id: string = '';
  user_id: string = '';
  channel: string = 'console';
  created_at: string = '';
  updated_at: string = '';
  /** Live value: the server overwrites it from the task tracker (idle|running). */
  status: string = 'idle';
  pinned: boolean = false;
  archived: boolean = false;
  source: string = 'chat';
  root_session_id: string = '';
}

export class ChatHistory {
  messages: ChatMessageModel[] = [];
  status: string = 'idle';
}

export class ChatMessageModel {
  id: string = '';
  type: string = 'message';
  role: string = '';
  content: ContentPart[] = [];
  status: string = '';
}

/** Identity of a chat the phone should reopen after login. Doubles as route params. */
export class ChatRef {
  chatId: string = '';
  sessionId: string = '';
  userId: string = '';
  title: string = '';
}

export class ApprovalInfo {
  request_id: string = '';
  session_id: string = '';
  root_session_id: string = '';
  owner_agent_id: string = '';
  agent_id: string = '';
  tool_name: string = '';
  tool_display_name: string = '';
  tool_source: string = '';
  exact_target: string = '';
  similar_target: string = '';
  is_generalized: boolean = false;
  severity: string = '';
  findings_count: number = 0;
  /** Epoch seconds. */
  created_at: number = 0;
  timeout_seconds: number = 0;
  result_summary: string = '';
  reasoning: string = '';
}

export class ApprovalListResponse {
  pending_approvals: ApprovalInfo[] = [];
  count: number = 0;
}

export class ApprovalActionRequest {
  request_id: string = '';
  /** Must carry the approval's root_session_id, or the server replies 403. */
  session_id: string = '';
  user_id?: string;
  reason?: string;
  scope?: string;
}

export class ApprovalActionResponse {
  success: boolean = false;
  message: string = '';
  tool_name?: string;
  request_id: string = '';
}

/** Response of POST /api/console/upload; `url` is an absolute stored path. */
export class UploadResult {
  url: string = '';
  file_name: string = '';
  size: number = 0;
}

/** Outgoing content part inside AgentRequest.input[].content. */
export class RequestPart {
  type: string = 'text';
  text?: string;
  image_url?: string;
  video_url?: string;
  /** Audio carries its stored path here, not under a `url` key. */
  data?: string;
  file_url?: string;
  file_name?: string;
}

export class OutgoingMessage {
  role: string = 'user';
  content: RequestPart[] = [];
}

/** Body of POST /api/console/chat (AgentRequest envelope, extra="allow"). */
export class AgentRequest {
  input: OutgoingMessage[] = [];
  session_id: string = '';
  user_id?: string;
  stream: boolean = true;
  /** True re-attaches to a run already in flight and replays buffered frames. */
  reconnect?: boolean;
}

/**
 * Any frame from POST /api/console/chat.
 * `error` is Object on purpose: response frames carry {code,message},
 * transport frames carry a bare string.
 */
export class SseFrame {
  object?: string;
  id?: string;
  type?: string;
  role?: string;
  status?: string;
  delta?: boolean;
  text?: string;
  index?: number;
  msg_id?: string;
  session_id?: string;
  sequence_number?: number;
  error?: Object;
  data?: DataPayload;
  image_url?: string;
  video_url?: string;
  content?: ContentPart[];
  output?: ChatMessageModel[];
}
