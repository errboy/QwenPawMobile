/**
 * Attachment picking and multipart upload to POST /api/console/upload.
 *
 * The picker URI is held until send time, so a user can queue several files and
 * still cancel cheaply. Upload streams the file through one reused chunk into a
 * single pre-sized body: v1 materialised the whole file and then copied it into
 * the multipart body, which cost twice the file in peak memory and had no cap.
 */
import { fileIo as fs, fileUri, picker, ReadOptions } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { util } from '@kit.ArkTS';
import { ApiClient } from '../net/ApiClient';
import { Attachment } from '../model/Attachment';
import { UploadResult } from '../model/Dtos';
import { Parts } from '../model/Parts';
import { ApiPath } from '../core/Wire';
import { Failure } from '../core/Failure';
import { Copy } from '../l10n/Copy';

/**
 * Files above this are rejected client-side. It is a memory guard, not a server
 * policy: the multipart body is materialised as one ArrayBuffer, and the server
 * itself imposes no cap unless QWENPAW_UPLOAD_MAX_SIZE_MB is set. 50MB is roughly
 * the shortest clip a phone camera produces, so video stays usable.
 */
const MAX_UPLOAD_BYTES: number = 50 * 1024 * 1024;
const MAX_UPLOAD_MB: number = MAX_UPLOAD_BYTES / (1024 * 1024);

/** Picker cap, matching the v1 behaviour. */
const MAX_PICK: number = 4;

/** Reused read buffer; bounds peak memory independently of the file size. */
const CHUNK_BYTES: number = 1024 * 1024;

/** One row of the extension table used to name a part's content type. */
class MimeRow {
  suffixes: string[] = [];
  mime: string = '';

  constructor(suffixes: string[], mime: string) {
    this.suffixes = suffixes;
    this.mime = mime;
  }
}

/**
 * Mirrors the content types a desktop browser reports for the same files, because
 * ChatApi.buildParts routes on the mime prefix: audio must come back as audio/* or
 * it is sent as a generic file instead of a voice note.
 */
const MIME_ROWS: MimeRow[] = [
  new MimeRow(['png'], 'image/png'),
  new MimeRow(['jpg', 'jpeg'], 'image/jpeg'),
  new MimeRow(['gif'], 'image/gif'),
  new MimeRow(['webp'], 'image/webp'),
  new MimeRow(['bmp'], 'image/bmp'),
  new MimeRow(['tif', 'tiff'], 'image/tiff'),
  new MimeRow(['heic'], 'image/heic'),
  new MimeRow(['svg'], 'image/svg+xml'),
  new MimeRow(['mp4', 'm4v'], 'video/mp4'),
  new MimeRow(['mov'], 'video/quicktime'),
  new MimeRow(['webm'], 'video/webm'),
  new MimeRow(['mkv'], 'video/x-matroska'),
  new MimeRow(['avi'], 'video/x-msvideo'),
  new MimeRow(['3gp'], 'video/3gpp'),
  new MimeRow(['mp3'], 'audio/mpeg'),
  new MimeRow(['wav'], 'audio/wav'),
  new MimeRow(['m4a', 'mp4a'], 'audio/mp4'),
  new MimeRow(['aac'], 'audio/aac'),
  new MimeRow(['flac'], 'audio/flac'),
  new MimeRow(['ogg', 'oga'], 'audio/ogg'),
  new MimeRow(['opus'], 'audio/opus'),
  new MimeRow(['amr'], 'audio/amr'),
  new MimeRow(['txt', 'md', 'log', 'json', 'csv'], 'text/plain'),
  new MimeRow(['pdf'], 'application/pdf'),
  new MimeRow(['doc'], 'application/msword'),
  new MimeRow(['docx'], 'application/vnd.openxmlformats-officedocument'
    + '.wordprocessingml.document'),
  new MimeRow(['xls'], 'application/vnd.ms-excel'),
  new MimeRow(['xlsx'], 'application/vnd.openxmlformats-officedocument'
    + '.spreadsheetml.sheet'),
  new MimeRow(['ppt'], 'application/vnd.ms-powerpoint'),
  new MimeRow(['pptx'], 'application/vnd.openxmlformats-officedocument'
    + '.presentationml.presentation'),
  new MimeRow(['zip'], 'application/zip')
];

/** What one picker run produced: readable files, and the reasons it dropped any. */
export class PickOutcome {
  picked: Attachment[] = [];
  /** Already worded for the notice line; empty when nothing was dropped. */
  skipped: string[] = [];
}

class MultipartBody {
  boundary: string = '';
  bytes: ArrayBuffer = new ArrayBuffer(0);
}

export class UploadApi {
  private readonly client: ApiClient;
  private seq: number = 0;

  constructor(client: ApiClient) {
    this.client = client;
  }

  static mimeFromName(name: string): string {
    const dot = name.lastIndexOf('.');
    const ext = dot >= 0 ? name.substring(dot + 1).toLowerCase() : '';
    for (const row of MIME_ROWS) {
      if (row.suffixes.includes(ext)) {
        return row.mime;
      }
    }
    return 'application/octet-stream';
  }

  /**
   * Display name for a picked URI. Media URIs keep the name in a query the path
   * split would throw away, so fileuri is asked first.
   */
  static displayName(uri: string): string {
    try {
      const named = new fileUri.FileUri(uri).name;
      if (named.length > 0) {
        return named;
      }
    } catch (e) {
      // A URI the framework cannot parse still has a last segment worth trying.
    }
    return UploadApi.nameFromUri(uri);
  }

  static nameFromUri(uri: string): string {
    let s = uri.split('?')[0];
    const slash = s.lastIndexOf('/');
    if (slash >= 0) {
      s = s.substring(slash + 1);
    }
    try {
      s = decodeURIComponent(s);
    } catch (e) {
      // Media URIs are not always percent-encoded; the raw segment still names it.
    }
    return s.length > 0 ? s : 'file';
  }

  /** Strip the characters that could break out of the Content-Disposition header. */
  static sanitizeFileName(name: string): string {
    let out = '';
    for (const ch of name) {
      if (ch !== '"' && ch !== '\r' && ch !== '\n' && ch !== '\\') {
        out += ch;
      }
    }
    return out.length > 0 ? out : 'file';
  }

  /**
   * System photo picker, images and videos (no permission required). The gallery
   * MIME type the SDK names IMAGE_VIDEO_TYPE covers that pair only, so audio stays
   * where it belongs.
   */
  async pickGallery(): Promise<PickOutcome> {
    const helper = new photoAccessHelper.PhotoViewPicker();
    const options = new photoAccessHelper.PhotoSelectOptions();
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_VIDEO_TYPE;
    options.maxSelectNumber = MAX_PICK;
    const result = await helper.select(options);
    return UploadApi.toOutcome(result.photoUris);
  }

  /** System file picker for documents and other files. */
  async pickFiles(): Promise<PickOutcome> {
    const p = new picker.DocumentViewPicker();
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = MAX_PICK;
    return UploadApi.toOutcome(await p.select(options));
  }

  /**
   * System audio picker. It lists the media library's audio only, and unlike the
   * document picker its options expose no suffix filter.
   */
  async pickAudio(): Promise<PickOutcome> {
    const p = new picker.AudioViewPicker();
    const options = new picker.AudioSelectOptions();
    options.maxSelectNumber = MAX_PICK;
    return UploadApi.toOutcome(await p.select(options));
  }

  /**
   * Drop what the phone cannot hold in memory while uploading, before the tray is
   * built. Checking here rather than at send time matters: a send that fails on the
   * second file would take the composed message and the whole tray with it.
   *
   * A size this module could not read is kept, not skipped — an unreadable URI is
   * the upload's own error to report, and guessing here would reject files the
   * picker had every right to hand over.
   */
  static toOutcome(uris: string[]): PickOutcome {
    const out = new PickOutcome();
    for (const uri of uris) {
      const name = UploadApi.displayName(uri);
      const size = UploadApi.sizeOf(uri);
      if (size > MAX_UPLOAD_BYTES) {
        out.skipped.push(Copy.fillN2(Copy.notice_file_too_large, name, MAX_UPLOAD_MB));
        continue;
      }
      const a = new Attachment();
      a.key = `att_${Date.now()}_${out.picked.length}`;
      a.uri = uri;
      a.name = name;
      a.mime = UploadApi.mimeFromName(name);
      out.picked.push(a);
    }
    return out;
  }

  /** Negative means this module could not stat it, which is not the same as empty. */
  private static sizeOf(uri: string): number {
    let file: fs.File | undefined = undefined;
    try {
      file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      return fs.statSync(file.fd).size;
    } catch (e) {
      return -1;
    } finally {
      if (file !== undefined) {
        fs.closeSync(file);
      }
    }
  }

  /** Upload one attachment; `url` in the result is the server-side stored path. */
  async upload(a: Attachment): Promise<UploadResult> {
    const body = this.compose(a);
    const raw = await this.client.uploadMultipart(ApiPath.CONSOLE_UPLOAD, body.boundary, body.bytes);
    const parsed = JSON.parse(raw) as UploadResult;
    if (Parts.str(parsed.url).length === 0) {
      throw Failure.parse(Copy.notice_upload_no_path);
    }
    if (Parts.str(parsed.file_name).length === 0) {
      parsed.file_name = a.name;
    }
    return parsed;
  }

  /** Upload in pick order so ChatApi.buildParts can pair results with mimes. */
  async uploadAll(list: Attachment[]): Promise<UploadResult[]> {
    const out: UploadResult[] = [];
    for (const a of list) {
      out.push(await this.upload(a));
    }
    return out;
  }

  private compose(a: Attachment): MultipartBody {
    const boundary = this.boundaryName();
    const file = fs.openSync(a.uri, fs.OpenMode.READ_ONLY);
    try {
      const size = UploadApi.statSize(file.fd, a.name);
      if (size > MAX_UPLOAD_BYTES) {
        throw Failure.local(Copy.fillN2(Copy.notice_file_too_large, a.name, MAX_UPLOAD_MB));
      }
      const enc = new util.TextEncoder();
      const head = enc.encodeInto(`--${boundary}\r\nContent-Disposition: form-data; `
        + `name="file"; filename="${UploadApi.sanitizeFileName(a.name)}"\r\n`
        + `Content-Type: ${a.mime}\r\n\r\n`);
      const tail = enc.encodeInto(`\r\n--${boundary}--\r\n`);
      // The body is allocated as an ArrayBuffer up front: a typed array's own
      // .buffer is ArrayBufferLike, which is not assignable where an ArrayBuffer
      // is required.
      const bytes = new ArrayBuffer(head.byteLength + size + tail.byteLength);
      const out = new Uint8Array(bytes);
      out.set(new Uint8Array(head.buffer, head.byteOffset, head.byteLength), 0);
      UploadApi.copyInto(file.fd, size, out, head.byteLength, a.name);
      out.set(new Uint8Array(tail.buffer, tail.byteOffset, tail.byteLength), head.byteLength + size);
      const body = new MultipartBody();
      body.boundary = boundary;
      body.bytes = bytes;
      return body;
    } finally {
      fs.closeSync(file);
    }
  }

  /**
   * readSync always writes from the start of the buffer it is given, so the file
   * cannot be pulled into the middle of the body directly. Stream it through one
   * reused chunk instead of v1's whole-file buffer: peak memory is the body plus
   * 1MB, not twice the file.
   */
  private static copyInto(fd: number, size: number, out: Uint8Array, dest: number,
    name: string): void {
    const chunk = new ArrayBuffer(CHUNK_BYTES);
    let pos = 0;
    while (pos < size) {
      const options: ReadOptions = { offset: pos, length: Math.min(CHUNK_BYTES, size - pos) };
      const got = fs.readSync(fd, chunk, options);
      if (got <= 0) {
        break;
      }
      out.set(new Uint8Array(chunk, 0, got), dest + pos);
      pos += got;
    }
    if (pos !== size) {
      throw Failure.local(Copy.fill(Copy.notice_file_truncated, name));
    }
  }

  private static statSize(fd: number, name: string): number {
    const stat = fs.statSync(fd);
    if (stat.size <= 0) {
      throw Failure.local(Copy.fill(Copy.notice_file_unreadable, name));
    }
    return stat.size;
  }

  private boundaryName(): string {
    this.seq += 1;
    return `----qpm${Date.now()}${this.seq}`;
  }
}
