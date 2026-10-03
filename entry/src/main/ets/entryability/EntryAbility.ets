/**
 * The only place that boots the app.
 *
 * Three things happen here and nothing else: the saved palette is applied before
 * the first frame, StoreHub reads the saved session so a page never submits
 * against an unconfigured client, and the main window starts reporting its width
 * bucket so pages size themselves for a phone or a tablet.
 */
import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { StoreHub } from '../state/StoreHub';
import { ThemeManager } from '../theme/ThemeManager';
import { Breakpoint } from '../core/Breakpoint';
import { Log } from '../core/Log';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    ThemeManager.restore(this.context);
    StoreHub.shared().start(this.context);
  }

  onDestroy(): void {
    // Streams and the poll timer are owned by the hub, so the ability releases them.
    StoreHub.shared().reset();
    Breakpoint.detach();
    Log.info('Ability destroyed');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Before the page loads: the window rect is already readable, so the first
    // frame can be sized right instead of painting phone-width and jumping.
    Breakpoint.attach(windowStage);
    windowStage.loadContent('pages/Index', (err: BusinessError): void => {
      if (err.code) {
        Log.error(`Failed to load the first page: ${JSON.stringify(err)}`);
        return;
      }
      // After the first frame the UIContext exists, so the system's own bucket
      // replaces the rect estimate.
      Breakpoint.resync();
      Log.info('First page loaded');
    });
  }

  onForeground(): void {
    // Coming back to the app should not wait for the next tick.
    StoreHub.shared().poller.poke();
  }
}
