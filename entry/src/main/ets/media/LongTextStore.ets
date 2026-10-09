/**
 * The phone's own copy of a message that outgrew the model's window.
 *
 * Such a message goes out as a text file beside a preview of its opening lines,
 * and this is the second copy of the whole thing. It is not in the media cache:
 * that directory is the system's to reclaim when it wants the space, and a text
 * the user typed is the one thing on this app that cannot be got back by opening
 * the asset again. So these bytes live under filesDir and leave only when the
 * cleanup page says so by name.
 */
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { CleanupFile } from '../model/Cleanup';
import { Log } from '../core/Log';

/** Subdirectory of filesDir, named for what it holds. */
const DIR_NAME: string = 'longtext';

/** The cleanup bucket these copies are listed under. */
const KIND: string = 'longtext';

/** Every name written here starts with this, and nothing else is accepted back. */
const PREFIX: string = 'longtext-';

/**
 * One text per send, under a name that is also the name the desktop received, so
 * the row on the cleanup page needs no name recovery and a copy can be read back
 * by the message it came from.
 */
export class LongTextStore {
  /** Empty until bind() names the sandbox directory; every call then no-ops. */
  private dir: string = '';

  bind(ctx: common.Context): void {
    this.dir = `${ctx.filesDir}/${DIR_NAME}`;
  }

  /**
   * Keep a copy of what is about to be sent. False means the send still goes and
   * only the local recovery is lost, so the caller must not gate a message on it.
   */
  save(name: string, text: string): boolean {
    if (!LongTextStore.isMine(name) || this.dir.length === 0) {
      return false;
    }
    try {
      LongTextStore.makeDir(this.dir);
      const file = fs.openSync(`${this.dir}/${name}`,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        // A string, not an encoded view: writeSync(fd, Uint8Array) accepts the call
        // and writes no bytes at all, which left every copy a 0 B file on disk.
        fs.writeSync(file.fd, text);
      } finally {
        fs.closeSync(file);
      }
      return true;
    } catch (e) {
      Log.warn(`[LongText] 本机全文未能保存 ${name}`);
      return false;
    }
  }

  /** Every copy held, newest first — the read the cleanup page's rows are built from. */
  files(): CleanupFile[] {
    const out: CleanupFile[] = [];
    if (this.dir.length === 0) {
      return out;
    }
    let names: string[] = [];
    try {
      names = fs.listFileSync(this.dir);
    } catch (e) {
      // No directory yet means nothing was ever kept, not that a cleanup failed.
      return out;
    }
    for (const name of names) {
      if (!LongTextStore.isMine(name)) {
        continue;
      }
      try {
        const stat = fs.statSync(`${this.dir}/${name}`);
        const file = new CleanupFile();
        file.name = name;
        file.path = `${this.dir}/${name}`;
        file.kind = KIND;
        file.bytes = stat.size;
        file.modified = stat.mtime * 1000;
        out.push(file);
      } catch (e) {
        // Gone between the listing and the stat, so it is not a row to tick either.
      }
    }
    out.sort((a: CleanupFile, b: CleanupFile): number => b.modified - a.modified);
    return out;
  }

  /**
   * Throw away the named copies; returns how many actually went. Names that are
   * not this store's are the other half of the cleanup page's pick list, so they
   * pass through without a word — only a name that could not be a file is refused.
   */
  dropFiles(names: string[]): number {
    let gone: number = 0;
    for (const name of names) {
      if (!LongTextStore.isMine(name)) {
        continue;
      }
      const path = `${this.dir}/${name}`;
      try {
        fs.unlinkSync(path);
        gone += 1;
      } catch (e) {
        Log.warn(`[LongText] 本机全文未能删除 ${name}`);
      }
    }
    return gone;
  }

  /**
   * A name this store wrote, and only that. The page hands back what files()
   * listed, and nothing outside this directory should be reachable from here —
   * the directory sits beside the app's whole files tree, not in a cache of its own.
   */
  private static isMine(name: string): boolean {
    return name.startsWith(PREFIX) && /^[A-Za-z0-9._-]+$/.test(name)
      && name !== '.' && name !== '..';
  }

  private static makeDir(dir: string): void {
    try {
      fs.mkdirSync(dir);
    } catch (e) {
      // The only real case here is 'already there'.
    }
  }
}
