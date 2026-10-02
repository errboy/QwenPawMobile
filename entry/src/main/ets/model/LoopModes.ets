/**
 * Loop-mode slash prefix.
 *
 * No endpoint sets a chat's loop mode: the mode travels as a `/<slash_command>`
 * prefix on the message text, and only while the session is idle. Prefixing a
 * message sent mid-run would queue a second command behind the live one.
 */
import { LoopModeInfo } from './Dtos';
import { Parts } from './Parts';

/** The phone's own UI language, used to read the server's per-mode translations. */
const LOOP_LANGUAGE: string = 'zh-CN';

export class LoopModes {
  /** Built-ins report `goal`; a plugin mode can already arrive as `/mission`. */
  static command(slash: string): string {
    const raw = slash.trim();
    if (raw.length === 0) {
      return '';
    }
    return raw.startsWith('/') ? raw : `/${raw}`;
  }

  private static firstToken(text: string): string {
    const trimmed = text.trimStart();
    const end = trimmed.search(/\s/);
    return end < 0 ? trimmed : trimmed.substring(0, end);
  }

  /** The mode a hand-typed `/command` selects, if any. */
  static findByCommand(modes: LoopModeInfo[], text: string): LoopModeInfo | undefined {
    const token = LoopModes.firstToken(text).toLowerCase();
    if (!token.startsWith('/')) {
      return undefined;
    }
    for (const m of modes) {
      if (LoopModes.command(Parts.str(m.slash_command)).toLowerCase() === token) {
        return m;
      }
    }
    return undefined;
  }

  /**
   * Compose the wire text for one send. `selectedSlash` is what the user's picker
   * holds, so a stale catalog cannot silently drop the mode they chose.
   */
  static apply(text: string, modes: LoopModeInfo[], selectedSlash: string, idle: boolean): string {
    if (!idle || text.trim().length === 0) {
      return text;
    }
    const manual = LoopModes.findByCommand(modes, text);
    if (manual === undefined && text.trimStart().startsWith('/')) {
      // Another slash command: the server's registry dispatches it, not a loop mode.
      return text;
    }
    const prefix = LoopModes.command(
      manual === undefined ? selectedSlash : Parts.str(manual.slash_command));
    if (prefix.length === 0 || LoopModes.firstToken(text).toLowerCase() === prefix.toLowerCase()) {
      return text;
    }
    return `${prefix} ${text}`;
  }

  /** Modes the picker offers: the default mode carries no command and stays hidden. */
  static selectable(modes: LoopModeInfo[]): LoopModeInfo[] {
    const out: LoopModeInfo[] = [];
    for (const m of modes) {
      if (LoopModes.command(Parts.str(m.slash_command)).length > 0) {
        out.push(m);
      }
    }
    return out;
  }

  /**
   * Upstream ships `name` in English and the translated strings in `name_i18n`;
   * the phone's UI is Chinese, so it reads the same entry the PC's zh locale picks.
   * The server answers these two fields with an explicit null, which JSON.parse
   * keeps as null rather than undefined, so the guard cannot stop at undefined.
   */
  static localized(map: Record<string, string> | undefined | null, fallback: string): string {
    if (map === undefined || map === null) {
      return fallback;
    }
    const zh = map[LOOP_LANGUAGE];
    const value = Parts.str(zh);
    return value.length > 0 ? value : fallback;
  }

  static displayName(mode: LoopModeInfo): string {
    return LoopModes.localized(mode.name_i18n, Parts.str(mode.name));
  }

  static displayDescription(mode: LoopModeInfo): string {
    return LoopModes.localized(mode.description_i18n, Parts.str(mode.description));
  }
}
