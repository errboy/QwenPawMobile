/**
 * Getting one asset out of the app sandbox.
 *
 * Every door here is one the user opens: the media library confirms the save in a
 * system dialog, the document picker hands the destination choice over, the share
 * panel is a system surface, and `startAbility` either raises the system's own
 *「打开方式」chooser or lands in the one app registered for that file type. That is
 * why none of this asks for a permission — the alternatives are all
 * restricted-permission APIs this app has no business holding, since it only ever
 * exports a file the user just looked at.
 */
import { common, Want, wantConstant } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { picker, fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { Failure } from '../core/Failure';
import { Log } from '../core/Log';
import { Copy } from '../l10n/Copy';

/** Suffix of a stored name, lowercased; '' when there is none to read. */
function extensionOf(name: string): string {
  const clean = name.split('?')[0].split('#')[0];
  const dot = clean.lastIndexOf('.');
  if (dot < 0 || clean.length - dot > 6) {
    return '';
  }
  return clean.substring(dot + 1).toLowerCase();
}

/** Media library wants a title without the extension it is told separately. */
function titleOf(name: string): string {
  const dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}

/** Last segment of whatever the caller called a name, on either slash style. */
function leafOf(value: string): string {
  const flat = value.split('\\').join('/');
  const slash = flat.lastIndexOf('/');
  return slash >= 0 ? flat.substring(slash + 1) : flat;
}

/**
 * What the destination gets called. The name comes off the transcript, which the
 * server writes, so it is not trusted to be a plain file name: a value that still
 * carries slashes would reach the gallery title and the document picker's suggested
 * name as a path. The sandbox file's own hashed name is the fallback.
 */
function displayName(name: string, path: string): string {
  const leaf = leafOf(name);
  return leaf.length > 0 ? leaf : leafOf(path);
}

/**
 * The type a suffix maps to, or '' when this phone has no entry for it.
 *
 * `belongsTo` is optional and has no default, so it is left off rather than passed
 * as '': the empty string is rejected as a bad parameter, and the API throws rather
 * than returning ''. Neither door below can treat that throw as the answer — share
 * has its own 'unknown type' line to show, and open leaves the type out so the
 * system reads it off the URI suffix.
 */
function utdOf(ext: string): string {
  if (ext.length === 0) {
    return '';
  }
  try {
    return utd.getUniformDataTypeByFilenameExtension(`.${ext}`);
  } catch (e) {
    return '';
  }
}

/** Whether bytes really landed. An empty entry is a broken download, not a file. */
function hasBytes(path: string): boolean {
  try {
    return fs.statSync(path).size > 0;
  } catch (e) {
    return false;
  }
}

/** Copy sandbox bytes into a destination URI the caller has just been granted. */
async function copyInto(from: string, to: string): Promise<void> {
  const src = await fs.open(from, fs.OpenMode.READ_ONLY);
  try {
    // READ_WRITE, not WRITE_ONLY: the media library hands back a URI it expects the
    // writer to reopen read-write, and a write-only open on it is refused.
    const dest = await fs.open(to, fs.OpenMode.READ_WRITE);
    try {
      await fs.copyFile(src.fd, dest.fd);
    } finally {
      fs.closeSync(dest);
    }
  } finally {
    fs.closeSync(src);
  }
}

export class Export {
  /**
   * Image or video into the gallery. An empty array back means the user declined,
   * which is a normal outcome and not an error to report.
   */
  static async toGallery(ctx: common.UIAbilityContext, path: string, name: string,
    video: boolean): Promise<string> {
    if (!hasBytes(path)) {
      return Copy.fill(Copy.assets_fetch_failed, displayName(name, path));
    }
    const shown = displayName(name, path);
    const helper = photoAccessHelper.getPhotoAccessHelper(ctx);
    try {
      const config: photoAccessHelper.PhotoCreationConfig = {
        title: titleOf(shown),
        fileNameExtension: extensionOf(shown),
        photoType: video ? photoAccessHelper.PhotoType.VIDEO : photoAccessHelper.PhotoType.IMAGE,
        subtype: photoAccessHelper.PhotoSubtype.DEFAULT
      };
      const targets: string[] = await helper.showAssetsCreationDialog([path], [config]);
      if (targets.length === 0) {
        return '';
      }
      await copyInto(path, targets[0]);
      return Copy.export_saved_gallery;
    } catch (e) {
      return Copy.fill(Copy.export_save_failed, Failure.from(e as Object).message);
    } finally {
      helper.release();
    }
  }

  /** Anything the gallery does not hold — a voice note, a document — to a folder. */
  static async toDocuments(ctx: common.UIAbilityContext, path: string, name: string): Promise<string> {
    if (!hasBytes(path)) {
      return Copy.fill(Copy.assets_fetch_failed, displayName(name, path));
    }
    try {
      const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
      options.newFileNames = [displayName(name, path)];
      const targets: string[] = await new picker.DocumentViewPicker(ctx).save(options);
      if (targets.length === 0) {
        return '';
      }
      await copyInto(path, targets[0]);
      return Copy.export_saved;
    } catch (e) {
      return Copy.fill(Copy.export_save_failed, Failure.from(e as Object).message);
    }
  }

  /**
   * Hand the file to the system share panel. The panel grants the reader access to
   * this sandbox URI for the duration of the transfer, so nothing is copied into a
   * world-readable place first.
   */
  static async share(ctx: common.UIAbilityContext, path: string, name: string): Promise<string> {
    if (!hasBytes(path)) {
      return Copy.fill(Copy.assets_fetch_failed, displayName(name, path));
    }
    const shown = displayName(name, path);
    const ext = extensionOf(shown);
    if (ext.length === 0) {
      return Copy.export_no_ext;
    }
    // The type comes from the suffix rather than a hard-coded list: a wrong UTD makes
    // the panel hide every target app, which reads as '转发没反应'.
    const kind = utdOf(ext);
    if (kind.length === 0) {
      return Copy.fill(Copy.export_unknown_type, ext);
    }
    try {
      const data = new systemShare.SharedData({
        utd: kind,
        uri: fileUri.getUriFromPath(path),
        title: shown
      });
      const controller = new systemShare.ShareController(data);
      await controller.show(ctx, { selectionMode: systemShare.SelectionMode.SINGLE });
      return '';
    } catch (e) {
      return Copy.fill(Copy.export_share_failed, Failure.from(e as Object).message);
    }
  }

  /**
   * Hand the file to an installed app that reads its type. Unlike the other doors
   * here the success case shows nothing in this app — the reader opens in front of
   * it — so the only thing to report back is a match failure, which the system
   * raises as an error code rather than a dialog.
   */
  static async open(ctx: common.UIAbilityContext, path: string, name: string): Promise<string> {
    if (!hasBytes(path)) {
      return Copy.fill(Copy.assets_fetch_failed, displayName(name, path));
    }
    const shown = displayName(name, path);
    const ext = extensionOf(shown);
    // A type that does not match the file is what makes every app drop out of the
    // match, so an unknown suffix is left out and the system reads it off the URI.
    const kind = utdOf(ext);
    const want: Want = {
      action: 'ohos.want.action.viewData',
      uri: fileUri.getUriFromPath(path),
      flags: wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION
    };
    if (kind.length > 0) {
      want.type = kind;
    }
    try {
      await ctx.startAbility(want);
      return '';
    } catch (e) {
      Log.warn(`[Export] 打开 ${shown} 失败: ${Failure.from(e as Object).message}`);
      return Copy.export_open_failed;
    }
  }
}
