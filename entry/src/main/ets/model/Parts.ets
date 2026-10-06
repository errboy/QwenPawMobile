/**
 * Reading helpers for the heterogeneous `content` parts the backend sends.
 * Declared string fields can arrive as objects or arrays (the server runs
 * extra="allow"), so every read funnels through asText().
 * Display copy is injected as templates to keep this module UI-free and testable.
 */
import { ContentPart, DataPayload, ToolOutputBlock } from './Content';
import { ContentType } from '../core/Wire';

/** A file part's URL and display name, extracted from content parts. */
export class FileRef {
  url: string = '';
  name: string = '';
}

/** One file a tool handed to the user, in the form this phone can show. */
export class SentFile {
  /** One of ContentType's media values, which picks the bubble it lands in. */
  kind: string = ContentType.FILE;
  /** Fetchable reference: a stored path with the `file:` scheme taken off, or a data: URI. */
  ref: string = '';
  name: string = '';
}

/** What the `data` parts of a message amount to once the tool's blocks are read. */
export class ToolMedia {
  files: SentFile[] = [];
  /** The tool's own words, with the file blocks taken out of the list. */
  text: string = '';
}

/**
 * Labels the transcript shows for non-text parts. ArkTS requires every field to
 * carry a value at construction, but the placeholders are deliberately empty:
 * a caller that forgets to inject one loses a label on screen, while a copy of
 * the real wording here is a second source of truth that silently drifts from
 * `l10n/Copy.ets`. Inject via `state/ChatStore.partTemplates()`.
 */
export class PartTemplates {
  image: string = '';
  video: string = '';
  audio: string = '';
  fileTemplate: string = '';
  unknownTool: string = '';
  /** Stands in for a file the tool inlined without naming. */
  inlineFile: string = '';
  /** Appended to a tool card that carries the result rather than the request. */
  outputSuffix: string = '';
  /** Tool text longer than this is elided; the phone has no scroll room for it. */
  toolClipChars: number = 400;
}

export class Parts {
  /**
   * Model-facing boilerplate the server embeds inside the user's own text part.
   * The desktop's renderer drops it as an unknown HTML tag, so nobody there ever
   * sees it; a `Text` component has no such rule and would show the user a tag
   * plus a paragraph about where their upload landed on another machine.
   */
  private static readonly REMINDER: RegExp = /<system-reminder>[\s\S]*?<\/system-reminder>\s*/g;

  /**
   * What a non-text part says about itself in the transcript. The optimistic echo
   * asks for the same string, so a bubble cannot rename its own attachment when
   * history comes back — '[语音]' before and '[语音]' after, not a local file name
   * that only exists on this phone.
   */
  static label(type: string, name: string, t: PartTemplates): string {
    if (type === ContentType.IMAGE) {
      return t.image;
    }
    if (type === ContentType.VIDEO) {
      return t.video;
    }
    if (type === ContentType.AUDIO) {
      return t.audio;
    }
    if (type === ContentType.FILE) {
      return t.fileTemplate.replace('%s', name);
    }
    return '';
  }

  /** Flattens a message's content into display text, labelling non-text parts. */
  static displayText(parts: ContentPart[] | undefined, t: PartTemplates): string {
    if (parts === undefined) {
      return '';
    }
    // One message can carry several text parts (the user's own words, then the
    // server's note about each attachment). Welding them into one line turns two
    // sentences into a third word, so they keep their separation as blocks.
    const blocks: string[] = [];
    for (const p of parts) {
      let piece = '';
      if (p.type === ContentType.TEXT) {
        piece = Parts.str(p.text).replace(Parts.REMINDER, '').trim();
      } else {
        piece = Parts.label(p.type, Parts.fileName(p), t);
      }
      if (piece.length > 0) {
        blocks.push(piece);
      }
    }
    return blocks.join('\n');
  }

  static fileName(part: ContentPart): string {
    const named = Parts.str(part.filename);
    return named.length > 0 ? named : Parts.str(part.file_name);
  }

  /**
   * The last segment of a name or path, on either slash style. The server names a
   * file out of its own filesystem, so what arrives here can be a whole Windows
   * path; shown raw it fills the bubble and buries the part the user recognises.
   */
  static leafOf(value: string): string {
    const flat = value.split('\\').join('/');
    const slash = flat.lastIndexOf('/');
    return slash >= 0 ? flat.substring(slash + 1) : flat;
  }

  /**
   * The last two segments of a path, keeping the separator it arrived with. The
   * asset panel shows where a file sits, not where on the PC's disk it sits: a full
   * `C:\Users\…\AppData\…\media\clip.mp4` names directories the user never chose,
   * and the parent folder is enough to tell two same-named files apart. A bare name
   * (no separator at all) comes back unchanged.
   */
  static shortPath(value: string): string {
    const slash = Math.max(value.lastIndexOf('\\'), value.lastIndexOf('/'));
    if (slash < 0) {
      return value;
    }
    const parent = Math.max(value.lastIndexOf('\\', slash - 1), value.lastIndexOf('/', slash - 1));
    return value.substring(parent + 1);
  }

  /**
   * Lowercased suffix of a file name, or '' when there is none to read. The tail is
   * capped at six characters so a name like `archive.2024` is treated as having no
   * extension rather than one called `.2024`.
   */
  static suffixOf(value: string): string {
    const clean = Parts.leafOf(value).split('?')[0].split('#')[0];
    const dot = clean.lastIndexOf('.');
    if (dot < 0 || clean.length - dot > 6) {
      return '';
    }
    return clean.substring(dot + 1).toLowerCase();
  }

  /**
   * Whether this phone can fetch a reference at all. The desktop's media tools
   * answer with `file:///…` URIs, which name a filesystem the phone cannot read:
   * the preview endpoint takes the **bare** absolute path the upload endpoint
   * returned, so a `file:`-prefixed ref fetches nothing. Left in, it becomes a
   * bubble that never loads and an asset row whose every action fails, while the
   * `📁` badge advertises assets the panel cannot deliver.
   *
   * Everything else passes, including the bare stored path (`C:\…\media\x.jpg`)
   * that `/api/console/upload` hands back — that one is the working contract.
   *
   * A `file:` ref is only unfetchable while it keeps its scheme, so the one route
   * that meets them — `toolMedia()` below — takes the scheme off first.
   */
  static reachable(ref: string): boolean {
    return ref.substring(0, 5).toLowerCase() !== 'file:';
  }

  /**
   * `file:///C:\dir\x.pdf` -> `C:\dir\x.pdf`. The desktop's own renderer does this
   * and asks the server for the bytes: the preview endpoint serves exactly that bare
   * absolute path, so stripping the scheme is the whole difference between a
   * reference this phone refuses and a file it can open. A path that arrives without
   * the scheme (history rewrites some of those) comes back unchanged.
   */
  static localRef(url: string): string {
    return url.substring(0, 7).toLowerCase() === 'file://' ? url.substring(7) : url;
  }

  /**
   * The files a tool handed over, and what the tool said about them.
   *
   * They do not ride the wire as `file` content parts. The desktop's send-file tool
   * answers with a block list serialised into the tool output's `output` **string**,
   * one `data` block per file, each naming a path on the PC or inlining its bytes —
   * so a turn that "sent twelve files" reaches the phone as twelve tool cards whose
   * body is JSON. Read the list here and both paths, the live stream and the
   * history, carry the same files.
   */
  static toolMedia(parts: ContentPart[] | undefined, t: PartTemplates): ToolMedia {
    const out = new ToolMedia();
    if (parts === undefined) {
      return out;
    }
    for (const p of parts) {
      if (p.type !== ContentType.DATA || p.data === undefined) {
        continue;
      }
      const blocks = Parts.outputBlocks(p.data.output);
      if (blocks.length === 0) {
        continue;
      }
      const words: string[] = [];
      for (const b of blocks) {
        if (b === undefined || b === null) {
          continue;
        }
        if (b.type === ContentType.TEXT) {
          const piece = Parts.str(b.text).trim();
          if (piece.length > 0) {
            words.push(piece);
          }
          continue;
        }
        if (b.type !== ContentType.DATA || b.source === undefined) {
          continue;
        }
        const src = b.source;
        const mime = Parts.str(src.media_type);
        const inline = Parts.str(src.type) === 'base64';
        const bytes = Parts.str(src.data);
        const ref = inline ? (bytes.length > 0 ? `data:${mime};base64,${bytes}` : '')
          : Parts.localRef(Parts.str(src.url));
        if (ref.length === 0) {
          continue;
        }
        const file = new SentFile();
        // The mime is the tool's own guess at what it sent, and it is the same one
        // an upload is typed by. A file whose mime says nothing (`application/
        // octet-stream` over a `.md`) is a document, which is the honest bubble.
        file.kind = ContentType.forMime(mime);
        file.ref = ref;
        // Naming is independent of the source type: real history carries unnamed url
        // blocks, unnamed inlined ones, and an inlined block that does have a name.
        // Only a url has a leaf to read off — base64's last segment is not a name.
        const named = Parts.str(b.name);
        file.name = named.length > 0 ? named : (inline ? t.inlineFile : Parts.leafOf(ref));
        out.files.push(file);
      }
      out.text = words.join('\n');
    }
    return out;
  }

  /** The block list inside a tool's `output`, or nothing when it is not one. */
  private static outputBlocks(value: Object | undefined): ToolOutputBlock[] {
    if (typeof value !== 'string') {
      return [];
    }
    const raw = (value as string).trim();
    if (!raw.startsWith('[')) {
      return [];
    }
    try {
      const parsed: Object = JSON.parse(raw) as Object;
      return Array.isArray(parsed) ? parsed as ToolOutputBlock[] : [];
    } catch (e) {
      // A tool whose answer is prose, or half a JSON document: the card keeps it raw.
      return [];
    }
  }

  static firstImage(parts: ContentPart[] | undefined): string {
    if (parts === undefined) {
      return '';
    }
    for (const p of parts) {
      const url = Parts.str(p.image_url);
      if (p.type === ContentType.IMAGE && url.length > 0 && Parts.reachable(url)) {
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
      if (p.type === ContentType.VIDEO && url.length > 0 && Parts.reachable(url)) {
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
        if (url.length > 0 && Parts.reachable(url)) {
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
        // The name survives even when the bytes are somewhere the phone cannot
        // reach: the transcript did carry a file, and hiding it would rewrite
        // what the user sent. Only the fetchable half of the reference goes.
        ref.url = Parts.reachable(url) ? url : '';
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

  /**
   * Bytes a `data:` URI carries, counted off its base64 body without decoding it.
   * Those bytes are already on this phone, inside the message — which is the whole
   * difference between telling the user a file waits on the PC and naming what they
   * can open right now, offline.
   */
  static inlineBytes(value: string): number {
    const comma = value.indexOf(',');
    if (comma < 0) {
      return 0;
    }
    const body = value.substring(comma + 1);
    const pad = body.endsWith('==') ? 2 : (body.endsWith('=') ? 1 : 0);
    return Math.floor((body.length - pad) * 3 / 4);
  }
}
