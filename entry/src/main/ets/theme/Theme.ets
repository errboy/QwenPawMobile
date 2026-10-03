/**
 * Design tokens for QwenPaw Mobile, mirroring the upstream semantic vocabulary
 * (design.md + console/src/styles/tokens.css). Components must consume these
 * names and never spell out a colour, radius or spacing value by hand.
 *
 * Colour values live in resources/{base,dark}/element/color.json so the system
 * re-resolves them on colour-mode change; durations and layers cannot live in
 * resources and stay here as numbers.
 */
import { Bp } from '../core/Breakpoint';

export class AppColor {
  static readonly accent: Resource = $r('app.color.app_accent');
  static readonly accent_hover: Resource = $r('app.color.app_accent_hover');
  static readonly accent_active: Resource = $r('app.color.app_accent_active');
  static readonly accent_text: Resource = $r('app.color.app_accent_text');
  static readonly accent_faint: Resource = $r('app.color.app_accent_faint');
  static readonly accent_soft: Resource = $r('app.color.app_accent_soft');
  static readonly accent_border: Resource = $r('app.color.app_accent_border');
  static readonly accent_ring: Resource = $r('app.color.app_accent_ring');
  static readonly focus_ring: Resource = $r('app.color.app_focus_ring');

  static readonly bg: Resource = $r('app.color.app_bg');
  static readonly surface: Resource = $r('app.color.app_surface');
  static readonly surface_subtle: Resource = $r('app.color.app_surface_subtle');
  static readonly surface_raised: Resource = $r('app.color.app_surface_raised');
  static readonly surface_sunken: Resource = $r('app.color.app_surface_sunken');
  static readonly shell_bg: Resource = $r('app.color.app_shell_bg');

  static readonly fill_strong: Resource = $r('app.color.app_fill_strong');
  static readonly fill: Resource = $r('app.color.app_fill');
  static readonly fill_subtle: Resource = $r('app.color.app_fill_subtle');
  static readonly fill_faint: Resource = $r('app.color.app_fill_faint');

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
  static readonly success_text: Resource = $r('app.color.app_success_text');
  static readonly success_bg: Resource = $r('app.color.app_success_bg');
  static readonly success_border: Resource = $r('app.color.app_success_border');
  static readonly warning: Resource = $r('app.color.app_warning');
  static readonly warning_text: Resource = $r('app.color.app_warning_text');
  static readonly warning_bg: Resource = $r('app.color.app_warning_bg');
  static readonly warning_border: Resource = $r('app.color.app_warning_border');
  static readonly error: Resource = $r('app.color.app_error');
  static readonly error_text: Resource = $r('app.color.app_error_text');
  static readonly error_bg: Resource = $r('app.color.app_error_bg');
  static readonly error_border: Resource = $r('app.color.app_error_border');
  static readonly error_ring: Resource = $r('app.color.app_error_ring');
  static readonly status_idle: Resource = $r('app.color.app_status_idle');
  static readonly highlight_bg: Resource = $r('app.color.app_highlight_bg');
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
  static readonly focus: Resource = $r('app.float.app_border_focus');
}

export class AppSize {
  static readonly hit_target: Resource = $r('app.float.app_hit_target');
  /** Running-state dot next to a chat name. */
  static readonly status_dot: Resource = $r('app.float.app_status_dot');
  static readonly icon_sm: Resource = $r('app.float.app_icon_sm');
  static readonly icon_md: Resource = $r('app.float.app_icon_md');
  static readonly icon_lg: Resource = $r('app.float.app_icon_lg');
  static readonly input_min: Resource = $r('app.float.app_input_min_height');
  static readonly input_max: Resource = $r('app.float.app_input_max_height');
  static readonly image_max: Resource = $r('app.float.app_image_max_height');
  static readonly tool_max: Resource = $r('app.float.app_tool_collapsed_height');
}

/** Width caps are percentages, so they stay numbers to feed constraintSize(). */
export class AppWidth {
  static readonly bubble_max: string = '82%';
  static readonly tool_max: string = '86%';
  static readonly chip_max: string = '60%';
  static readonly status_w: number = 64;
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
  /** Sheets and cards entering; exit is deliberately quicker. */
  static readonly enter: number = 400;
  static readonly exit: number = 300;
  static readonly stagger: number = 30;
  static readonly stagger_cap: number = 200;
  /** Upstream standard curve cubic-bezier(.4,0,.2,1). */
  static readonly curve_state: Curve = Curve.FastOutSlowIn;
  /** Upstream entrance curve cubic-bezier(.16,1,.3,1). */
  static readonly curve_enter: Curve = Curve.Smooth;
}

export class AppElevation {
  static readonly sm: ShadowOptions = {
    radius: 8,
    color: $r('app.color.app_shadow_sm'),
    offsetX: 0,
    offsetY: 2,
    type: ShadowType.COLOR,
    fill: false
  };
  static readonly md: ShadowOptions = {
    radius: 16,
    color: $r('app.color.app_shadow_md'),
    offsetX: 0,
    offsetY: 4,
    type: ShadowType.COLOR,
    fill: false
  };
  static readonly panel: ShadowOptions = {
    radius: 24,
    color: $r('app.color.app_shadow_panel'),
    offsetX: 0,
    offsetY: 12,
    type: ShadowType.COLOR,
    fill: false
  };
}

/** In-content layers stay below 10; only overlays may exceed it. */
export class AppLayer {
  static readonly content: number = 1;
  static readonly sticky: number = 4;
  static readonly local_overlay: number = 20;
  static readonly sheet_scrim: number = 1100;
  static readonly sheet: number = 1101;
}
