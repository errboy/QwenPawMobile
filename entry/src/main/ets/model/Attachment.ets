/**
 * One file the user picked locally and has not uploaded yet.
 * Deliberately not a wire DTO: it holds a content URI, not a server path.
 */
export class Attachment {
  key: string = '';
  /** Picker URI (file://media/... or file://docs/...), read lazily at send time. */
  uri: string = '';
  name: string = '';
  mime: string = '';
}
