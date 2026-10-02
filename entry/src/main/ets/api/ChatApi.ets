/**
 * Chat, history and the streaming run endpoint.
 * Endpoints are the console ones the web UI uses, so a phone run and a PC run
 * share the same ChatSpec and the same 409-while-running semantics.
 */
import { ApiClient } from '../net/ApiClient';
import { SseHandler, SseSession } from '../net/SseSession';
import { Failure } from '../core/Failure';
import { AgentRequest, ChatHistory, ChatSpec, OutgoingMessage, RequestPart, UploadResult } from '../model/Dtos';
import { ChatPreference } from '../model/ChatPrefs';
import { ApiPath, ContentType } from '../core/Wire';

export class ChatApi {
  private readonly client: ApiClient;

  constructor(client: ApiClient) {
    this.client = client;
  }

  /** GET /api/chats — the same window list the PC console shows. */
  async list(): Promise<ChatSpec[]> {
    const raw = await this.client.get(ApiPath.CHATS);
    const parsed = JSON.parse(raw) as ChatSpec[];
    return parsed === undefined ? [] : parsed;
  }

  async history(chatId: string): Promise<ChatHistory> {
    const raw = await this.client.get(`${ApiPath.CHATS}/${encodeURIComponent(chatId)}`);
    const parsed = JSON.parse(raw) as ChatHistory;
    if (parsed === undefined) {
      throw Failure.parse('历史记录响应为空');
    }
    if (parsed.messages === undefined) {
      parsed.messages = [];
    }
    return parsed;
  }

  /** POST /api/console/chat/stop?chat_id=... — query parameter, no request body. */
  async stop(chatId: string): Promise<void> {
    await this.client.post(`${ApiPath.CONSOLE_CHAT_STOP}?chat_id=${encodeURIComponent(chatId)}`);
  }

  stream(bodyJson: string, handler: SseHandler): SseSession {
    return this.client.startStream(ApiPath.CONSOLE_CHAT, bodyJson, handler);
  }

  /**
   * Map uploaded attachments plus optional text onto content parts, in the same
   * shapes the web console sends: audio carries its path under `data`.
   */
  static buildParts(text: string, uploads: UploadResult[], mimes: string[]): RequestPart[] {
    const parts: RequestPart[] = [];
    if (text.length > 0) {
      const t = new RequestPart();
      t.type = ContentType.TEXT;
      t.text = text;
      parts.push(t);
    }
    for (let i = 0; i < uploads.length; i++) {
      const upload = uploads[i];
      const mime = i < mimes.length ? mimes[i] : '';
      const part = new RequestPart();
      if (mime.startsWith('image/')) {
        part.type = ContentType.IMAGE;
        part.image_url = upload.url;
      } else if (mime.startsWith('video/')) {
        part.type = ContentType.VIDEO;
        part.video_url = upload.url;
      } else if (mime.startsWith('audio/')) {
        part.type = ContentType.AUDIO;
        part.data = upload.url;
      } else {
        part.type = ContentType.FILE;
        part.file_url = upload.url;
        part.file_name = upload.file_name;
      }
      parts.push(part);
    }
    return parts;
  }

  /**
   * `pref` rides along as pass-through body fields: leaving both unset is what
   * "follow the desktop's own default" looks like on the wire, because the server
   * only reads them when they are present.
   */
  static bodyOf(sessionId: string, parts: RequestPart[], userId: string | undefined,
    pref?: ChatPreference): string {
    const message = new OutgoingMessage();
    message.role = 'user';
    message.content = parts;
    const body = new AgentRequest();
    body.input = [message];
    body.session_id = sessionId;
    if (userId !== undefined && userId.length > 0) {
      body.user_id = userId;
    }
    if (pref !== undefined) {
      // An unknown stored level sends nothing, which is the server's own AUTO.
      body.request_context = pref.approvalOverride();
      body.model_slot_override = pref.modelOverride();
    }
    return JSON.stringify(body);
  }

  /** reconnect=true attaches to a run started elsewhere and replays its buffer. */
  static reconnectBody(sessionId: string, userId: string | undefined): string {
    const body = new AgentRequest();
    body.session_id = sessionId;
    body.reconnect = true;
    body.input = [];
    if (userId !== undefined && userId.length > 0) {
      body.user_id = userId;
    }
    return JSON.stringify(body);
  }
}
