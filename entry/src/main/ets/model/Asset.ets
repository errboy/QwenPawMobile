/**
 * One row of the session's asset list.
 *
 * The server owns the transcript, so this is not a second store: every row is read
 * off a UiMessage that is already on screen, and `cached` says whether the phone
 * happens to hold those bytes too. A row whose asset was never opened is real —
 * it just costs a fetch to save or forward.
 */
export class AssetRow {
  /** This row's own identity: message key plus media kind. Jumping uses `index`. */
  key: string = '';
  /** Key of the message this row was read off; "open" looks the bubble back up. */
  msgKey: string = '';
  /** Position in the transcript list. */
  index: number = 0;
  /** One of QuoteKind's media values. */
  kind: string = '';
  /** Stored path, data: URI or direct URL — what the transcript carries. */
  ref: string = '';
  name: string = '';
  /** When the carrying turn happened, as a list shows it ('10-06 21:30'); '' if unknown. */
  stamp: string = '';
  cached: boolean = false;
  size: number = 0;
}
