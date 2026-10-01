import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0927;
const TAG: string = 'QwenPawMobile';

export class Log {
  static info(message: string): void {
    hilog.info(DOMAIN, TAG, '%{public}s', message);
  }

  static warn(message: string): void {
    hilog.warn(DOMAIN, TAG, '%{public}s', message);
  }

  static error(message: string): void {
    hilog.error(DOMAIN, TAG, '%{public}s', message);
  }
}
