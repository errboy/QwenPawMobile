/**
 * Window-width breakpoints.
 *
 * The layout key is the window, never the device type: a foldable reports 'phone'
 * whatever its hinge is doing, and one device walks through several buckets as it
 * unfolds. Measured on emulators, all of them at 2.0-2.75 px/vp:
 * Mate X inner 711vp 'md' / outer 345vp 'sm'; Mate XT 1107 'lg' / 712 'md' / 350 'sm';
 * Pura X Max widefold inner 939vp 'lg' / outer 459vp 'sm'; MatePad 1137vp 'lg' /
 * MatePad Pro 13 1440vp 'xl'. A widefold is not automatically narrow.
 *
 * So the window is measured and published from EntryAbility, and every page reads
 * the same AppStorage key instead of asking what device it is on. It is measured
 * twice: from the window rect before the first frame, so a tablet does not paint
 * one phone-width frame and jump, and through the UIContext once it exists.
 */
import { display, window } from '@kit.ArkUI';
import { Log } from './Log';

/** Bucket names, matching the system thresholds in vp: <320, [320,600), [600,840), [840,1440), 1440+. */
export class Bp {
  static readonly xs: string = 'xs';
  static readonly sm: string = 'sm';
  static readonly md: string = 'md';
  static readonly lg: string = 'lg';
  static readonly xl: string = 'xl';

  /**
   * AppStorage key. The default is 'sm' on purpose: that is the phone bucket, and
   * it is the one layout every page had before responsive sizing existed, so a
   * window that never reports in still renders the way it always did.
   */
  static readonly KEY: string = 'qpWidthBp';
}

export class Breakpoint {
  private static mainWindow: window.Window | undefined = undefined;
  /** One closure, so off() can identify the listener it removes. */
  private static readonly onSize: (size: window.Size) => void = (): void => {
    Breakpoint.publish();
  };

  /**
   * Called before the page loads. The window rect is readable this early, which is
   * what sizes the first frame; {@link resync} upgrades the reading later.
   */
  static attach(windowStage: window.WindowStage): void {
    try {
      const win = windowStage.getMainWindowSync();
      Breakpoint.mainWindow = win;
      Breakpoint.publish();
      win.on('windowSizeChange', Breakpoint.onSize);
    } catch (e) {
      Log.warn(`Breakpoint: no window to measure, layout stays phone-width: ${JSON.stringify(e)}`);
    }
  }

  static detach(): void {
    const win = Breakpoint.mainWindow;
    Breakpoint.mainWindow = undefined;
    if (win === undefined) {
      return;
    }
    try {
      win.off('windowSizeChange', Breakpoint.onSize);
    } catch (e) {
      Log.warn(`Breakpoint: listener not removed: ${JSON.stringify(e)}`);
    }
  }

  /** Re-read once the first frame exists, so the system's own bucket wins. */
  static resync(): void {
    Breakpoint.publish();
  }

  private static publish(): void {
    const win = Breakpoint.mainWindow;
    if (win === undefined) {
      return;
    }
    const bp = Breakpoint.of(win);
    if (AppStorage.get<string>(Bp.KEY) !== bp) {
      Log.info(`Window width bucket is ${bp}`);
      AppStorage.setOrCreate(Bp.KEY, bp);
    }
  }

  private static of(win: window.Window): string {
    try {
      return Breakpoint.nameOf(win.getUIContext().getWindowWidthBreakpoint());
    } catch (e) {
      return Breakpoint.fromRect(win);
    }
  }

  /** The system thresholds, applied by hand for the frame before a UIContext exists. */
  private static fromRect(win: window.Window): string {
    try {
      const widthVp = win.getWindowProperties().windowRect.width / display.getDefaultDisplaySync().densityPixels;
      if (widthVp < 320) {
        return Bp.xs;
      }
      if (widthVp < 600) {
        return Bp.sm;
      }
      if (widthVp < 840) {
        return Bp.md;
      }
      return widthVp < 1440 ? Bp.lg : Bp.xl;
    } catch (e) {
      Log.warn(`Breakpoint: window rect unreadable, using phone layout: ${JSON.stringify(e)}`);
      return Bp.sm;
    }
  }

  private static nameOf(raw: WidthBreakpoint): string {
    if (raw === WidthBreakpoint.WIDTH_XS) {
      return Bp.xs;
    }
    if (raw === WidthBreakpoint.WIDTH_MD) {
      return Bp.md;
    }
    if (raw === WidthBreakpoint.WIDTH_LG) {
      return Bp.lg;
    }
    if (raw === WidthBreakpoint.WIDTH_XL) {
      return Bp.xl;
    }
    return Bp.sm;
  }
}
