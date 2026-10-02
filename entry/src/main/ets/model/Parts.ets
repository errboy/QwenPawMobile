/**
 * Reading helpers for the heterogeneous `content` parts the backend sends.
 * Declared string fields can arrive as objects or arrays (the server runs
 * extra="allow"), so every read funnels through asText().
 * Display copy is injected as templates to keep this module UI-free and testable.
 */
import { ContentPart, DataPayload } from './Content';
import { ContentType } from '../core/Wire';

/** A file part's URL and display name, extracted from content parts. */
export class FileRef {
  url: string = '';
  name: string = '';
}

export class PartTemplates {
  image: string = '[图片]';
  video: string = '[视频]';
  audio: string = '[语音]';
  fileTemplate: string = '[文件: %s]';
  unknownTool: string = '工具';
  /** Appended to a tool card that carries the result rather than the request. */
  outputSuffix: string = ' · 输出';
  /** Tool text longer than this is elided; the phone has no scroll room for it. */
  toolClipChars: number = 400;
}

export const DEFAULT_TEMPLATES: PartTemplates = new PartTemplates();

export class Parts {
  /** Flattens a message's content into display text, labelling non-text parts. */
  static displayText(parts: ContentPart[] | undefined, t: PartTemplates): string {
    if (parts === undefined) {
      return '';
    }
    let out = '';
    for (const p of parts) {
      if (p.type === ContentType.TEXT) {
        out += Parts.str(p.text);
      } else if (p.type === ContentType.IMAGE) {
        out += t.image;
      } else if (p.type === ContentType.VIDEO) {
        out += t.video;
      } else if (p.type === ContentType.AUDIO) {
        out += t.audio;
      } else if (p.type === ContentType.FILE) {
        out += t.fileTemplate.replace('%s', Parts.fileName(p));
      }
    }
    return out;
  }

  static fileName(part: ContentPart): string {
    const named = Parts.str(part.filename);
    return named.length > 0 ? named : Parts.str(part.file_name);
  }

  static firstImage(parts: ContentPart[] | undefined): string {
    if (parts === undefined) {
      return '';
    }
    for (const p of parts) {
      const url = Parts.str(p.image_url);
      if (p.type === ContentType.IMAGE && url.length > 0) {
        return url;
      }
    }
    return '';
  }

  static firstVideo(parts: ContentPart[] | undefined): string {
    if (parts === undefined) {
      return '';
    }
    for (const p of parts) {
      const url = Parts.str(p.video_url);
      if (p.type === ContentType.VIDEO && url.length > 0) {
        return url;
      }
    }
    return '';
  }

  /** Audio parts carry their stored path or base64 payload in `data`. */
  static firstAudio(parts: ContentPart[] | undefined): string {
    if (parts === undefined) {
      return '';
    }
    for (const p of parts) {
      if (p.type === ContentType.AUDIO && typeof p.data === 'string') {
        const url = Parts.str(p.data as string);
        if (url.length > 0) {
          return url;
        }
      }
    }
    return '';
  }

  static firstFile(parts: ContentPart[] | undefined): FileRef | undefined {
    if (parts === undefined) {
      return undefined;
    }
    for (const p of parts) {
      if (p.type !== ContentType.FILE) {
        continue;
      }
      const url = Parts.str(p.file_url);
      const name = Parts.fileName(p);
      if (url.length > 0 || name.length > 0) {
        const ref = new FileRef();
        ref.url = url;
        ref.name = name;
        return ref;
      }
    }
    return undefined;
  }

  static firstData(parts: ContentPart[] | undefined): DataPayload | undefined {
    if (parts === undefined) {
      return undefined;
    }
    for (const p of parts) {
      if (p.type === ContentType.DATA && p.data !== undefined) {
        return p.data;
      }
    }
    return undefined;
  }

  static toolName(data: DataPayload | undefined, t: PartTemplates): string {
    const name = data === undefined ? '' : Parts.str(data.name);
    return name.length > 0 ? name : t.unknownTool;
  }

  /**
   * The backend serialises optional string fields as explicit nulls, and JSON.parse
   * keeps those as null, so `!== undefined` alone still dereferences null. Every
   * wire string read funnels through this.
   */
  static str(value: string | undefined | null): string {
    return value === undefined || value === null ? '' : value;
  }

  static asText(value: Object | undefined): string {
    if (value === undefined || value === null) {
      return '';
    }
    if (typeof value === 'string') {
      return value as string;
    }
    return JSON.stringify(value);
  }

  static clip(text: string, max: number): string {
    return text.length > max ? `${text.substring(0, max)}…` : text;
  }

  /** History may hand back an inline data: URI, an absolute path, or a URL. */
  static isDirectUrl(value: string): boolean {
    return value.startsWith('data:') || value.startsWith('http://') || value.startsWith('https://');
  }
}
