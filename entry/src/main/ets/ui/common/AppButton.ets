/**
 * The app's only button.
 *
 * Primary uses the brand accent, quiet uses a surface with a border; both keep the
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

  build() {
    Button(this.label)
      .type(ButtonType.Normal)
      .fontSize(AppType.body)
      .fontColor(this.quiet ? AppColor.text : AppColor.text_inverse)
      .backgroundColor(this.quiet ? AppColor.surface_raised : AppColor.accent)
      .border({ width: this.quiet ? AppLine.thin : 0, color: AppColor.border })
      .borderRadius(AppRadius.control)
      .padding({ left: AppSpace.md, right: AppSpace.md })
      .constraintSize({ minHeight: AppSize.hit_target, minWidth: AppSize.hit_target })
      .height(AppSize.hit_target)
      .width(this.grow ? '100%' : undefined)
      .enabled(!this.disabled)
      .opacity(this.disabled ? 0.5 : 1)
      .scale({ x: this.pressed ? AppMotion.press_scale : 1, y: this.pressed ? AppMotion.press_scale : 1 })
      .animation({ duration: AppMotion.small, curve: AppMotion.curve_state })
      .onTouch((event: TouchEvent): void => {
        if (event.type === TouchType.Down) {
          this.pressed = true;
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.pressed = false;
        }
      })
      .onClick(() => {
        this.onTap();
      })
  }
}
