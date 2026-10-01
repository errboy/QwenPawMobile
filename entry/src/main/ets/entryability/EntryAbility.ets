/**
 * The only place that boots the app.
 *
 * Two things happen here and nothing else: the saved palette is applied before the
 * first frame, and StoreHub reads the saved session so a page never submits against
 * an unconfigured client.
 */
import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { StoreHub } from '../state/StoreHub';
import { ThemeManager } from '../theme/ThemeManager';

const DOMAIN: number = 0x0000;
const TAG: string = 'QwenPaw';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    ThemeManager.restore(this.context);
    StoreHub.shared().start(this.context);
  }

  onDestroy(): void {
    // Streams and the poll timer are owned by the hub, so the ability releases them.
    StoreHub.shared().reset();
    hilog.info(DOMAIN, TAG, 'Ability destroyed');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err: BusinessError): void => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load the first page: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, 'First page loaded');
    });
  }

  onForeground(): void {
    // Coming back to the app should not wait for the next tick.
    StoreHub.shared().poller.poke();
  }
}
