/**
 * Turns a message's media reference into something a component can draw or play.
 *
 * v1 appended the bearer token to the preview URL. That put the credential into
 * every HTTP request line, proxy log and screenshot of the chat. Here the bytes
 * come through ApiClient.fetchBytes() with the Authorization header and are
 * decoded to a PixelMap; http(s) URLs pass through as-is, and history's inline
 * `data:` URIs are decoded locally because Image cannot draw them. Video and
 * audio cannot be handed a PixelMap or a header, so they go through MediaCache.
 */
import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { ApiClient } from '../net/ApiClient';
import { Parts } from '../model/Parts';
import { CleanupFile } from '../model/Cleanup';
import { Failure } from '../core/Failure';
import { Log } from '../core/Log';
import { MediaCache } from './MediaCache';

/** Bounded so a long chat cannot grow the native bitmap pool without limit. */
const MAX_CACHED: number = 18;

/** Either a directly usable URL or a decoded PixelMap; never both. */
export class MediaValue {
  url: string = '';
  map?: image.PixelMap;
  /** Fetch or decode failed: the bubble shows its own placeholder copy. */
  failed: boolean = false;

  static ofUrl(url: string): MediaValue {
    const v = new MediaValue();
    v.url = url;
    return v;
  }

  static ofMap(map: image.PixelMap): MediaValue {
    const v = new MediaValue();
    v.map = map;
    return v;
  }

  static failure(): MediaValue {
    const v = new MediaValue();
    v.failed = true;
    return v;
  }

  isEmpty(): boolean {
    return this.url.length === 0 && this.map === undefined;
  }
}

export class MediaLoader {
  private readonly client: ApiClient;
  private readonly cache: MediaCache;
  private readonly pixmaps: Map<string, image.PixelMap> = new Map();
  /** Two bubbles for the same image must produce one request, not two. */
  private readonly inflight: Map<string, Promise<image.PixelMap>> = new Map();

  constructor(client: ApiClient) {
    this.client = client;
    this.cache = new MediaCache(client);
  }

  /** The sandbox directory clips are written to; set once from the ability. */
  bind(ctx: common.Context): void {
    this.cache.bind(ctx);
  }

  /** data: URIs and http(s) URLs need no credential, so skip the byte path. */
  static isDirect(ref: string): boolean {
    return Parts.isDirectUrl(ref);
  }

  /** Resolve a stored path or inline reference; never rejects. */
  async load(ref: string): Promise<MediaValue> {
    if (ref.length === 0) {
      return new MediaValue();
    }
    if (ref.startsWith('data:')) {
      return this.decodeInline(ref);
    }
    if (MediaLoader.isDirect(ref)) {
      return MediaValue.ofUrl(ref);
    }
    if (!this.client.isConfigured()) {
      return MediaValue.failure();
    }
    try {
      return await this.resolve(ref);
    } catch (e) {
      Log.warn(`[Media] 图片加载失败 ${this.cache.nameOf(ref)}: ${Failure.from(e as Object).message}`);
      return MediaValue.failure();
    }
  }

  /**
   * A Video component's src: a direct URL, or the sandbox file the bytes were
   * written to. The header-authenticated fetch is the only way past an
   * authenticated server, and the player cannot carry one.
   */
  async videoSource(ref: string): Promise<MediaValue> {
    if (ref.length === 0) {
      return new MediaValue();
    }
    if (MediaLoader.isDirect(ref)) {
      return MediaValue.ofUrl(ref);
    }
    const uri = await this.cache.uriFor(ref);
    return uri.length === 0 ? MediaValue.failure() : MediaValue.ofUrl(uri);
  }

  /**
   * An AVPlayer's source: the URL itself, or the sandbox path the caller opens as
   * `fd://`. Empty means the clip cannot be played here.
   */
  async audioSource(ref: string): Promise<string> {
    if (ref.length === 0 || ref.startsWith('data:')) {
      return '';
    }
    if (MediaLoader.isDirect(ref)) {
      return ref;
    }
    return await this.cache.pathFor(ref);
  }

  /** Bytes held in the sandbox cache, for the storage line on the home page. */
  cacheBytes(): number {
    return this.cache.sizeBytes();
  }

  cacheFiles(): number {
    return this.cache.fileCount();
  }

  /** Every local copy, newest first, for the cleanup page. */
  files(): CleanupFile[] {
    return this.cache.files();
  }

  /** Throw away the named copies; returns how many actually went. */
  dropFiles(names: string[]): number {
    return this.cache.dropFiles(names);
  }

  /** One asset's local copy: how many bytes are on the phone, and dropping them. */
  sizeOfRef(ref: string): number {
    return this.cache.sizeOfRef(ref);
  }

  /**
   * The on-disk name one reference would land under. The cleanup page recovers
   * display names by hashing the refs the open stores still hold and matching
   * them against what `files()` listed.
   */
  nameOf(ref: string): string {
    return this.cache.nameOf(ref);
  }

  dropRef(ref: string): boolean {
    return this.cache.drop(ref);
  }

  /** Sandbox path for one asset, fetching it first. Export and sharing read bytes. */
  async localPath(ref: string): Promise<string> {
    return await this.cache.pathFor(ref);
  }

  /** Logged-out or agent-switch cleanup: drop decoded bitmaps, keep nothing stale. */
  clear(): void {
    this.pixmaps.clear();
    this.inflight.clear();
  }

  private async resolve(ref: string): Promise<MediaValue> {
    const hit = this.pixmaps.get(ref);
    if (hit !== undefined) {
      this.remember(ref, hit);
      return MediaValue.ofMap(hit);
    }
    const pending = this.inflight.get(ref);
    if (pending !== undefined) {
      return MediaValue.ofMap(await pending);
    }
    const job = this.fetch(ref);
    this.inflight.set(ref, job);
    try {
      return MediaValue.ofMap(await job);
    } finally {
      this.inflight.delete(ref);
    }
  }

  private async fetch(ref: string): Promise<image.PixelMap> {
    const bytes = await this.client.fetchBytes(ref);
    return this.decodeBytes(bytes, ref);
  }

  /**
   * History inlines images as `data:` URIs. Image can draw a PixelMap or a URL but
   * not those, so the payload is decoded here and never leaves the device.
   */
  private async decodeInline(ref: string): Promise<MediaValue> {
    const hit = this.pixmaps.get(ref);
    if (hit !== undefined) {
      return MediaValue.ofMap(hit);
    }
    const comma = ref.indexOf(',');
    if (comma < 0) {
      return MediaValue.failure();
    }
    try {
      const packed = await new util.Base64Helper().decode(ref.substring(comma + 1));
      // createImageSource() takes an ArrayBuffer, and the decoded view may sit on
      // a shared buffer, so the bytes are copied into one of their own.
      const buffer = new ArrayBuffer(packed.length);
      new Uint8Array(buffer).set(packed);
      return MediaValue.ofMap(await this.decodeBytes(buffer, ref));
    } catch (e) {
      Log.warn(`[Media] 内嵌图片解码失败: ${Failure.from(e as Object).message}`);
      return MediaValue.failure();
    }
  }

  private async decodeBytes(bytes: ArrayBuffer, ref: string): Promise<image.PixelMap> {
    const source = image.createImageSource(bytes);
    try {
      const map = await source.createPixelMap();
      this.remember(ref, map);
      return map;
    } finally {
      source.release();
    }
  }

  /**
   * Insertion order is the recency order: re-inserting moves a hit to the back,
   * so the oldest entry is always the first key. An evicted PixelMap is only
   * dropped from the map, not released, because a bubble may still be drawing it.
   */
  private remember(ref: string, map: image.PixelMap): void {
    this.pixmaps.delete(ref);
    this.pixmaps.set(ref, map);
    if (this.pixmaps.size <= MAX_CACHED) {
      return;
    }
    for (const stale of this.pixmaps.keys()) {
      this.pixmaps.delete(stale);
      break;
    }
  }
}
