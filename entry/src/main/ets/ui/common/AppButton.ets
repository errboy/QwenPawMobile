/**
 * The app's only button.
 *
 * Primary uses the action fill, quiet uses a surface with a border; both keep the
 * 44vp touch target and the shared press feedback, so no page has to restate them.
 */
import { AppColor, AppLine, AppMotion, AppRadius, AppSize, AppSpace, AppType } from '../../theme/Theme';

@Component
export struct AppButton {
  @Prop label: string = '';
  @Prop quiet: boolean = false;
  @Prop disabled: boolean = false;
  @Prop grow: boolean = false;
  @State pressed: boolean = false;
  onTap: () => void = (): void => {};

  /**
   * Disabled is its own colour pair rather than a washed live button: ArkUI dims a
   * disabled `Button` to ~40% opacity on its own (measured on screen: fill 240, label
   * 180 -> 1.8:1, and `.opacity(1)` does not override it), so the button stays enabled
   * and swallows the tap in `onClick` instead. That is also what the store's 1.27:1
   * login-button finding came down to.
   */
  private ink(): Resource {
    if (this.disabled) {
      return AppColor.text_secondary;
    }
    return this.quiet ? AppColor.text : AppColor.on_action;
  }

  private fill(): Resource {
    if (this.disabled) {
      return AppColor.fill_strong;
    }
    return this.quiet ? AppColor.surface_raised : AppColor.accent_action;
  }

  build() {
    Button(this.label)
      .type(ButtonType.Normal)
      .fontSize(AppType.body)
      .fontColor(this.ink())
      .backgroundColor(this.fill())
      .border({ width: this.quiet ? AppLine.thin : 0, color: AppColor.border })
      .borderRadius(AppRadius.control)
      .padding({ left: AppSpace.md, right: AppSpace.md })
      .constraintSize({ minHeight: AppSize.hit_target, minWidth: AppSize.hit_target })
      .height(AppSize.hit_target)
      .width(this.grow ? '100%' : undefined)
      .scale({ x: this.pressed ? AppMotion.press_scale : 1, y: this.pressed ? AppMotion.press_scale : 1 })
      .animation({ duration: AppMotion.small, curve: AppMotion.curve_state })
      .onTouch((event: TouchEvent): void => {
        if (this.disabled) {
          this.pressed = false;
          return;
        }
        if (event.type === TouchType.Down) {
          this.pressed = true;
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.pressed = false;
        }
      })
      .onClick(() => {
        if (!this.disabled) {
          this.onTap();
        }
      })
  }
}
