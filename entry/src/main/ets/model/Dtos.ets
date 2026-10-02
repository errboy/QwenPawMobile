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

/**
 * Body of POST /chats. The server mints the chat id; the client only names the
 * session, which is exactly what the web console's "new chat" sends.
 */
export class NewChatRequest {
  session_id: string = '';
  user_id: string = 'default';
  channel: string = 'console';
  name: string = '';
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

/** Per-request model pick, read out of the chat body by agents/model_factory.py. */
export class ModelSlot {
  provider_id: string = '';
  model: string = '';
}

/** Only approval_level is used; the rest of the context is server-internal. */
export class RequestContext {
  approval_level?: string;
}

/** Body of POST /api/console/chat (AgentRequest envelope, extra="allow"). */
export class AgentRequest {
  input: OutgoingMessage[] = [];
  session_id: string = '';
  user_id?: string;
  stream: boolean = true;
  /** True re-attaches to a run already in flight and replays buffered frames. */
  reconnect?: boolean;
  /** Both of these are pass-through: omitted means 'follow the desktop's own default'. */
  request_context?: RequestContext;
  model_slot_override?: ModelSlot;
}

// ---------- composer capabilities (all read-only) ----------

/** One entry of /workspace/commands/available; `name` carries no leading slash. */
export class SlashCommand {
  name: string = '';
  description: string = '';
  category: string = '';
}

export class CommandListResponse {
  commands: SlashCommand[] = [];
}

/**
 * One loop mode. The server has no setter for the active mode: `slash_command`
 * is what gets prefixed to the message text so the runtime's slash dispatch
 * picks the loop.
 */
export class LoopModeInfo {
  id: string = '';
  name: string = '';
  /** Empty for the built-in 'default' loop, which needs no prefix. */
  slash_command: string = '';
  description: string = '';
  /** builtin | custom | plugin. */
  source: string = 'builtin';
  name_i18n?: Record<string, string>;
  description_i18n?: Record<string, string>;
}

export class LoopModeStatus {
  /** idle | running | awaiting_user. A prefix may only be applied while idle. */
  state: string = 'idle';
  mode?: LoopModeInfo;
}

export class ModelInfo {
  id: string = '';
  name: string = '';
}

/**
 * The phone reads only enough to rebuild the PC chat picker: a provider is
 * offerable when it has models and the credential it demands is present.
 */
export class ProviderInfo {
  id: string = '';
  name: string = '';
  base_url: string = '';
  api_key: string = '';
  models: ModelInfo[] = [];
  extra_models: ModelInfo[] = [];
  is_free_tier: boolean = false;
  is_custom: boolean = false;
  is_local: boolean = false;
  require_api_key: boolean = true;
}

/** GET /models/active. Null active_llm means the agent has no configured slot. */
export class ActiveModelsResponse {
  active_llm?: ModelSlot;
}

/** GET /settings/upload-limit. Absent means the server set no cap. */
export class UploadLimit {
  upload_max_size_mb?: number;
}

/**
 * GET /workspace/running-config. The document is large and the picker needs one
 * field of it; the phone never writes any of it back.
 */
export class RunningConfigLevel {
  approval_level?: string;
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
  audio_url?: string;
  file_url?: string;
  file_name?: string;
  content?: ContentPart[];
  output?: ChatMessageModel[];
}
