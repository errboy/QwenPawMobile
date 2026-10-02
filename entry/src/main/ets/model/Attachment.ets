/**
 * One file the user picked locally and has not uploaded yet.
 * Deliberately not a wire DTO: it holds a content URI, not a server path.
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
}

/** Which system picker the ＋ menu asked for. */
export class AttachSource {
  static readonly GALLERY: string = 'gallery';
  static readonly FILES: string = 'files';
  static readonly AUDIO: string = 'audio';
}
