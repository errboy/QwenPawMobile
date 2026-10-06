/**
 * One thing queued in the composer and not uploaded yet.
 * Deliberately not a wire DTO: it holds a content URI or its own bytes,
 * not a server path.
 */
export class Attachment {
  key: string = '';
  /**
   * Picker URI (file://media/... or file://docs/...) or the sandbox path of a
   * recording. Read lazily at send time, so a queued file costs nothing until then.
   */
  uri: string = '';
  name: string = '';
  mime: string = '';
  /**
   * Set for a message quoted out of the transcript: the bytes already sit on the
   * server under this reference, so sending reuses it and uploads nothing.
   */
  ref: string = '';
  /**
   * Full text of a quoted message too long to paste into the composer. Held in
   * memory and uploaded as a text file at send time instead of written to the
   * sandbox first: a temp file would have to survive from the quote to the send
   * (the system reclaims `cacheDir` under storage pressure), and anything it
   * leaves behind when the tray is cleared needs its own delete rules.
   */
  text: string = '';
}

/** Which kind of content a quoted reference carries. */
export class QuoteKind {
  static readonly TEXT: string = 'text';
  static readonly IMAGE: string = 'image';
  static readonly VIDEO: string = 'video';
  static readonly AUDIO: string = 'audio';
  static readonly FILE: string = 'file';
}

/** Which system picker the ＋ menu asked for. */
export class AttachSource {
  static readonly GALLERY: string = 'gallery';
  static readonly FILES: string = 'files';
  static readonly AUDIO: string = 'audio';
}
