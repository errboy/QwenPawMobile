/**
 * The shapes the cleanup page needs.
 *
 * Cleanup is split by *kind* of local residue rather than offered as one tap,
 * because the categories have very different costs: dropping a cached clip costs
 * a re-download, and that is about the worst this page can do on purpose.
 *
 * What is deliberately not here: unsent drafts, saved accounts and server
 * addresses. A draft is text the user was writing, and the two others are login
 * configuration, which is edited and emptied on the login configuration page.
 * Putting them next to a cache sweep is how a 'clean up' tap loses a paragraph.
 */

/** The five buckets the cache splits into, as the page names its rows. */
export const CLEANUP_KINDS: string[] = ['video', 'audio', 'doc', 'record', 'other'];

/**
 * One local copy the cleanup page can list, tick and delete.
 *
 * `name` is the handle the delete goes through, and a whole category is just all
 * of its names: one route for both, so a bucket sweep and a single-copy sweep
 * cannot drift apart on a suffix one of them reads differently.
 */
export class CleanupFile {
  /** Name on disk. Hashed on purpose: the server's file name stays on the server. */
  name: string = '';
  /**
   * Name the user recognises, recovered in StoreHub from the references the
   * running app still holds; '' when nothing on this phone points at this copy
   * any more (a cache entry older than the current process keeps only its hash).
   */
  label: string = '';
  /** Absolute sandbox path, so the row can open what it offers to delete. */
  path: string = '';
  /** Bucket it falls in, so the page can group copies under their category. */
  kind: string = 'other';
  bytes: number = 0;
  /** Last write in ms since the epoch — the one cue a hashed name still gives. */
  modified: number = 0;
}

/** What the phone holds right now, as read from the device. */
export class CleanupTally {
  videoFiles: number = 0;
  videoBytes: number = 0;
  audioFiles: number = 0;
  audioBytes: number = 0;
  docFiles: number = 0;
  docBytes: number = 0;
  recordFiles: number = 0;
  recordBytes: number = 0;
  otherFiles: number = 0;
  otherBytes: number = 0;
  choices: number = 0;
  /** Every copy on the phone, newest first. The counts above are these, summed. */
  files: CleanupFile[] = [];

  /** Fold one copy into its bucket's counts. */
  add(kind: string, bytes: number): void {
    if (kind === 'video') {
      this.videoFiles += 1;
      this.videoBytes += bytes;
    } else if (kind === 'audio') {
      this.audioFiles += 1;
      this.audioBytes += bytes;
    } else if (kind === 'doc') {
      this.docFiles += 1;
      this.docBytes += bytes;
    } else if (kind === 'record') {
      this.recordFiles += 1;
      this.recordBytes += bytes;
    } else {
      this.otherFiles += 1;
      this.otherBytes += bytes;
    }
  }
}

/**
 * Which copies the user picked on the cleanup page.
 *
 * A category ticked whole is the same thing as every file in it ticked, so this
 * holds the files and nothing else: the delete has one route, and the category
 * checkbox is the page's shortcut for 'all of mine'.
 */
export class CleanupPicks {
  files: CleanupFile[] = [];
  choices: boolean = false;

  /** Items on the button and the receipt: each copy, plus the preferences once. */
  count(): number {
    return this.files.length + (this.choices ? 1 : 0);
  }
}
