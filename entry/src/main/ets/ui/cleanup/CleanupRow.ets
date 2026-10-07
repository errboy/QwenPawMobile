/**
 * One category row on the cleanup page.
 *
 * This is a component rather than a @Builder because the tally arrives after the
 * first frame: a builder called with plain values renders once with whatever the
 * page held at that moment and never re-reads them, so every category would stay
 * frozen at 'nothing to clean'. Only a component's @Prop follows the parent.
 */
import { AppColor, AppLine, AppRadius, AppSpace, AppType } from '../../theme/Theme';
import { Copy } from '../../l10n/Copy';

@Component
export struct CleanupRow {
  @Prop label: string;
  @Prop detail: string;
  /** False means this kind of data is not on the device right now. */
  @Prop available: boolean;
  /** Ticked whole. The page derives it from its copies, so 'all of mine'. */
  @Prop on: boolean;
  /** Rows with copies worth naming one at a time get the tail that lists them. */
  @Prop expandable: boolean;
  @Prop open: boolean;
  onPick: (on: boolean) => void = (): void => {};
  onToggle: () => void = (): void => {};

  /**
   * A row with nothing on the device shows no control at all rather than a greyed
   * one: ArkUI washes a disabled Checkbox down to ~1.4:1 against the card, which
   * fails the store's graphic-contrast bar, and a dead tick box promises a pick
   * that cannot happen. The dimmed label and 'nothing to clean' line say it.
   */
  build() {
    Row({ space: AppSpace.sm }) {
      if (this.available) {
        Checkbox()
          .select(this.on)
          .width(24)
          .height(24)
          .selectedColor(AppColor.accent_action)
          .unselectedColor(AppColor.border_strong)
          .onChange((value: boolean): void => {
            this.onPick(value);
          })
      } else {
        Column()
          .width(24)
          .height(24)
      }
      Column({ space: AppSpace.xxs }) {
        Text(this.label)
          .fontSize(AppType.body)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.available ? AppColor.text : AppColor.text_quaternary)
        Text(this.available ? this.detail : Copy.cleanup_nothing)
          .fontSize(AppType.caption)
          .fontColor(AppColor.text_quaternary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.expandable) {
        Text(this.open ? Copy.cleanup_items_close : Copy.cleanup_items)
          .fontSize(AppType.caption)
          .fontColor(AppColor.accent_text)
          .padding({
            left: AppSpace.sm,
            right: AppSpace.sm,
            top: AppSpace.xs,
            bottom: AppSpace.xs
          })
          .onClick((): void => {
            this.onToggle();
          })
      }
    }
    .width('100%')
    .padding(AppSpace.sm)
    .backgroundColor(AppColor.surface)
    .border({ width: AppLine.thin, color: AppColor.border_subtle })
    .borderRadius(AppRadius.row)
  }
}
