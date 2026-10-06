/**
 * Three-state theme preference, matching the upstream console behaviour:
 * `system` follows the device, `light`/`dark` force the app palette.
 * Switching only changes the application colour mode, so the resource layer
 * re-resolves every token and no component code is involved.
 */
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { Copy } from '../l10n/Copy';
import { Settings } from '../core/Prefs';
import { Log } from '../core/Log';

export class ThemeMode {
  static readonly SYSTEM: string = 'system';
  static readonly LIGHT: string = 'light';
  static readonly DARK: string = 'dark';

  static all(): string[] {
    return [ThemeMode.SYSTEM, ThemeMode.LIGHT, ThemeMode.DARK];
  }

  static label(mode: string): string {
    if (mode === ThemeMode.LIGHT) {
      return Copy.theme_light;
    }
    if (mode === ThemeMode.DARK) {
      return Copy.theme_dark;
    }
    return Copy.theme_system;
  }

  static parse(raw: string): string {
    return ThemeMode.all().includes(raw) ? raw : ThemeMode.SYSTEM;
  }
}

export class ThemeManager {
  private static mode: string = ThemeMode.SYSTEM;

  static current(): string {
    return ThemeManager.mode;
  }

  static async restore(ctx: common.Context): Promise<string> {
    ThemeManager.mode = ThemeMode.parse(await Settings.themeMode(ctx));
    ThemeManager.apply(ctx);
    return ThemeManager.mode;
  }

  static async choose(ctx: common.Context, mode: string): Promise<string> {
    ThemeManager.mode = ThemeMode.parse(mode);
    await Settings.saveThemeMode(ctx, ThemeManager.mode);
    ThemeManager.apply(ctx);
    return ThemeManager.mode;
  }

  private static colorModeOf(mode: string): ConfigurationConstant.ColorMode {
    if (mode === ThemeMode.LIGHT) {
      return ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    }
    if (mode === ThemeMode.DARK) {
      return ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    }
    return ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
  }

  private static apply(ctx: common.Context): void {
    try {
      ctx.getApplicationContext().setColorMode(ThemeManager.colorModeOf(ThemeManager.mode));
    } catch (e) {
      Log.error(`setColorMode failed: ${(e as Error).message}`);
    }
  }
}
