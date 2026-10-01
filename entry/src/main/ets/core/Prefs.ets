/**
 * Typed, lazily-opened persistence. Every read carries a declared fallback and
 * every object is validated after parse, so a corrupted entry degrades to
 * 'not signed in' instead of throwing inside a page.
 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { ChatRef } from '../model/Dtos';

const STORE_NAME: string = 'qwenpaw_store';

class Key {
  static readonly SERVER: string = 'server_url';
  static readonly TOKEN: string = 'auth_token';
  static readonly USERNAME: string = 'username';
  static readonly AGENT: string = 'agent_id';
  static readonly THEME_MODE: string = 'theme_mode';
  static readonly LAST_CHAT: string = 'last_chat';
  /** An empty token is also what 'the server has no auth' looks like. */
  static readonly SIGNED_IN: string = 'signed_in';
  /** Login configuration, edited on the settings page: every known address. */
  static readonly SERVERS: string = 'server_list';
  /** Typed at the settings page; the session username in USERNAME is server-issued. */
  static readonly CONFIG_USER: string = 'config_username';
  static readonly PASSWORD: string = 'auth_password';
  static readonly SCAN_PORT: string = 'scan_port';
}

export class Prefs {
  private static db?: preferences.Preferences;

  private static async open(ctx: common.Context): Promise<preferences.Preferences> {
    if (Prefs.db === undefined) {
      Prefs.db = await preferences.getPreferences(ctx, STORE_NAME);
    }
    return Prefs.db;
  }

  static async read(ctx: common.Context, key: string, fallback: string): Promise<string> {
    const db = await Prefs.open(ctx);
    return (await db.get(key, fallback)) as string;
  }

  static async write(ctx: common.Context, key: string, value: string): Promise<void> {
    const db = await Prefs.open(ctx);
    await db.put(key, value);
    await db.flush();
  }

  static async erase(ctx: common.Context, key: string): Promise<void> {
    const db = await Prefs.open(ctx);
    await db.delete(key);
    await db.flush();
  }
}

function isFilled(value: string | undefined): boolean {
  return value !== undefined && typeof value === 'string' && value.length > 0;
}

/** The port a fresh install sweeps; matches QwenPaw's own console default. */
const DEFAULT_SCAN_PORT: number = 8088;

/**
 * Read back the saved address list. Anything that is not an array of non-empty
 * strings collapses to an empty list, so a half-written entry cannot take the
 * login page down.
 */
function toStringList(raw: string): string[] {
  if (raw.length === 0) {
    return [];
  }
  try {
    const parsed = JSON.parse(raw) as string[];
    const out: string[] = [];
    for (const item of parsed) {
      if (isFilled(item) && out.indexOf(item) < 0) {
        out.push(item);
      }
    }
    return out;
  } catch (e) {
    return [];
  }
}

export class Settings {
  static async serverUrl(ctx: common.Context): Promise<string> {
    return Prefs.read(ctx, Key.SERVER, '');
  }

  static async token(ctx: common.Context): Promise<string> {
    return Prefs.read(ctx, Key.TOKEN, '');
  }

  static async username(ctx: common.Context): Promise<string> {
    return Prefs.read(ctx, Key.USERNAME, '');
  }

  static async agentId(ctx: common.Context): Promise<string> {
    const v = await Prefs.read(ctx, Key.AGENT, 'default');
    return isFilled(v) ? v : 'default';
  }

  static async themeMode(ctx: common.Context): Promise<string> {
    return Prefs.read(ctx, Key.THEME_MODE, 'system');
  }

  static async saveThemeMode(ctx: common.Context, mode: string): Promise<void> {
    await Prefs.write(ctx, Key.THEME_MODE, mode);
  }

  // ---------- login configuration ----------
  //
  // These keys are what the settings page edits and what the login page signs in
  // with. They belong to the device, not to a session: signing out keeps them,
  // exactly like the server address. The password sits in the app-private
  // preferences store next to the bearer token, so it is no more exposed than the
  // session already was.

  static async servers(ctx: common.Context): Promise<string[]> {
    return toStringList(await Prefs.read(ctx, Key.SERVERS, ''));
  }

  static async saveServers(ctx: common.Context, urls: string[]): Promise<void> {
    await Prefs.write(ctx, Key.SERVERS, JSON.stringify(urls));
  }

  static async scanPort(ctx: common.Context): Promise<number> {
    const port = parseInt(await Prefs.read(ctx, Key.SCAN_PORT, ''), 10);
    // A corrupt value fails the range test, so it needs no separate NaN check.
    return port >= 1 && port <= 65535 ? port : DEFAULT_SCAN_PORT;
  }

  static async saveScanPort(ctx: common.Context, port: number): Promise<void> {
    await Prefs.write(ctx, Key.SCAN_PORT, `${port}`);
  }

  static async password(ctx: common.Context): Promise<string> {
    return Prefs.read(ctx, Key.PASSWORD, '');
  }

  static async configUsername(ctx: common.Context): Promise<string> {
    return Prefs.read(ctx, Key.CONFIG_USER, '');
  }

  static async saveConfigUsername(ctx: common.Context, value: string): Promise<void> {
    await Prefs.write(ctx, Key.CONFIG_USER, value);
  }

  static async savePassword(ctx: common.Context, value: string): Promise<void> {
    await Prefs.write(ctx, Key.PASSWORD, value);
  }

  /** Everything a session needs; empty token means 'server has no auth'. */
  static async saveSession(ctx: common.Context, serverUrl: string, token: string,
    username: string): Promise<void> {
    await Prefs.write(ctx, Key.SERVER, serverUrl);
    await Prefs.write(ctx, Key.TOKEN, token);
    await Prefs.write(ctx, Key.USERNAME, username);
    await Prefs.write(ctx, Key.SIGNED_IN, '1');
  }

  static async signedIn(ctx: common.Context): Promise<boolean> {
    return (await Prefs.read(ctx, Key.SIGNED_IN, '')) === '1';
  }

  static async saveAgentId(ctx: common.Context, agentId: string): Promise<void> {
    await Prefs.write(ctx, Key.AGENT, agentId);
  }

  static async saveLastChat(ctx: common.Context, ref: ChatRef): Promise<void> {
    await Prefs.write(ctx, Key.LAST_CHAT, JSON.stringify(ref));
  }

  static async clearLastChat(ctx: common.Context): Promise<void> {
    await Prefs.erase(ctx, Key.LAST_CHAT);
  }

  static async loadLastChat(ctx: common.Context): Promise<ChatRef | undefined> {
    const raw = await Prefs.read(ctx, Key.LAST_CHAT, '');
    if (!isFilled(raw)) {
      return undefined;
    }
    try {
      const parsed = JSON.parse(raw) as ChatRef;
      return isFilled(parsed.chatId) ? parsed : undefined;
    } catch (e) {
      return undefined;
    }
  }

  /** Sign out keeps the server address and drops credentials and history pointer. */
  static async clearSession(ctx: common.Context): Promise<void> {
    await Prefs.erase(ctx, Key.TOKEN);
    await Prefs.erase(ctx, Key.USERNAME);
    await Prefs.erase(ctx, Key.LAST_CHAT);
    await Prefs.erase(ctx, Key.SIGNED_IN);
  }
}
