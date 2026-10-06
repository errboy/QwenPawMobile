/**
 * Design tokens for QwenPaw Mobile, mirroring the upstream semantic vocabulary
 * (design.md + console/src/styles/tokens.css). Components must consume these
 * names and never spell out a colour, radius or spacing value by hand.
 *
 * Colour values live in resources/{base,dark}/element/color.json so the system
 * re-resolves them on colour-mode change; animation durations cannot live in
 * resources and stay here as numbers.
 */
import { Bp } from '../core/Breakpoint';

export class AppColor {
  static readonly accent: Resource = $r('app.color.app_accent');
  static readonly accent_active: Resource = $r('app.color.app_accent_active');
  static readonly accent_text: Resource = $r('app.color.app_accent_text');
  static readonly accent_faint: Resource = $r('app.color.app_accent_faint');
  static readonly accent_soft: Resource = $r('app.color.app_accent_soft');
  static readonly accent_border: Resource = $r('app.color.app_accent_border');

  static readonly bg: Resource = $r('app.color.app_bg');
  static readonly surface: Resource = $r('app.color.app_surface');
  static readonly surface_subtle: Resource = $r('app.color.app_surface_subtle');
  static readonly surface_raised: Resource = $r('app.color.app_surface_raised');
  static readonly surface_sunken: Resource = $r('app.color.app_surface_sunken');
  /** Backdrop behind a full-screen image; white text on it reads in both themes. */
  static readonly scrim: Resource = $r('app.color.app_scrim');

  static readonly fill_strong: Resource = $r('app.color.app_fill_strong');
  static readonly fill: Resource = $r('app.color.app_fill');

  static readonly border: Resource = $r('app.color.app_border');
  static readonly border_strong: Resource = $r('app.color.app_border_strong');
  static readonly border_subtle: Resource = $r('app.color.app_border_subtle');

  static readonly text: Resource = $r('app.color.app_text');
  static readonly text_secondary: Resource = $r('app.color.app_text_secondary');
  static readonly text_tertiary: Resource = $r('app.color.app_text_tertiary');
  static readonly text_quaternary: Resource = $r('app.color.app_text_quaternary');
  static readonly text_inverse: Resource = $r('app.color.app_text_inverse');

  static readonly info_bg: Resource = $r('app.color.app_info_bg');
  static readonly info_border: Resource = $r('app.color.app_info_border');
  static readonly info_text: Resource = $r('app.color.app_info_text');
  static readonly success: Resource = $r('app.color.app_success');
  static readonly warning: Resource = $r('app.color.app_warning');
  static readonly warning_text: Resource = $r('app.color.app_warning_text');
  static readonly warning_bg: Resource = $r('app.color.app_warning_bg');
  static readonly warning_border: Resource = $r('app.color.app_warning_border');
  static readonly error: Resource = $r('app.color.app_error');
  static readonly error_text: Resource = $r('app.color.app_error_text');
  static readonly error_bg: Resource = $r('app.color.app_error_bg');
}

export class AppRadius {
  static readonly control: Resource = $r('app.float.app_radius');
  static readonly card: Resource = $r('app.float.app_radius_card');
  static readonly panel: Resource = $r('app.float.app_radius_panel');
  static readonly row: Resource = $r('app.float.app_radius_row');
  static readonly pill: Resource = $r('app.float.app_radius_pill');
}

export class AppSpace {
  static readonly xxs: Resource = $r('app.float.app_space_xxs');
  static readonly xs: Resource = $r('app.float.app_space_xs');
  static readonly sm: Resource = $r('app.float.app_space_sm');
  static readonly md: Resource = $r('app.float.app_space_md');
  static readonly lg: Resource = $r('app.float.app_space_lg');
  static readonly xl: Resource = $r('app.float.app_space_xl');
  static readonly xxl: Resource = $r('app.float.app_space_xxl');
  static readonly huge: Resource = $r('app.float.app_space_huge');
}

export class AppType {
  static readonly caption: Resource = $r('app.float.app_font_caption');
  static readonly secondary: Resource = $r('app.float.app_font_secondary');
  static readonly body: Resource = $r('app.float.app_font_body');
  static readonly message: Resource = $r('app.float.app_font_message');
  static readonly subtitle: Resource = $r('app.float.app_font_subtitle');
  static readonly title: Resource = $r('app.float.app_font_title');
  static readonly display: Resource = $r('app.float.app_font_display');
}

/**
 * Font families. Only code spans and code blocks ask for one, so everything else
 * keeps the system default untouched. 'monospace' resolves to the system mono face
 * where the device ships one and falls back silently where it does not.
 */
export class AppFont {
  static readonly mono: string = 'monospace';
}

export class AppLine {
  static readonly thin: Resource = $r('app.float.app_border_thin');
  static readonly emphasis: Resource = $r('app.float.app_border_emphasis');
}

export class AppSize {
  static readonly hit_target: Resource = $r('app.float.app_hit_target');
  /** A tool glyph in the composer's strip: a target, but not one that towers over the bar. */
  static readonly icon_hit: Resource = $r('app.float.app_icon_hit');
  /** Running-state dot next to a chat name. */
  static readonly status_dot: Resource = $r('app.float.app_status_dot');
  static readonly icon_md: Resource = $r('app.float.app_icon_md');
  static readonly input_min: Resource = $r('app.float.app_input_min_height');
  static readonly image_max: Resource = $r('app.float.app_image_max_height');
  /** 220vp x 16/9. Keeps a video box from turning into a wide black frame with
   * side bars on a tablet or an unfolded widefold. */
  static readonly video_max: Resource = $r('app.float.app_video_max_width');
  static readonly tool_max: Resource = $r('app.float.app_tool_collapsed_height');
  /** The `/` sheet caps here and scrolls, so a long registry stays reachable. */
  static readonly slash_max: Resource = $r('app.float.app_slash_max_height');
}

/** Width caps are percentages, so they stay numbers to feed constraintSize(). */
export class AppWidth {
  static readonly bubble_max: string = '82%';
  static readonly tool_max: string = '86%';
  static readonly chip_max: string = '60%';
}

/**
 * How much of a window a page may lay its content out in.
 *
 * Up to 'sm' the page fills the window: that is a phone, and it is also a
 * widefold's inner screen, which is only 440vp across. From 'md' up the column is
 * capped in vp and centred, so a chat line stays a readable measure instead of
 * stretching over a foldable's inner screen or a tablet. Two kinds, because a list
 * gains from width while prose does not.
 */
export class AppMeasure {
  /** Chat, login and settings: a line of text stays readable. */
  static text(wBp: string): ResourceStr | number {
    if (wBp === Bp.xs || wBp === Bp.sm) {
      return '100%';
    }
    return wBp === Bp.md ? 600 : 680;
  }

  /** Chat list and status rows, which read better with the room used. */
  static panel(wBp: string): ResourceStr | number {
    if (wBp === Bp.xs || wBp === Bp.sm) {
      return '100%';
    }
    return wBp === Bp.md ? 680 : 880;
  }
}

export class AppMotion {
  static readonly press_scale: number = 0.96;
  /** Micro state changes (colour, border). */
  static readonly small: number = 150;
  /** Selection, expansion, badge changes. */
  static readonly state: number = 300;
  /** Upstream standard curve cubic-bezier(.4,0,.2,1). */
  static readonly curve_state: Curve = Curve.FastOutSlowIn;
}
