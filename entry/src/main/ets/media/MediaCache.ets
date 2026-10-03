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
import { Failure } from '../core/Failure';
import { Log } from '../core/Log';

/** Subdirectory of cacheDir; the system may reclaim it, which is all a cache is for. */
const DIR_NAME: string = 'media';

/** Refs with no usable container suffix still need a name the demuxer will accept. */
const FALLBACK_SUFFIX: string = 'bin';

/** FNV-1a over the reference: the same stored path always names the same file. */
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
  /** Two bubbles for one clip must produce one download, not two. */
  private readonly inflight: Map<string, Promise<string>> = new Map();

  constructor(client: ApiClient) {
    this.client = client;
  }

  bind(ctx: common.Context): void {
    this.dir = `${ctx.cacheDir}/${DIR_NAME}`;
  }

  /** Absolute sandbox path, downloaded first when it is not cached yet; '' on failure. */
  async pathFor(ref: string): Promise<string> {
    if (this.dir.length === 0 || ref.length === 0 || !this.client.isConfigured()) {
      return '';
    }
    const path = `${this.dir}/${digest(ref)}.${suffixOf(ref)}`;
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

  /** Total bytes held, for the storage line the user clears by hand. */
  sizeBytes(): number {
    let total: number = 0;
    for (const name of MediaCache.listing(this.dir)) {
      const size = MediaCache.sizeOf(`${this.dir}/${name}`);
      if (size > 0) {
        total += size;
      }
    }
    return total;
  }

  /**
   * Delete every cached clip. A file some player still holds open refuses to go;
   * that is correct — the next clear gets it, and nothing is re-fetched wrongly
   * because pathFor() re-checks existence on every call.
   */
  clear(): void {
    if (this.dir.length === 0) {
      return;
    }
    for (const name of MediaCache.listing(this.dir)) {
      try {
        fs.unlinkSync(`${this.dir}/${name}`);
      } catch (e) {
        Log.warn(`[Media] 缓存文件未能删除 ${name}`);
      }
    }
    this.inflight.clear();
  }

  private async download(ref: string, path: string): Promise<string> {
    try {
      const bytes = await this.client.fetchBytes(ref);
      MediaCache.makeDir(this.dir);
      const file = fs.openSync(path,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, bytes);
      } finally {
        fs.closeSync(file);
      }
      return path;
    } catch (e) {
      Log.warn(`[Media] 缓存写入失败 ${ref}: ${Failure.from(e as Object).message}`);
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
