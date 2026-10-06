/**
 * Media bytes in the app sandbox, so a Video or an AVPlayer can open them.
 *
 * Neither component can attach an Authorization header, and this app never puts
 * the bearer token into a URL, so the only way a streamed video or voice note
 * plays is: fetch with the header through ApiClient.fetchBytes(), write once,
 * then read the local file. A direct http(s) URL skips all of it.
 */
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { ApiClient } from '../net/ApiClient';
import { CleanupFile } from '../model/Cleanup';
import { Failure } from '../core/Failure';
import { Log } from '../core/Log';

/** Subdirectory of cacheDir; the system may reclaim it, which is all a cache is for. */
const DIR_NAME: string = 'media';

/** Refs with no usable container suffix still need a name the demuxer will accept. */
const FALLBACK_SUFFIX: string = 'bin';

/** A recorded take is written here, in the cache root, and stays after it is sent. */
const RECORD_PREFIX: string = 'voice-';

/** The buckets the cleanup page lists, named by container rather than by MIME. */
const VIDEO_EXT: string[] = ['mp4', 'mov', 'mkv', 'webm', 'avi'];
const AUDIO_EXT: string[] = ['m4a', 'mp3', 'wav', 'aac', 'ogg', 'flac', 'amr'];
const DOC_EXT: string[] = ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt',
  'md', 'csv', 'json'];

/** FNV-1a: the same bytes asked for twice name the same file. */
function digest(ref: string): string {
  let h: number = 0x811c9dc5;
  for (let i = 0; i < ref.length; i++) {
    h ^= ref.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return (h >>> 0).toString(16);
}

/**
 * Container suffix, kept because both players choose a demuxer from it. Taken
 * from the stored path itself, so a file the server names clip.mp4 stays clip.mp4
 * on disk even though the file name is hashed away.
 */
function suffixOf(ref: string): string {
  const clean = ref.split('?')[0].split('#')[0];
  const slash = clean.lastIndexOf('/');
  const name = slash >= 0 ? clean.substring(slash + 1) : clean;
  const dot = name.lastIndexOf('.');
  if (dot < 0 || name.length - dot > 6) {
    return FALLBACK_SUFFIX;
  }
  const ext = name.substring(dot + 1).toLowerCase();
  return /^[a-z0-9]+$/.test(ext) ? ext : FALLBACK_SUFFIX;
}

export class MediaCache {
  private readonly client: ApiClient;
  /** Empty until bind() names the sandbox directory; every call then no-ops. */
  private dir: string = '';
  /** The cache root, where a recorded take is written beside this app's own cache. */
  private root: string = '';
  /** Two bubbles for one clip must produce one download, not two. */
  private readonly inflight: Map<string, Promise<string>> = new Map();

  constructor(client: ApiClient) {
    this.client = client;
  }

  bind(ctx: common.Context): void {
    this.root = ctx.cacheDir;
    this.dir = `${ctx.cacheDir}/${DIR_NAME}`;
  }

  /** Absolute sandbox path, downloaded first when it is not cached yet; '' on failure. */
  async pathFor(ref: string): Promise<string> {
    if (this.dir.length === 0 || ref.length === 0 || !this.client.isConfigured()) {
      return '';
    }
    const path = `${this.dir}/${this.nameOf(ref)}`;
    if (MediaCache.present(path)) {
      return path;
    }
    const pending = this.inflight.get(ref);
    if (pending !== undefined) {
      return await pending;
    }
    const job = this.download(ref, path);
    this.inflight.set(ref, job);
    try {
      return await job;
    } finally {
      this.inflight.delete(ref);
    }
  }

  /** A Video component reads the sandbox through a file:// URI. */
  async uriFor(ref: string): Promise<string> {
    const path = await this.pathFor(ref);
    return path.length === 0 ? '' : `file://${path}`;
  }

  /**
   * File name for one reference. The server's origin is hashed in with the path,
   * because two desktops can carry the same stored path and hold different bytes
   * under it; without that the second one would read the first one's clip.
   *
   * This is also what the failure logs name an asset by. The reference itself is
   * the desktop's own absolute path (`C:\Users\…\media\x.jpg`), and a warning line
   * is something users are asked to paste into a public issue, where their account
   * name has no business appearing.
   */
  nameOf(ref: string): string {
    return `${digest(`${this.client.serverUrl}|${ref}`)}.${suffixOf(ref)}`;
  }

  /** Local path for a ref that is already on the phone; '' when it never landed. */
  private cachedPath(ref: string): string {
    if (this.dir.length === 0 || ref.length === 0) {
      return '';
    }
    const path = `${this.dir}/${this.nameOf(ref)}`;
    return MediaCache.present(path) ? path : '';
  }

  /** Bytes this one ref holds locally; 0 when the asset lives only on the server. */
  sizeOfRef(ref: string): number {
    const path = this.cachedPath(ref);
    return path.length === 0 ? 0 : MediaCache.sizeOf(path);
  }

  /**
   * Throw away one local copy. The server keeps its own, so this is a cache miss
   * the next time the asset opens — not a deletion the user can lose anything to.
   */
  drop(ref: string): boolean {
    const path = this.cachedPath(ref);
    if (path.length === 0) {
      return false;
    }
    try {
      fs.unlinkSync(path);
      return true;
    } catch (e) {
      Log.warn(`[Media] 本机副本未能删除 ${this.nameOf(ref)}`);
      return false;
    }
  }

  /**
   * Total bytes held, for the storage line the user clears by hand. Includes the
   * recorded takes, which sit outside the media directory and would otherwise go
   * uncounted on a page that promises to say what the phone is holding.
   */
  sizeBytes(): number {
    let bytes: number = 0;
    for (const f of this.files()) {
      bytes += f.bytes;
    }
    return bytes;
  }

  /** Cached files counted, so the cleanup page can say how many go. */
  fileCount(): number {
    return this.files().length;
  }

  /**
   * Every local copy, newest first — the one read the cleanup page is built from,
   * so its category counts and its per-file list cannot disagree.
   */
  files(): CleanupFile[] {
    const out: CleanupFile[] = [];
    for (const name of MediaCache.listing(this.dir)) {
      MediaCache.read(out, this.dir, name, MediaCache.suffixBucket(name));
    }
    for (const name of MediaCache.listing(this.root)) {
      if (MediaCache.isRecord(name)) {
        MediaCache.read(out, this.root, name, 'record');
      }
    }
    out.sort((a: CleanupFile, b: CleanupFile): number => b.modified - a.modified);
    return out;
  }

  private static read(out: CleanupFile[], dir: string, name: string, kind: string): void {
    try {
      const stat = fs.statSync(`${dir}/${name}`);
      const file = new CleanupFile();
      file.name = name;
      file.path = `${dir}/${name}`;
      file.kind = kind;
      file.bytes = stat.size;
      file.modified = stat.mtime * 1000;
      out.push(file);
    } catch (e) {
      // The system reclaimed it between the listing and the stat. It is not a copy
      // the page can delete, so it is not a row on it either.
    }
  }

  /**
   * Throw away the named local copies and report how many actually went. Only the
   * two cache directories are consulted, and a name carrying anything but cache
   * file characters is refused: the page hands back what files() listed, and
   * nothing outside the cache should be reachable from here.
   */
  dropFiles(names: string[]): number {
    if (this.dir.length === 0) {
      return 0;
    }
    let gone: number = 0;
    for (const name of names) {
      if (!MediaCache.isFileName(name)) {
        Log.warn(`[Media] 缓存文件名不合规矩，未删 ${name}`);
        continue;
      }
      const cached = `${this.dir}/${name}`;
      const recorded = `${this.root}/${name}`;
      if (MediaCache.present(cached)) {
        if (MediaCache.unlink(cached, name)) {
          gone += 1;
        }
      } else if (MediaCache.present(recorded)) {
        if (MediaCache.unlink(recorded, name)) {
          gone += 1;
        }
      }
    }
    return gone;
  }

  private static isFileName(name: string): boolean {
    return /^[A-Za-z0-9._-]+$/.test(name) && name !== '.' && name !== '..';
  }

  private static suffixBucket(name: string): string {
    const dot = name.lastIndexOf('.');
    if (dot < 0) {
      return 'other';
    }
    const ext = name.substring(dot + 1).toLowerCase();
    if (VIDEO_EXT.indexOf(ext) >= 0) {
      return 'video';
    }
    if (AUDIO_EXT.indexOf(ext) >= 0) {
      return 'audio';
    }
    if (DOC_EXT.indexOf(ext) >= 0) {
      return 'doc';
    }
    return 'other';
  }

  private static isRecord(name: string): boolean {
    return name.startsWith(RECORD_PREFIX) && name.endsWith('.m4a');
  }

  /**
   * False means the bytes are still there — a player that holds the file open
   * refuses to let it go, which is correct: nothing is re-fetched wrongly, because
   * pathFor() re-checks existence on every call.
   */
  private static unlink(path: string, name: string): boolean {
    try {
      fs.unlinkSync(path);
      return true;
    } catch (e) {
      Log.warn(`[Media] 缓存文件未能删除 ${name}`);
      return false;
    }
  }

  /**
   * Write to a temporary name and move it into place only once every byte arrived.
   * A download that dies midway used to leave a truncated file under the final
   * name, and `present()` then read it as a cache hit forever: a black video, an
   * unplayable voice note, and 保存 exporting a file nobody can open.
   */
  private async download(ref: string, path: string): Promise<string> {
    const part = `${path}.part`;
    try {
      const bytes = await this.client.fetchBytes(ref);
      MediaCache.makeDir(this.dir);
      const file = fs.openSync(part,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, bytes);
      } finally {
        fs.closeSync(file);
      }
      fs.renameSync(part, path);
      return path;
    } catch (e) {
      // The half-file is not a cache entry, so it goes with the failure it came from.
      // unlink() is used because a cleanup that throws would turn one failure into two.
      if (MediaCache.present(part)) {
        MediaCache.unlink(part, part);
      }
      Log.warn(`[Media] 缓存写入失败 ${this.nameOf(ref)}: ${Failure.from(e as Object).message}`);
      return '';
    }
  }

  private static present(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch (e) {
      return false;
    }
  }

  private static sizeOf(path: string): number {
    try {
      return fs.statSync(path).size;
    } catch (e) {
      return 0;
    }
  }

  private static listing(dir: string): string[] {
    if (dir.length === 0) {
      return [];
    }
    try {
      return fs.listFileSync(dir);
    } catch (e) {
      // No directory yet means nothing was ever cached, not that cleanup failed.
      return [];
    }
  }

  private static makeDir(dir: string): void {
    try {
      fs.mkdirSync(dir);
    } catch (e) {
      // Cache dir is created by the system, so the only real case here is 'exists'.
    }
  }
}
